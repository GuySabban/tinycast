import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import { createInterface } from "node:readline/promises";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { parseArgs, stripVTControlCharacters } from "node:util";
import { analyzeTrace, startTrace, traceTargets } from "./owner-trace.mjs";

const probe = fileURLToPath(new URL("./probe.mjs", import.meta.url));
const marker = "M3TEST5271 שלום";
const maxBytes = 10 * 1024 * 1024;
const screens = ["English mail (include known 11-point text)", "Hebrew mail (include known 11-point text)",
    "English calendar invite", "Hebrew event flyer", "PDF", "long web article", "chat", "document",
    "map or directions", "busy spreadsheet"];
const usage = "Usage: run-owner-checks.sh --model MODEL [--codex /absolute/path] [--from act|suggest] [--no-schema]";
const captureReasons = {
    "display count unavailable": "Could not determine the active displays. Run from a logged-in macOS desktop.",
    "front app unavailable": "Could not identify the front app. Bring the sample app forward during the countdown.",
    "main display bounds unavailable": "Could not read the main display bounds.",
    "front window bounds unavailable": "Could not find an onscreen window for the front app. Bring its window forward.",
    "front window outside main display": "The front window is not entirely on the main display. Move it there and rerun.",
    "macOS desktop query failed": "Could not query the macOS desktop. Run from a logged-in macOS Terminal.",
    "main display capture failed": "Could not capture the main display. Check Screen Recording permission for Terminal."
};

export function settings(args) {
    const { values } = parseArgs({ args, options: {
        model: { type: "string" }, codex: { type: "string" }, from: { type: "string", default: "act" },
        "no-schema": { type: "boolean" }, help: { type: "boolean" }
    } });
    if (values.help) return { help: true };
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(values.model ?? "") ||
        !["act", "suggest"].includes(values.from) || (values.codex !== undefined && !isAbsolute(values.codex))) {
        throw new Error(usage);
    }
    return { model: values.model, codex: values.codex ?? "codex", from: values.from, comparison: !!values["no-schema"] };
}

function percentiles(values) {
    const sorted = values.filter((n) => Number.isFinite(n) && n >= 0).sort((a, b) => a - b);
    if (sorted.length === 0) return null;
    const middle = (sorted.length - 1) / 2;
    return { median: (sorted[Math.floor(middle)] + sorted[Math.ceil(middle)]) / 2,
        p95: sorted[Math.ceil(0.95 * sorted.length) - 1], n: sorted.length };
}

function metric(result) {
    return result ? result.median + "/" + result.p95 + " ms (n=" + result.n + ")" : "n/a";
}

function scores(rows, key) {
    const values = rows.map((row) => row[key]).filter((n) => Number.isInteger(n) && n >= 1 && n <= 5);
    return values.length ? (values.reduce((sum, n) => sum + n, 0) / values.length).toFixed(1) +
        "/5 (n=" + values.length + ")" : "n/a";
}

function safe(value, pattern) { return typeof value === "string" && pattern.test(value) ? value : "unknown"; }
function count(n) { return Number.isSafeInteger(n) && n >= 0 ? n : "unknown"; }

export function report(state) {
    const { facts, acts, row10, schema, comparison } = state;
    const out = ["Spotcast Look owner checks",
        "macOS " + safe(facts.os, /^\d+(?:\.\d+){1,2}$/) + "; " +
        safe(facts.chip, /^Apple M\d+(?: Pro| Max| Ultra)?$|^Intel$/) + "; Node " +
        safe(facts.node, /^v\d+\.\d+\.\d+$/) + "; Codex " +
        safe(facts.codex, /^\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?$/) + "; model " +
        safe(facts.model, /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/) +
        "; login " + safe(facts.login, /^(ChatGPT|not verified)$/),
        "Endpoint preflight: " + (state.endpoint ? "pass" : "not passed") +
        "; personal MCP disabled: " + count(state.disabled)];
    out.push("Act: " + (acts.map(({ kind, pass, reason, elapsed, held, restart, thread }) =>
        safe(kind, /^(short|hold|restart 1|restart 2)$/) + " " +
        (pass ? "pass" : "fail: " + safe(reason, /^(not armed|repeated call|invalid arguments|marker mismatch|evidence incomplete)$/)) +
        " (turn " + count(elapsed) + ", held " + count(held) + ", init " + count(restart) +
        ", thread " + count(thread) + " ms)").join("; ") || "not run"));
    const short = acts.filter(({ kind, pass }) => kind !== "hold" && pass);
    if (short.length) {
        const timings = percentiles(short.map(({ restart }) => restart));
        out.push("Short restart median/p95: " + metric(timings) +
            (timings?.n === 3 ? "; <1 s median: " + (timings.median < 1000 ? "met" : "missed") : ""));
    }
    out.push("Row 10: " + (row10 ?
        safe(row10.status, /^(pass|fail|inconclusive)$/) + "; personal stdio matches " +
            count(row10.personalProcess) + ", personal HTTP packet matches " + count(row10.personalHTTP) +
            ", other peers " + count(row10.otherPeer) + ", ambiguous observations " + count(row10.ambiguous) +
            " (possible stdio " + count(row10.possibleStdio) + ", shared provider/bridge peer " + count(row10.sharedPeer) +
            ", proxied peer " + count(row10.proxiedPeer) + ", unattributed personal peer " +
            count(row10.unattributedPeer) + ")" :
        "not run"));
    for (const [name, rows] of [["Schema", schema], ["No-schema", comparison]]) {
        if (!rows.length) { out.push(name + ": not run"); continue; }
        const valid = rows.filter(({ valid }) => valid).length;
        const timing = percentiles(rows.map(({ elapsed }) => elapsed));
        const sizes = ["large", "compact"].map((size) => size + " " +
            metric(percentiles(rows.filter((row) => row.size === size).map(({ elapsed }) => elapsed)))).join("; ");
        out.push(name + ": " + valid + "/" + rows.length + " valid JSON" +
            (rows.length === 20 ? " (19/20 target " + (valid >= 19 ? "met" : "missed") + ")" : " (partial)") +
            "; median/p95 " + metric(timing) + (timing?.n === 20 ? " (<4 s " + (timing.median < 4000 ? "met" : "missed") + ")" : "") +
            "; " + sizes + "; readability " + scores(rows, "readability") +
            ", usefulness " + scores(rows, "usefulness") + "; correct language " +
            rows.filter(({ language }) => language === "y").length + "/" +
            rows.filter(({ language }) => language === "y" || language === "n").length);
    }
    if (state.stop) out.push("Stopped: " + (Object.hasOwn(captureReasons, state.stop) ? state.stop : safe(state.stop,
        /^(environment|endpoint preflight|capture or Preview approval|act safety gate|personal MCP activity|suggest endpoint\/setup(?: or protocol)?|interrupted|local check)$/)));
    out.push("Cleanup: " + safe(state.cleanup, /^(deleted|kept|not needed|could not delete)$/));
    return out.join("\n");
}

class Stop extends Error {}

function local(command, args, options) {
    return spawnSync(command, args, { encoding: "utf8", timeout: 20_000, maxBuffer: 2 * 1024 * 1024, ...options });
}

function mcpList(options) {
    const list = local(options.codex, ["mcp", "list", "--json"], { cwd: options.dir });
    try {
        const entries = JSON.parse(list.stdout);
        return list.status === 0 && Array.isArray(entries) ? entries : null;
    } catch { return null; }
}

function runProbe(options, args) {
    const child = spawn(process.execPath, [probe, ...args, "--codex", options.codex],
        { stdio: ["ignore", "pipe", "pipe"] });
    options.active = child;
    return new Promise((resolve) => {
        let stdout = "", stderr = "", overflow = false;
        const append = (prior, chunk) => {
            if (prior.length + chunk.length > 1024 * 1024) { overflow = true; return prior; }
            return prior + chunk;
        };
        child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout = append(stdout, chunk); });
        child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr = append(stderr, chunk); });
        child.on("error", () => {});
        child.on("close", (code) => {
            options.active = null;
            resolve({ ok: code === 0 && !overflow, code: overflow ? null : code, stdout, stderr });
        });
    });
}

function number(text, pattern) {
    const match = pattern.exec(text);
    return match ? Number(match[1]) : undefined;
}

function capture(path, options) {
    if (options.interrupted) throw new Stop("interrupted");
    const app = frontApp();
    if (local("/usr/sbin/screencapture", ["-x", "-m", path]).status !== 0) {
        stopCapture("main display capture failed");
    }
    return app;
}

function dimensions(path) {
    const result = local("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", path]);
    if (result.status !== 0) throw new Stop("capture or Preview approval");
    const width = number(result.stdout, /pixelWidth: (\d+)/);
    const height = number(result.stdout, /pixelHeight: (\d+)/);
    const bytes = statSync(path).size;
    if (!width || !height || !bytes) throw new Stop("capture or Preview approval");
    return { width, height, bytes, edge: Math.max(width, height) };
}

function jpeg(source, path, edge) {
    for (const quality of [85, 75, 60, 45]) {
        if (local("/usr/bin/sips", ["-s", "format", "jpeg", "-s", "formatOptions", String(quality),
            "-Z", String(edge), source, "--out", path]).status !== 0) break;
        const info = dimensions(path);
        if (info.edge <= edge && info.bytes <= maxBytes) return info;
    }
    throw new Stop("capture or Preview approval");
}

async function countdown(ask, label) {
    await ask("Press Enter, then bring " + label + " to the front on the main display.");
    for (let seconds = 5; seconds > 0; seconds -= 1) {
        console.log("Capture in " + seconds + "…");
        await delay(1000);
    }
}

async function approve(ask, paths) {
    if (local("/usr/bin/open", ["-a", "Preview", ...paths]).status !== 0 ||
        await ask("Inspect " + (paths.length === 1 ? "the exact file" : "both exact files") +
            " in Preview. Type y to allow upload to OpenAI; anything else stops:") !== "y") {
        throw new Stop("capture or Preview approval");
    }
}

function printActFailure({ stdout, stderr }) {
    if (stderr.includes("Act evidence incomplete:")) {
        for (const line of stdout.split("\n")) {
            if (/^(Tool call rejected|Marker diagnosis):? /.test(line)) console.log(stripVTControlCharacters(line));
        }
    }
    console.log("Act failed. No further uploads; see the manual troubleshooting table.");
}

async function act(options, ask, state, inventory, authorizeTrace) {
    const fixture = join(options.dir, "act-fixture.txt");
    writeFileSync(fixture, "LOOK SPIKE: " + marker + "\n", { mode: 0o600 });
    if (local("/usr/bin/open", ["-a", "TextEdit", fixture]).status !== 0) throw new Stop("capture or Preview approval");
    await countdown(ask, "the TextEdit fixture (make the marker clearly visible)");
    const original = join(options.dir, "act.png");
    capture(original, options);
    let image = original;
    if (statSync(original).size > maxBytes) {
        image = join(options.dir, "act.jpg");
        jpeg(original, image, 4096);
    }
    await approve(ask, [image]);
    const targets = await traceTargets(inventory ?? []);
    let trace;
    const runs = [];
    const proxy = Object.keys(process.env).some((key) => /^(https?|all)_proxy$/i.test(key) && process.env[key]);
    let actError;
    try {
        if (authorizeTrace()) trace = await startTrace(targets);
        if (!trace?.ready) console.log("Trace sanity check unavailable; row 10 cannot pass.");
        for (const kind of ["short", "hold", "restart 1", "restart 2"]) {
            if (options.interrupted) throw new Stop("interrupted");
            if (kind !== "short") await approve(ask, [image]);
            const result = await runProbe(options, ["act", "--confirm-upload", "--image", image, "--model", options.model,
                "--expect", marker, ...(kind === "hold" ? ["--hold-60s"] : [])]);
            const { stdout } = result;
            runs.push({
                root: number(stdout, /^Trace root \(probe PID\): (\d+)\.$/m),
                appServers: Array.from(stdout.matchAll(/^App-server PID \((?:initial|armed)\): (\d+)\.$/gm), (m) => Number(m[1])),
                port: number(stdout, /^Expected MCP connection: http:\/\/127\.0\.0\.1:(\d+)\b/m)
            });
            const reason = /^Tool call rejected: (not armed|repeated call|invalid arguments|marker mismatch)[.( ]/m.exec(stdout)?.[1];
            state.acts.push({ kind, pass: result.ok, reason: reason ?? "evidence incomplete",
                elapsed: number(stdout, /^Turn status: .*; (\d+) ms\.$/m),
                held: number(stdout, /^Tool reply sent after (\d+) ms\.$/m),
                restart: number(stdout, /^Restart through initialize: (\d+) ms\.$/m),
                thread: number(stdout, /^Restart through thread\/start: (\d+) ms\.$/m) });
            if (!result.ok) { printActFailure(result); throw new Stop("act safety gate"); }
            console.log("Act " + kind + " passed.");
            if (trace && analyzeTrace(trace.snapshot(), runs, targets, { proxy }).status === "fail") {
                throw new Stop("personal MCP activity");
            }
        }
    } catch (error) { actError = error; }
    finally {
        const evidence = trace ? await trace.stop() : { complete: false, events: [], packets: [] };
        state.row10 = analyzeTrace(evidence, runs, targets, {
            configStable: inventory !== null && JSON.stringify(inventory) === JSON.stringify(mcpList(options)),
            proxy
        });
    }
    if (state.row10.status === "fail") throw new Stop("personal MCP activity");
    if (actError) throw actError;
}

export function primaryCaptureContext({ app, window, display, displayCount }) {
    const rectangle = (bounds) => Array.isArray(bounds) && bounds.length === 4 &&
        bounds.every(Number.isFinite) && bounds[2] > 0 && bounds[3] > 0;
    if (!Array.isArray(app) || app.length !== 2 || !app.every((part) => typeof part === "string" && part)) {
        return { reason: "front app unavailable" };
    }
    if (!Number.isSafeInteger(displayCount) || displayCount < 1) return { reason: "display count unavailable" };
    if (displayCount === 1) return { app };
    if (!rectangle(display)) return { reason: "main display bounds unavailable" };
    if (!rectangle(window)) return { reason: "front window bounds unavailable" };
    const [x, y, width, height] = window;
    const [left, top, displayWidth, displayHeight] = display;
    return x >= left && y >= top && x + width <= left + displayWidth && y + height <= top + displayHeight
        ? { app } : { reason: "front window outside main display" };
}

function stopCapture(reason) {
    console.log(captureReasons[reason]);
    throw new Stop(reason);
}

function frontApp() {
    const result = local("/usr/bin/osascript", ["-l", "JavaScript", "-e",
        `ObjC.import("AppKit");
        ObjC.import("CoreGraphics");
        var a = $.NSWorkspace.sharedWorkspace.frontmostApplication;
        var context = {
            app: [ObjC.unwrap(a.localizedName), ObjC.unwrap(a.bundleIdentifier)],
            displayCount: Number($.NSScreen.screens.count)
        };
        if (context.displayCount > 1) {
            var flags = $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements;
            var windows = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(flags, $.kCGNullWindowID)));
            var front = Array.isArray(windows) && windows.find(function(w) {
                return w.kCGWindowOwnerPID === a.processIdentifier && w.kCGWindowLayer === 0;
            });
            var b = front && front.kCGWindowBounds;
            var d = $.CGDisplayBounds($.CGMainDisplayID());
            if (b) context.window = [b.X, b.Y, b.Width, b.Height];
            context.display = [d.origin.x, d.origin.y, d.size.width, d.size.height];
        }
        JSON.stringify(context);`]);
    if (result.status !== 0) stopCapture("macOS desktop query failed");
    let context;
    try {
        context = primaryCaptureContext(JSON.parse(result.stdout));
    } catch {
        stopCapture("macOS desktop query failed");
    }
    if (context.reason) stopCapture(context.reason);
    return context.app;
}

export function recordSuggestResult(rows, size, { ok, code, stdout, stderr }) {
    const elapsed = number(stdout, /^Turn status: completed; (\d+) ms\.$/m);
    const valid = ok && /^Suggest JSON parsed and passed the shape and length checks\.$/m.test(stdout);
    const invalid = code === 1 && stderr.trim() === "Suggest JSON failed validation.";
    if (!/^Verified Codex endpoint: /m.test(stdout) || elapsed === undefined || (!valid && !invalid)) {
        throw new Stop("suggest endpoint/setup or protocol");
    }
    const row = { size, elapsed, valid };
    rows.push(row);
    return row;
}

async function suggestPair(options, ask, screen, rows, comparison) {
    await approve(ask, screen.images);
    for (const [i, size] of ["large", "compact"].entries()) {
        if (options.interrupted) throw new Stop("interrupted");
        const result = await runProbe(options, ["suggest", "--confirm-upload", "--model", options.model,
            "--image", screen.images[i], "--language", screen.language, "--app", screen.name,
            "--bundle-id", screen.bundle, "--window-title", "Spike sample " + screen.id,
            ...(comparison ? ["--no-schema"] : [])]);
        const row = recordSuggestResult(rows, size, result);
        if (!row.valid) { console.log(size + ": no valid suggestions."); continue; }
        const raw = result.stdout.split("\n").find((line) => line.startsWith('{"suggestions":'));
        console.log(size + " (local suggestions — do not paste):\n" + stripVTControlCharacters(raw ?? ""));
        const score = async (label) => {
            for (;;) {
                const answer = await ask(label + " 1–5, or Enter to skip:");
                if (!answer) return undefined;
                if (/^[1-5]$/.test(answer)) return Number(answer);
            }
        };
        row.readability = await score("Readability (did it read the expected screen fact?)");
        row.usefulness = await score("Usefulness");
        row.language = await ask("Correct interface language? y / n / Enter to skip:");
    }
}

async function suggest(options, ask, state) {
    const samples = [];
    for (const [index, label] of screens.entries()) {
        const id = String(index + 1).padStart(2, "0");
        const language = await ask("Screen " + id + "/10: prepare mock " + label +
            "; note one expected reading/action privately. Interface language [en-US]:") || "en-US";
        if (!/^[a-z]{2,8}(?:-[a-z0-9]{1,8}){0,5}$/i.test(language)) throw new Stop("suggest endpoint/setup");
        await countdown(ask, "screen " + id);
        const source = join(options.dir, id + ".png");
        const [name, bundle] = capture(source, options);
        const images = ["large", "compact"].map((size) => join(options.dir, id + "-" + size + ".jpg"));
        const large = jpeg(source, images[0], 4096);
        const compact = jpeg(source, images[1], large.edge > 2048 ? 2048 : Math.max(1, Math.floor(large.edge * 0.75)));
        if (compact.edge >= large.edge) throw new Stop("capture or Preview approval");
        console.log([large, compact].map(({ width, height, bytes }) => width + "×" + height + ", " + bytes + " bytes").join(" / "));
        const screen = { id, images, name, bundle, language };
        samples.push(screen);
        await suggestPair(options, ask, screen, state.schema, false);
    }
    if (options.comparison) {
        for (const screen of samples) {
            console.log("No-schema comparison " + screen.id + "/10.");
            await suggestPair(options, ask, screen, state.comparison, true);
        }
    }
}

async function main(args) {
    let options;
    try { options = settings(args); } catch { console.error(usage); process.exitCode = 2; return; }
    if (options.help) { console.log(usage); return; }
    if (process.platform !== "darwin" || !process.stdin.isTTY || !process.stdout.isTTY ||
        Number(process.versions.node.split(".")[0]) < 22) {
        console.error("Run interactively in macOS Terminal with Node 22+.");
        process.exitCode = 2;
        return;
    }
    const state = { facts: { node: process.version, model: options.model }, acts: [], schema: [], comparison: [] };
    const input = createInterface({ input: process.stdin, output: process.stdout });
    const questions = new AbortController();
    input.on("close", () => questions.abort());
    const interrupt = () => { options.interrupted = true; options.active?.kill("SIGTERM"); input.close(); };
    input.on("SIGINT", interrupt);
    process.on("SIGINT", interrupt);
    process.on("SIGTERM", interrupt);
    const ask = async (question) => {
        if (questions.signal.aborted) throw new Stop("interrupted");
        try {
            return (await input.question(question + " ", { signal: questions.signal })).trim();
        } catch { throw new Stop("interrupted"); }
    };
    const authorizeTrace = () => {
        console.log("Authorizing both local traces. Terminal needs Full Disk Access for eslogger.");
        input.pause();
        process.stdin.setRawMode(false);
        try {
            return local("/usr/bin/sudo", ["-v"], { stdio: "inherit", timeout: undefined }).status === 0;
        } finally {
            if (!questions.signal.aborted) {
                process.stdin.setRawMode(true);
                input.resume();
            }
        }
    };
    try {
        const { facts } = state;
        facts.os = local("/usr/bin/sw_vers", ["-productVersion"]).stdout?.trim();
        const hardware = local("/usr/sbin/system_profiler", ["SPHardwareDataType"]).stdout ?? "";
        facts.chip = /^\s*Chip:\s*(.+)$/m.exec(hardware)?.[1] ?? (hardware.includes("Intel") ? "Intel" : undefined);
        facts.codex = /^codex(?:-cli)? (\S+)$/.exec(local(options.codex, ["--version"]).stdout?.trim() ?? "")?.[1];
        const login = local(options.codex, ["login", "status"]);
        facts.login = login.status === 0 && /logged in (?:with|using) chatgpt/i.test(login.stdout + login.stderr)
            ? "ChatGPT" : "not verified";
        if (!facts.codex || facts.login !== "ChatGPT") throw new Stop("environment");
        process.umask(0o077);
        options.dir = mkdtempSync(join(homedir(), "spotcast-look-screens."));
        const inventory = mcpList(options);
        const preflight = await runProbe(options, ["check-endpoint"]);
        state.disabled = number(preflight.stdout, /^Personal MCP servers disabled by launch override: (\d+)\.$/m);
        state.endpoint = preflight.ok;
        if (!preflight.ok) {
            console.log("Nothing uploaded. Run the manual endpoint preflight for local diagnostics.");
            throw new Stop("endpoint preflight");
        }
        console.log("Endpoint verified. Pause other Codex sessions and hide notifications and private content.");
        if (options.from === "act") await act(options, ask, state, inventory, authorizeTrace);
        await suggest(options, ask, state);
    } catch (error) {
        state.stop = options.interrupted ? "interrupted" : error instanceof Stop ? error.message : "local check";
        process.exitCode = 1;
    } finally {
        state.cleanup = options.dir ? "kept" : "not needed";
        if (options.dir && !questions.signal.aborted && !options.interrupted) {
            try {
                if (await ask("Delete the private local fixtures now? y to delete:") === "y") {
                    rmSync(options.dir, { recursive: true, force: true });
                    state.cleanup = "deleted";
                }
            } catch { state.cleanup = "could not delete"; }
        }
        input.close();
        if (options.dir && state.cleanup !== "deleted") console.log("Local fixtures (do not share): " + options.dir);
        console.log("\nPaste only the following report:\n\n" + report(state));
    }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    await main(process.argv.slice(2));
}
