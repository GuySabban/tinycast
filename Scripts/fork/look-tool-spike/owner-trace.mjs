import { spawn } from "node:child_process";
import { lookup } from "node:dns/promises";
import { access, realpath } from "node:fs/promises";
import { isIP } from "node:net";
import { basename, delimiter, isAbsolute, join } from "node:path";
import { createInterface } from "node:readline";
import { setTimeout as delay } from "node:timers/promises";

const defaultProvider = "chatgpt.com";
const maxEvents = 150_000;
const traceShell = 'set -m; "$@" </dev/null & tracer=$!; read -r stop; kill -TERM "$tracer" 2>/dev/null; wait "$tracer"';

function child(command, args, options) {
    const process = spawn(command, args, options);
    const done = new Promise((resolve) => {
        process.once("error", () => resolve(null));
        process.once("close", resolve);
    });
    process.stdin?.on("error", () => {});
    return { process, done };
}

function collectLines(stream, convert) {
    const rows = [];
    let incomplete = false;
    const reader = createInterface({ input: stream, crlfDelay: Infinity });
    reader.on("line", (line) => {
        if (!line.trim()) return;
        if (rows.length >= maxEvents) { incomplete = true; return; }
        try { rows.push(convert(line)); } catch { incomplete = true; }
    });
    return { rows, get incomplete() { return incomplete; } };
}

function address(ip) {
    if (ip.startsWith("::ffff:") && isIP(ip.slice(7)) === 4) return ip.slice(7);
    if (isIP(ip) !== 6) return ip;
    return new URL("http://[" + ip.split("%")[0] + "]").hostname.slice(1, -1);
}

function peer(value) {
    const match = /^(.*)\.(\d+)$/.exec(value);
    if (!match || !isIP(match[1].split("%")[0])) return null;
    return address(match[1]) + "/" + match[2];
}

export function packetRow(line) {
    const match = /^\S+\s+\((.*?)\)\s+IP6?\s+(\S+)\s+>\s+(\S+?):(?:\s|$)/.exec(line);
    if (!match) return null;
    const [, metadata, source, destination] = match;
    const pids = [...metadata.matchAll(/(?:^|,\s*)e?proc [^,]*:(\d+)(?=,|$)/g)]
        .map((entry) => Number(entry[1])).filter((pid) => pid > 0);
    return { pids, out: /(?:^|,\s*)out(?:,|$)/.test(metadata), source: peer(source), destination: peer(destination) };
}

async function baseline() {
    const marker = child("/usr/bin/true", [], { stdio: "ignore" });
    const connection = child("/usr/bin/nc", ["-z", "-w", "1", "127.0.0.1", "9"], { stdio: "ignore" });
    await Promise.all([marker.done, connection.done]);
    return { process: marker.process.pid, network: connection.process.pid };
}

function seenBaseline(events, packets, marker) {
    return events.some((event) => event.pid === marker.process && event.baseline) &&
        packets.some((packet) => packet?.out && packet.pids.includes(marker.network) &&
            packet.destination === "127.0.0.1/9");
}

export async function startTrace(targets) {
    const options = { stdio: ["pipe", "pipe", "pipe"] };
    const logger = child("/usr/bin/sudo", ["-n", "/bin/bash", "-c", traceShell, "trace",
        "/usr/bin/eslogger", "fork", "exec", "exit"], options);
    const tcpdump = child("/usr/bin/sudo", ["-n", "/bin/bash", "-c", traceShell, "trace",
        "/usr/sbin/tcpdump", "-i", "pktap,all", "-nnlq", "-k", "INPD", "ip or ip6"], options);
    logger.process.stderr.resume();
    const events = collectLines(logger.process.stdout, (line) => {
        const event = JSON.parse(line);
        const exec = event.event.exec;
        const path = exec?.target.executable.path;
        const argv = Array.isArray(exec?.args) ? exec.args : [];
        const executed = path && basename(path);
        let personal = false, possible = false;
        for (const entry of targets.stdio) {
            const indexes = argv.flatMap((arg, index) =>
                typeof arg === "string" && entry.images.has(basename(arg)) ? [index] : []);
            if (entry.images.has(executed) && !indexes.includes(0)) indexes.unshift(0);
            possible ||= indexes.length > 0;
            personal ||= argv.length > 0 && entry.args !== null && indexes.some((index) =>
                JSON.stringify(argv.slice(index + 1)) === JSON.stringify(entry.args));
        }
        return { seq: event.global_seq_num, pid: (exec?.target ?? event.process).audit_token.pid,
            ppid: event.process.ppid, child: event.event.fork?.child.audit_token.pid,
            exec: Boolean(exec), baseline: path === "/usr/bin/true", exit: Boolean(event.event.exit),
            personal, possible };
    });
    const packets = collectLines(tcpdump.process.stdout, packetRow);
    let statistics = "";
    tcpdump.process.stderr.on("data", (chunk) => { statistics = (statistics + chunk).slice(-8192); });
    let ready = false;
    let stopped;
    async function observeBaseline() {
        const marker = await baseline();
        for (let attempt = 0; attempt < 15; attempt += 1) {
            if (seenBaseline(events.rows, packets.rows, marker)) return true;
            await delay(100);
        }
        return false;
    }
    async function finish(checkEnd) {
        const endSeen = checkEnd && ready && await observeBaseline();
        const earlyExit = [logger, tcpdump].some(({ process }) =>
            process.exitCode !== null || process.signalCode !== null || !process.pid);
        logger.process.stdin.end("\n");
        tcpdump.process.stdin.end("\n");
        await Promise.all([logger.done, tcpdump.done]);
        const drops = /^(\d+) packets dropped by kernel$/m.exec(statistics)?.[1];
        const captured = /^(\d+) packets captured$/m.exec(statistics)?.[1];
        return { events: events.rows, packets: packets.rows,
            complete: ready && endSeen && !earlyExit && !events.incomplete && !packets.incomplete &&
                drops === "0" && Number(captured) === packets.rows.length };
    }
    const snapshot = () => ({ events: events.rows, packets: packets.rows, complete: false });
    const stop = (checkEnd = true) => stopped ??= finish(checkEnd);
    try {
        await delay(500);
        for (let attempt = 0; attempt < 3 && !ready; attempt += 1) ready = await observeBaseline();
        return { ready, snapshot, stop };
    } catch (error) {
        await stop(false);
        throw error;
    }
}

async function addresses(host) {
    try {
        return (await lookup(host.replace(/^\[|\]$/g, ""), { all: true })).map(({ address: ip }) => address(ip));
    } catch { return []; }
}

async function executableNames(command) {
    const names = new Set([basename(command)]);
    const paths = isAbsolute(command) ? [command] :
        command.includes("/") ? [] : (process.env.PATH ?? "").split(delimiter).filter(isAbsolute)
            .map((directory) => join(directory, command));
    for (const path of paths) {
        try {
            await access(path);
            names.add(basename(await realpath(path)));
            break;
        } catch { /* not on this path */ }
    }
    return names;
}

export async function traceTargets(entries) {
    const stdio = [];
    const http = new Set();
    let unknown = 0;
    await Promise.all(entries.map(async ({ transport }) => {
        if (transport?.type === "stdio" && typeof transport.command === "string" && transport.command) {
            const images = await executableNames(transport.command);
            const args = Array.isArray(transport.args) && transport.args.every((arg) => typeof arg === "string")
                ? transport.args : null;
            if (args === null) unknown += 1;
            stdio.push({ images, args });
        } else if (transport?.type === "streamable_http" && typeof transport.url === "string" &&
            URL.canParse(transport.url)) {
            const url = new URL(transport.url);
            if (url.protocol !== "https:" && url.protocol !== "http:") { unknown += 1; return; }
            const ips = await addresses(url.hostname);
            if (ips.length === 0) unknown += 1;
            for (const ip of ips) http.add(ip + "/" + (url.port || (url.protocol === "https:" ? "443" : "80")));
        } else {
            unknown += 1;
        }
    }));
    const provider = new Set((await addresses(defaultProvider)).map((ip) => ip + "/443"));
    if (provider.size === 0) unknown += 1;
    return { stdio, http, provider, unknown };
}

function trackRun(events, run, counts) {
    if (!Number.isSafeInteger(run.root)) return { pids: new Set(), complete: false };
    const active = new Set([run.root]);
    const pids = new Set();
    const seenExec = new Set();
    const seenExit = new Set();
    for (const event of events) {
        if (!active.has(event.pid) && !active.has(event.ppid)) continue;
        active.add(event.pid);
        pids.add(event.pid);
        if (event.child > 0) active.add(event.child);
        if (event.exec) {
            seenExec.add(event.pid);
            if (![run.root, ...run.appServers].includes(event.pid)) {
                if (event.personal) counts.personalProcess += 1;
                else if (event.possible) counts.possibleStdio += 1;
            }
        }
        if (event.exit) { seenExit.add(event.pid); active.delete(event.pid); }
    }
    const complete = run.appServers.length === 2 && [run.root, ...run.appServers].every((pid) =>
        seenExec.has(pid) && seenExit.has(pid)) && active.size === 0;
    return { pids, complete };
}

export function analyzeTrace(trace, runs, targets, { configStable = true, proxy = false } = {}) {
    const counts = { personalProcess: 0, personalHTTP: 0, otherPeer: 0,
        possibleStdio: 0, sharedPeer: 0, proxiedPeer: 0, unattributedPeer: 0 };
    const events = [...trace.events].sort((a, b) => a.seq - b.seq);
    const sequenced = events.length > 0 && events.every((event, index) =>
        Number.isSafeInteger(event.seq) && (index === 0 || event.seq === events[index - 1].seq + 1));
    let complete = trace.complete && sequenced && configStable && !proxy && targets.unknown === 0 &&
        targets.stdio.length + targets.http.size > 0 && runs.length === 4;
    const tracked = runs.map((run) => {
        const tree = trackRun(events, run, counts);
        const loopback = "127.0.0.1/" + run.port;
        complete &&= tree.complete && run.port > 0;
        return { ...tree, root: run.root, loopback, bridgeClients: new Set(), reachedBridge: false, reachedProvider: false };
    });
    const otherPeers = new Set();
    for (const packet of trace.packets) {
        if (!packet) { complete = false; continue; }
        if (!packet.out) continue;
        const run = tracked.find((item) => packet.pids.some((pid) => item.pids.has(pid)));
        const personal = targets.http.has(packet.destination);
        if (run) {
            const toBridge = packet.destination === run.loopback;
            const toProvider = targets.provider.has(packet.destination);
            const fromBridge = packet.source === run.loopback;
            if (toBridge && packet.source?.startsWith("127.0.0.1/") && packet.pids.some((pid) => pid !== run.root)) {
                run.bridgeClients.add(packet.source);
            }
            const bridgeReply = fromBridge && run.bridgeClients.has(packet.destination) &&
                packet.pids.every((pid) => pid === run.root);
            run.reachedBridge ||= toBridge;
            run.reachedProvider ||= toProvider;
            if (bridgeReply) continue;
            if (personal) {
                if (toBridge || toProvider || fromBridge) counts.sharedPeer += 1;
                else if (proxy) counts.proxiedPeer += 1;
                else counts.personalHTTP += 1;
            } else if (!toBridge && !toProvider) otherPeers.add(packet.destination ?? "unparsed");
        } else if (personal && packet.pids.length === 0) {
            counts.unattributedPeer += 1;
        }
    }
    counts.otherPeer = otherPeers.size;
    const ambiguous = counts.possibleStdio + counts.sharedPeer + counts.proxiedPeer + counts.unattributedPeer;
    complete &&= tracked.every((run) => run.reachedBridge && run.reachedProvider) &&
        counts.otherPeer === 0 && ambiguous === 0;
    return { status: counts.personalProcess || counts.personalHTTP ? "fail" : complete ? "pass" : "inconclusive",
        ambiguous, ...counts };
}
