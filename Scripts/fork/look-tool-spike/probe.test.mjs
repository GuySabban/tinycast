#!/usr/bin/env node
import assert from "node:assert/strict";
import { mkdtemp, realpath, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { listen, receipt, toolName } from "./loopback.mjs";
import { run } from "./probe.mjs";

const expected = 'שלום "Look" \\ ?';
const privateReceived = "NeverPrintThisMarker94726";
const serverName = "tinycast-look-spike";
const png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2iQAAAAASUVORK5CYII=";
const threadId = "fake-thread";

function mcp(url, token, method, params) {
    return fetch(url, {
        method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params })
    });
}

async function fakeAppServer() {
    const flags = process.argv.slice(2);
    for (const flag of ["mcp_servers.personal.enabled=false", "features.shell_tool=false",
        "features.unified_exec=false", "features.hooks=false", 'model_provider="openai"', 'web_search="disabled"']) {
        assert.ok(flags.includes(flag));
    }
    const token = process.env.SPOTCAST_LOOK_SPIKE_BEARER;
    const key = `mcp_servers.${serverName}`;
    const configured = flags.find((arg) => arg.startsWith(`${key}.url=`));
    const toolURL = configured ? JSON.parse(configured.slice(key.length + 5)) : undefined;
    const endpoint = process.env.SPOTCAST_FAKE_ENDPOINT;
    const override = endpoint !== undefined && toolURL ? JSON.parse(endpoint) : undefined;
    assert.equal(Boolean(token), Boolean(toolURL));
    if (toolURL) {
        assert.ok(flags.includes(`${key}.default_tools_approval_mode="prompt"`));
        assert.ok(flags.includes(`${key}.tool_timeout_sec=90`));
        assert.ok(!flags.some((flag) => flag.includes(token)));
    }
    const send = (object) => console.log(JSON.stringify(object));
    const event = (method, params) => send({ method, params: { threadId, ...params } });
    const finish = (text) => {
        event("item/agentMessage/delta", { delta: text });
        event("turn/completed", { turn: { id: "fake-turn", status: "completed" } });
    };
    for await (const line of createInterface({ input: process.stdin })) {
        const { id, method, params, result } = JSON.parse(line);
        switch (method) {
        case "initialize":
            returnTo(id, {});
            break;
        case "initialized":
            break;
        case "account/read":
            assert.equal(params.refreshToken, false);
            returnTo(id, {
                account: { type: process.env.SPOTCAST_FAKE_ACCOUNT ?? "chatgpt" },
                workspaceRouting: {
                    backendOrigin: override?.backendOrigin ?? "https://chatgpt.com",
                    accountRoutingOverride: "NO_CONSTRAINT", chatgptAccountId: "workspace"
                }
            });
            break;
        case "config/read":
            assert.equal(await realpath(params.cwd), process.cwd());
            assert.equal(params.includeLayers, false);
            returnTo(id, {
                config: {
                    model_provider: "openai", chatgpt_base_url: "https://chatgpt.com/backend-api/",
                    openai_base_url: null, model_providers: {},
                    mcp_servers: { personal: { enabled: false, url: "https://mcp.invalid/server" } },
                    ...override?.config
                },
                origins: override?.origins ?? {}
            });
            break;
        case "configRequirements/read":
            assert.equal(params, undefined);
            returnTo(id, { requirements: override?.requirements ?? null });
            break;
        case "thread/start":
            assert.equal(process.env.SPOTCAST_FAKE_ACCOUNT, undefined);
            assert.equal(override, undefined);
            assert.equal(params.ephemeral, true);
            assert.equal(params.sandbox, "read-only");
            assert.equal(params.config.web_search, "disabled");
            assert.equal(params.approvalPolicy, toolURL ? "untrusted" : "never");
            if (toolURL) {
                const disco = await mcp(toolURL, token, "initialize", { protocolVersion: "2025-06-18" });
                assert.equal((await disco.json()).result.protocolVersion, "2025-06-18");
                const tools = await mcp(toolURL, token, "tools/list");
                assert.deepEqual((await tools.json()).result.tools.map(({ name }) => name), [toolName]);
            }
            returnTo(id, { thread: { id: threadId }, modelProvider: "openai" });
            break;
        case "turn/start":
            assert.deepEqual(params.sandboxPolicy, { type: "readOnly", networkAccess: false });
            assert.equal(params.input[1].url, `data:image/png;base64,${png}`);
            assert.ok(!params.input[0].text.includes(expected));
            returnTo(id, { turn: { id: "fake-turn" } });
            if (toolURL) {
                assert.equal(params.outputSchema, undefined);
                event("item/started", { item: { type: "mcpToolCall", server: serverName, tool: toolName } });
                send({ id: "approval", method: "mcpServer/elicitation/request", params: {
                    threadId, serverName, _meta: { codex_approval_kind: "mcp_tool_call", tool_name: toolName }
                } });
            } else {
                assert.equal(params.outputSchema.properties.suggestions.maxItems, 3);
                finish('{"suggestions":[{"title":"Copy text","symbol":"doc.on.doc","detail":"Copy the line."}]}');
            }
            break;
        case undefined: {
            assert.equal(id, "approval");
            assert.deepEqual(result, { action: "accept" });
            const mismatch = process.env.SPOTCAST_FAKE_MARKER_MISMATCH === "1";
            const response = await mcp(toolURL, token, "tools/call", {
                name: toolName, arguments: { text: mismatch ? privateReceived : expected }
            });
            if (mismatch) {
                assert.deepEqual((await response.json()).result, {
                    isError: true, content: [{ type: "text", text: "Dry run rejected: marker mismatch." }]
                });
                finish(privateReceived);
                break;
            }
            assert.deepEqual((await response.json()).result, { content: [{ type: "text", text: receipt }] });
            finish(receipt);
            break;
        }
        default: assert.fail("Unexpected Codex method");
        }
    }

    function returnTo(id, result) { send({ id, result }); }
}

if (process.argv.at(-1) === "--json") {
    console.log(JSON.stringify([{ name: "personal" }]));
} else if (process.argv.at(-1) === "app-server") {
    await fakeAppServer();
} else {
    test("suggest and act traverse the app-server protocol and live loopback without Codex", async () => {
        const cwd = await mkdtemp(join(tmpdir(), "spotcast-look-fixture-"));
        try {
            const image = join(cwd, "screen.png");
            await writeFile(image, Buffer.from(png, "base64"));
            const args = ["--image", image, "--codex", fileURLToPath(import.meta.url)];
            await assert.rejects(run(["suggest", ...args]), /confirm-upload/);
            await run(["check-endpoint", "--codex", fileURLToPath(import.meta.url)]);
            process.env.SPOTCAST_FAKE_ACCOUNT = "apiKey";
            try {
                await assert.rejects(run(["suggest", ...args, "--confirm-upload"]), /no screenshot was sent/);
            } finally {
                delete process.env.SPOTCAST_FAKE_ACCOUNT;
            }
            await run(["suggest", ...args, "--confirm-upload"]);
            await run(["act", ...args, "--confirm-upload", "--expect", expected, "--hold-60s"], 20);
        } finally {
            await rm(cwd, { force: true, recursive: true });
        }
    });

    test("the armed act server rejects endpoint overrides before starting a thread", async () => {
        const args = ["act", "--image", "must-not-be-read.png", "--codex", fileURLToPath(import.meta.url),
            "--confirm-upload", "--expect", expected, "--hold-60s"];
        const url = "https://user:secret@unexpected.invalid:8443/private?token=secret#fragment";
        const origin = "(https://unexpected.invalid)";
        const overrides = [
            [{ config: { chatgpt_base_url: url } }, [`config.chatgpt_base_url ${origin}`]],
            [{ origins: { chatgpt_base_url: { name: { type: "user", file: "/private/config.toml" } } } },
                ["config.chatgpt_base_url (https://chatgpt.com)"]],
            [{ config: { chatgpt_base_url: "https://chatgpt.com/backend-api" } },
                ["config.chatgpt_base_url (https://chatgpt.com)"]],
            [{ config: { openai_base_url: url } }, [`config.openai_base_url ${origin}`]],
            [{ config: { model_providers: { openai: { base_url: url } } } },
                [`config.model_providers.openai.base_url ${origin}`]],
            [{ config: { model_providers: { custom: { base_url: url } } } },
                [`config.model_providers.custom.base_url ${origin}`]],
            [{ requirements: { model_providers: { custom: { base_url: url } } } },
                [`requirements.model_providers.custom.base_url ${origin}`]],
            [{ requirements: { chatgpt_base_url: "https://chatgpt.com/backend-api/" } },
                ["requirements.chatgpt_base_url (https://chatgpt.com)"]],
            [{ backendOrigin: "https://chatgpt.com:8443", config: { openai_base_url: url } },
                ["account/read.workspaceRouting.backendOrigin (https://chatgpt.com)", `config.openai_base_url ${origin}`]]
        ];
        try {
            for (const [override, findings] of overrides) {
                process.env.SPOTCAST_FAKE_ENDPOINT = JSON.stringify(override);
                await assert.rejects(run(args), ({ message }) => {
                    assert.match(message, /^Codex endpoint check refused: .*; no screenshot was sent\.$/);
                    for (const finding of findings) assert.ok(message.includes(finding), message);
                    assert.doesNotMatch(message, /secret|private|token|fragment|8443/);
                    return true;
                });
            }
        } finally {
            delete process.env.SPOTCAST_FAKE_ENDPOINT;
        }
    });

    test("endpoint preflight rejects base-URL overrides from the environment", async () => {
        const keys = ["OPENAI_BASE_URL", "CODEX_OPENAI_BASE_URL"];
        try {
            for (const key of keys) {
                process.env[key] = "https://unexpected.invalid";
            }
            await assert.rejects(run(["check-endpoint"]), {
                message: "Codex endpoint check refused: env.OPENAI_BASE_URL; env.CODEX_OPENAI_BASE_URL; no screenshot was sent."
            });
        } finally {
            for (const key of keys) delete process.env[key];
        }
    });

    test("loopback requires the bearer, rejects bad arguments and closes", async () => {
        const messages = [];
        const bridge = await listen(expected, 0, (message) => messages.push(message));
        try {
            assert.equal(new URL(bridge.url).hostname, "127.0.0.1");
            const denied = await mcp(bridge.url, "not-our-token", "tools/list");
            assert.equal(denied.status, 401);
            assert.equal(bridge.evidence.calls, 0);
            bridge.arm();
            const wrong = await mcp(bridge.url, bridge.token, "tools/call", {
                name: toolName, arguments: { text: expected, unsupported: true }
            });
            const wrongResult = (await wrong.json()).result;
            assert.equal(wrongResult.isError, true);
            assert.match(wrongResult.content[0].text, /invalid arguments \(additional properties are not allowed\)/);
            const repeated = await mcp(bridge.url, bridge.token, "tools/call", {
                name: toolName, arguments: { text: expected }
            });
            const repeatedResult = (await repeated.json()).result;
            assert.equal(repeatedResult.isError, true);
            assert.match(repeatedResult.content[0].text, /repeated call/);
            assert.ok(messages.includes("Tool call rejected: repeated call."));
            assert.equal(bridge.evidence.matched, false);
        } finally {
            bridge.close();
        }
        await assert.rejects(mcp(bridge.url, bridge.token, "tools/list"));
    });

    async function rejectedCall(target, args, reason, { armed = true, name = toolName } = {}) {
        const messages = [];
        const bridge = await listen(target, 0, (message) => messages.push(message));
        try {
            if (armed) bridge.arm();
            const response = await mcp(bridge.url, bridge.token, "tools/call", { name, arguments: args });
            assert.deepEqual((await response.json()).result, {
                isError: true, content: [{ type: "text", text: "Dry run rejected: " + reason + "." }]
            });
            assert.ok(messages.includes("Tool call rejected: " + reason + "."));
            assert.equal(bridge.evidence.matched, false);
            return messages;
        } finally {
            bridge.close();
        }
    }

    test("loopback names not-armed and individual argument-schema rejections without echoing values", async () => {
        await rejectedCall(expected, { text: expected }, "not armed", { armed: false });
        await rejectedCall(expected, { text: expected }, "invalid arguments (tool name must be copy_text)",
            { name: privateReceived });
        for (const [args, rule] of [
            [null, "arguments must be an object"],
            [[privateReceived], "arguments must be an object"],
            [{}, "text is required"],
            [{ text: { value: privateReceived } }, "text must be a string"],
            [{ text: "" }, "text minLength is 1 code point"],
            [{ text: "😀".repeat(201) }, "text maxLength is 200 code points"]
        ]) {
            const messages = await rejectedCall(expected, args, "invalid arguments (" + rule + ")");
            assert.doesNotMatch(messages.join("\n"), /NeverPrintThisMarker|94726|😀|U\+1F600/);
        }
    });

    test("mismatch diagnostics distinguish transformations and redact letters and digits", async () => {
        for (const [target, text, ...diagnostics] of [
            ["é", "e\u0301", "code-point length received=2 expected=1", "NFC match=true"],
            ['"a-b c"', "“a—b\u00A0c”", "ASCII punctuation/NBSP match=true", "received=Pi U+201C, expected=Po U+0022"],
            ["a b", "a\u00A0b", "received=Zs U+00A0, expected=Zs U+0020"],
            ["a b", " a \t b ", "collapsed whitespace match=true"],
            ["abc", "\u200E\u200F\u202A\u202B\u202C\u202D\u202E\u2066\u2067\u2068\u2069abc",
                "without bidi/format characters match=true", "received=Cf U+200E, expected=redacted"],
            ["abc", "LOOK SPIKE: abc", "expected substring=true", "first differing index (0-based)=0"],
            ["😀a", "😀" + privateReceived, "code-point length received=26 expected=2",
                "first differing index (0-based)=1, received=redacted, expected=redacted"],
            ["a", "7", "first differing index (0-based)=0, received=redacted, expected=redacted"],
            ["abc", "ab", "received=end of marker, expected=redacted"]
        ]) {
            const output = (await rejectedCall(target, { text }, "marker mismatch")).join("\n");
            for (const diagnostic of diagnostics) assert.ok(output.includes(diagnostic), output);
            assert.doesNotMatch(output, /NeverPrintThisMarker|94726|LOOK SPIKE|U\+004E|U\+0061|U\+0037|😀/);
        }
    });

    test("act prints the bridge diagnosis but not a model reply echoing the rejected marker", async (t) => {
        const cwd = await mkdtemp(join(tmpdir(), "spotcast-look-mismatch-"));
        const messages = [];
        t.mock.method(console, "log", (...args) => messages.push(args.join(" ")));
        try {
            const image = join(cwd, "screen.png");
            await writeFile(image, Buffer.from(png, "base64"));
            process.env.SPOTCAST_FAKE_MARKER_MISMATCH = "1";
            await assert.rejects(run(["act", "--image", image, "--codex", fileURLToPath(import.meta.url),
                "--confirm-upload", "--expect", expected, "--hold-60s"], 20), /Act evidence incomplete/);
            const output = messages.join("\n");
            assert.match(output, /Tool call rejected: marker mismatch/);
            assert.match(output, /Marker diagnosis: code-point length/);
            assert.doesNotMatch(output, /NeverPrintThisMarker|94726|U\+004E/);
        } finally {
            delete process.env.SPOTCAST_FAKE_MARKER_MISMATCH;
            await rm(cwd, { force: true, recursive: true });
        }
    });
}
