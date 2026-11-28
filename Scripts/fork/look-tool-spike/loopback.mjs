import { randomBytes, timingSafeEqual } from "node:crypto";
import { once } from "node:events";
import { createServer } from "node:http";
import { setTimeout as delay } from "node:timers/promises";

export const toolName = "copy_text";
export const receipt = "look-spike-tool-returned";
export const maxMarkerLength = 200;
const versions = ["2025-11-25", "2025-06-18", "2025-03-26"];
const tool = {
    name: toolName,
    description: "Dry run: accepts a visible test marker without copying it or changing anything.",
    inputSchema: {
        type: "object", properties: { text: { type: "string", minLength: 1, maxLength: maxMarkerLength } },
        required: ["text"], additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false }
};

const reportableCategories = [
    ["Pc", /\p{Pc}/u], ["Pd", /\p{Pd}/u], ["Ps", /\p{Ps}/u], ["Pe", /\p{Pe}/u],
    ["Pi", /\p{Pi}/u], ["Pf", /\p{Pf}/u], ["Po", /\p{Po}/u],
    ["Zs", /\p{Zs}/u], ["Zl", /\p{Zl}/u], ["Zp", /\p{Zp}/u], ["Cf", /\p{Cf}/u]
];

function describeDifference(character) {
    if (character === undefined) return "end of marker";
    const category = reportableCategories.find(([, pattern]) => pattern.test(character))?.[0];
    if (!category) return "redacted";
    return category + " U+" + character.codePointAt(0).toString(16).toUpperCase().padStart(4, "0");
}

function asciiPunctuation(text) {
    return text.replace(/[\u2018-\u201B]/gu, "'").replace(/[\u201C-\u201F]/gu, '"')
        .replace(/[\p{Pd}\u2212]/gu, "-").replace(/[\u00A0\u202F]/gu, " ");
}

function collapseWhitespace(text) {
    return text.replace(/\p{White_Space}+/gu, " ").trim();
}

function markerDiagnosis(received, expected) {
    const actual = [...received];
    const target = [...expected];
    let index = 0;
    while (index < actual.length && actual[index] === target[index]) index += 1;
    return [
        "Marker diagnosis: code-point length received=" + actual.length + " expected=" + target.length,
        "NFC match=" + (received.normalize("NFC") === expected.normalize("NFC")),
        "ASCII punctuation/NBSP match=" + (asciiPunctuation(received) === asciiPunctuation(expected)),
        "collapsed whitespace match=" + (collapseWhitespace(received) === collapseWhitespace(expected)),
        "without bidi/format characters match=" + (received.replace(/\p{Cf}/gu, "") === expected.replace(/\p{Cf}/gu, "")),
        "expected substring=" + received.includes(expected),
        "first differing index (0-based)=" + index +
            ", received=" + describeDifference(actual[index]) + ", expected=" + describeDifference(target[index])
    ].join("; ") + ".";
}

function argumentRule(params) {
    if (params?.name !== toolName) return "tool name must be copy_text";
    const args = params.arguments;
    if (!args || typeof args !== "object" || Array.isArray(args)) return "arguments must be an object";
    if (!Object.hasOwn(args, "text")) return "text is required";
    if (Object.keys(args).length !== 1) return "additional properties are not allowed";
    if (typeof args.text !== "string") return "text must be a string";
    if (args.text.length === 0) return "text minLength is 1 code point";
    if ([...args.text].length > maxMarkerLength) return "text maxLength is " + maxMarkerLength + " code points";
    return null;
}

function reply(response, status, payload) {
    response.writeHead(status, payload === undefined ? {} : { "Content-Type": "application/json" });
    response.end(payload === undefined ? undefined : JSON.stringify(payload));
}

export async function listen(expected, holdMS, report) {
    const token = randomBytes(32).toString("hex");
    const authorization = Buffer.from(`Bearer ${token}`);
    const lifetime = new AbortController();
    const evidence = { calls: 0, matched: false, heldMS: null };
    let mayCall = false;

    const server = createServer({ requestTimeout: 5_000, headersTimeout: 5_000 }, (request, response) => {
        handle(request, response).catch(() => {
            if (!response.destroyed && !response.headersSent) reply(response, 400);
        });
    });
    server.maxConnections = 8;
    server.setTimeout(holdMS + 5_000, (socket) => socket.destroy());

    async function handle(request, response) {
        if (request.url !== "/mcp") return reply(response, 404);
        const header = Buffer.from(request.headers.authorization ?? "");
        if (header.length !== authorization.length || !timingSafeEqual(header, authorization)) {
            return reply(response, 401);
        }
        if (request.method !== "POST") {
            response.setHeader("Allow", "POST");
            return reply(response, 405);
        }
        const chunks = [];
        let length = 0;
        for await (const chunk of request) {
            length += chunk.length;
            if (length > 8192) return reply(response, 413);
            chunks.push(chunk);
        }
        const { jsonrpc, id, method, params } = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (jsonrpc !== "2.0" || typeof method !== "string") return reply(response, 400);
        if (id === undefined) return reply(response, 202);
        const send = (result) => reply(response, 200, { jsonrpc, id, result });
        switch (method) {
        case "initialize":
            return send({
                protocolVersion: versions.includes(params?.protocolVersion) ? params.protocolVersion : versions[0],
                capabilities: { tools: {} }, serverInfo: { name: "Spotcast Look spike", version: "1" }
            });
        case "ping":
            return send({});
        case "tools/list":
            return send({ tools: [tool] });
        case "tools/call": {
            evidence.calls += 1;
            const reject = (reason) => {
                report("Tool call rejected: " + reason + ".");
                return send({ isError: true, content: [{ type: "text", text: "Dry run rejected: " + reason + "." }] });
            };
            if (!mayCall) return reject("not armed");
            if (evidence.calls !== 1) return reject("repeated call");
            const rule = argumentRule(params);
            if (rule) return reject("invalid arguments (" + rule + ")");
            if (params.arguments.text !== expected) {
                report(markerDiagnosis(params.arguments.text, expected));
                return reject("marker mismatch");
            }
            evidence.matched = true;
            report(`Tool call 1: arguments match; withholding reply for ${holdMS} ms.`);
            const started = performance.now();
            const deadline = started + holdMS;
            while (performance.now() < deadline) {
                await delay(Math.ceil(deadline - performance.now()), undefined, { signal: lifetime.signal });
            }
            evidence.heldMS = Math.floor(performance.now() - started);
            send({ content: [{ type: "text", text: receipt }] });
            report(`Tool reply sent after ${evidence.heldMS} ms.`);
            return;
        }
        default:
            return reply(response, 200, { jsonrpc, id, error: { code: -32601, message: "Unknown method" } });
        }
    }

    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    return {
        url: `http://127.0.0.1:${server.address().port}/mcp`, token, evidence,
        arm: () => { mayCall = true; },
        close: () => {
            lifetime.abort();
            server.close();
            server.closeAllConnections();
        }
    };
}
