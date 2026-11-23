import { randomBytes, timingSafeEqual } from "node:crypto";
import { once } from "node:events";
import { createServer } from "node:http";
import { setTimeout as delay } from "node:timers/promises";

export const toolName = "copy_text";
export const receipt = "look-spike-tool-returned";
const versions = ["2025-11-25", "2025-06-18", "2025-03-26"];
const tool = {
    name: toolName,
    description: "Dry run: accepts a visible test marker without copying it or changing anything.",
    inputSchema: {
        type: "object", properties: { text: { type: "string", minLength: 1, maxLength: 200 } },
        required: ["text"], additionalProperties: false
    },
    annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false }
};

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
            const args = params?.arguments;
            if (!mayCall || evidence.calls !== 1 || params?.name !== toolName ||
                !args || Object.keys(args).length !== 1 ||
                typeof args.text !== "string" || args.text.length > 200 || args.text !== expected) {
                report("Tool call rejected (not armed, repeated, invalid, or marker mismatch).");
                return send({ isError: true, content: [{ type: "text", text: "Dry run rejected." }] });
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
