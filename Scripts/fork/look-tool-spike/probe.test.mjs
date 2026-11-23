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
    const baseURL = process.env.SPOTCAST_FAKE_BASE_URL;
    const expectedAbort = baseURL !== undefined && toolURL;
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
            returnTo(id, { account: { type: process.env.SPOTCAST_FAKE_ACCOUNT ?? "chatgpt" } });
            break;
        case "config/read":
            assert.equal(await realpath(params.cwd), process.cwd());
            assert.equal(params.includeLayers, false);
            returnTo(id, {
                config: { model_provider: "openai", chatgpt_base_url: expectedAbort ? baseURL : undefined },
                origins: expectedAbort ? { chatgpt_base_url: { name: { type: "user" } } } : {}
            });
            break;
        case "configRequirements/read":
            assert.equal(params, undefined);
            returnTo(id, { requirements: null });
            break;
        case "thread/start":
            assert.equal(process.env.SPOTCAST_FAKE_ACCOUNT, undefined);
            assert.ok(!expectedAbort);
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
            const response = await mcp(toolURL, token, "tools/call", { name: toolName, arguments: { text: expected } });
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
        try {
            for (const url of ["https://unexpected.invalid/backend-api", "https://chatgpt.com/backend-api/"]) {
                process.env.SPOTCAST_FAKE_BASE_URL = url;
                await assert.rejects(run(args), /endpoint override or non-default origin; no screenshot was sent/);
            }
        } finally {
            delete process.env.SPOTCAST_FAKE_BASE_URL;
        }
    });

    test("loopback requires the bearer, rejects bad arguments and closes", async () => {
        const bridge = await listen(expected, 0, () => {});
        try {
            assert.equal(new URL(bridge.url).hostname, "127.0.0.1");
            const denied = await mcp(bridge.url, "not-our-token", "tools/list");
            assert.equal(denied.status, 401);
            assert.equal(bridge.evidence.calls, 0);
            bridge.arm();
            const wrong = await mcp(bridge.url, bridge.token, "tools/call", {
                name: toolName, arguments: { text: expected, unsupported: true }
            });
            assert.equal((await wrong.json()).result.isError, true);
            const repeated = await mcp(bridge.url, bridge.token, "tools/call", {
                name: toolName, arguments: { text: expected }
            });
            assert.equal((await repeated.json()).result.isError, true);
            assert.equal(bridge.evidence.matched, false);
        } finally {
            bridge.close();
        }
        await assert.rejects(mcp(bridge.url, bridge.token, "tools/list"));
    });
}
