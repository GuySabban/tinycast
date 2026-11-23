# Look phase L, step 5: Codex tool spike

Developer probe only. It does not change or run Spotcast, use its Screen Recording grant, alter
Codex config, or touch the pasteboard. The sole tool is an inert `copy_text`: it verifies one
known marker without copying, opening, sending or saving anything. The suggest trial has no
MCP server, no web search and no shell or script tool. Both turns use the existing route's
ephemeral thread and read-only, offline sandbox settings. The Codex client itself still connects
to OpenAI. The input file is read as a data URL; the probe does not create screenshot files.

## VM evidence (not the owner run)

`./Scripts/run-tests.sh LookToolSpikeTests` runs the offline protocol fixture. It uses a fake
Codex child, a synthetic PNG, and a real, authenticated loopback HTTP connection with a short
hold. It checks the app-server request shape, one approval and byte-for-byte marker handling, the
tool-free schema request, and rejected HTTP/tool requests. It cannot establish any live Codex
behaviour, duration or screen recognition.

## Owner-only run: macOS 27.2, M3

Only use screens you are willing to send to OpenAI. Use non-sensitive test content in your real
apps; hide notifications, real mail, personal data and unrelated windows. The Terminal commands
below explicitly create local test fixtures; do not use a synced folder, commit them, redirect
the probe output to a file, or share screenshots, transcripts, process arguments or endpoints.
The Look feature's in-memory capture and TCC checks are later steps, not covered by this probe.

### Act: rows 7, 8, 10, 11 and 12

1. In the PR checkout, confirm `sw_vers -productVersion`, `system_profiler SPHardwareDataType`
   (check the Chip field), `node --version` (Node 22+), `codex --version`, and
   `codex login status` (signed in through ChatGPT). Run `codex mcp list` to identify your normal
   configured servers privately; leave them configured for the exclusion check. Pause other
   Codex sessions so they are not confused with the probe. Use the normal OpenAI backend (no
   custom provider, endpoint or API key). The probe checks the ChatGPT account before uploading.
2. In Terminal at repo root, set up the probe and a private fixture directory. Set `model` to the
   exact Codex model ID you want to test; use it for both turns (D53).

   ```sh
   probe="$PWD/Scripts/fork/look-tool-spike/probe.mjs"
   shots=$(mktemp -d "$HOME/spotcast-look-screens.XXXXXX")
   model='REPLACE_WITH_YOUR_CODEX_MODEL_ID'
   ```

3. On the main display, put a TextEdit document on screen with
   `LOOK SPIKE: M3 "dry-run" שלום 5271` in a single clearly visible line, or choose your own
   harmless marker. Start the first command in Terminal, switch to the document within five
   seconds, and allow Terminal screen capture if prompted; then verify the file in Preview.
   Use the part **after** `LOOK SPIKE: ` exactly as `--expect`. That value is compared locally
   and is not placed in the prompt. If Codex is not on PATH, add `--codex /absolute/path/to/codex`.

   ```sh
   screencapture -x -m -T 5 "$shots/act.png"
   node "$probe" act --confirm-upload --image "$shots/act.png" --model "$model" \
     --expect 'M3 "dry-run" שלום 5271'
   ```

   If the capture is above 10 MiB, convert it with `sips -s format jpeg -s formatOptions 85
   -Z 4096 "$shots/act.png" --out "$shots/act.jpg"` and pass the JPEG instead.

4. First check that the short act run completed, with exactly one accepted elicitation, no
   subsequent approval request, and one exact marker match. This settles rows 7 and 11
   independently of row 8. If it fails, follow the stop rule in step 6 instead of running the hold.
   Otherwise rerun the same command with `--hold-60s` appended. During
   `withholding reply for 60000 ms`, in a second Terminal tab, substitute the printed
   **App-server PID** and run the following. It lists the app-server and descendants by PID,
   parent PID and command name (no arguments), then their live network connections.

   ```sh
   pid=REPLACE_WITH_APP_SERVER_PID
   ps -axo pid=,ppid= | awk -v root="$pid" '
       { parent[$1] = $2 }
       END {
           for (p in parent)
               for (q = p; q in parent && parent[q] != q; q = parent[q])
                   if (q == root) { print p; break }
       }' | while IFS= read -r child; do
       ps -p "$child" -o pid=,ppid=,comm=
       lsof -nP -a -p "$child" -i
   done
   ```

   For row 10, verify no process belonging to a personal stdio MCP server and no connection to a
   personal HTTP MCP server. The loopback connection should match the printed address; Codex's
   normal provider connection is expected. Record the disabled count and pass/fail, not names
   or addresses. A missed sampling window or a run with no personal servers configured does not
   settle row 10.
5. In the probe Terminal, record whether there was a tool reply at or beyond 60,000 ms and the
   model returned its receipt (8). Record the actual hold time and both restart timings. For row 12 use
   **Restart through initialize**, including stopping the warm process, enumerating personal
   servers, binding the bridge and handshaking; record **Restart through thread/start** separately
   so any added thread cost is visible. Repeat the short act run twice more for restart timing,
   with the same model, fixture and machine. Compare the median short-run restart to 1,000 ms.
6. If row 7 (image plus tool) or 11 (single approval and unchanged arguments) fails, or personal
   tools start, **stop**. Do not loosen the sandbox, enable personal MCP servers or start another
   roadmap step. Report which evidence was missing. The probe allows a 90 s tool timeout and a
   150 s turn deadline **only so a single dry-run call can itself wait 60 s**; it does not
   replace the product's eight-call / 60 s maximum.

### Suggest: rows 5 and 6

7. Prepare ten distinct screens at normal display scaling, including a visible piece of
   known 11-point text in English and in Hebrew. Example screens: English mail, Hebrew mail,
   English calendar invite, Hebrew event flyer, PDF, long web article, chat, document, map or
   directions page, and a busy spreadsheet. Use mock content in the real apps. Note one expected
   reading or natural action per screen **before** running the probe. Use `01` to `10` as IDs.
8. Capture each screen with the same delayed command from step 3, but use a new ID in place of
   `01`. Make a large (up to 4096 px long side) and a compact (up to 2048 px) version of each
   same capture. Verify actual dimensions and encoded byte counts; if the variants have the
   same size, make the compact one smaller. Keep either file at or below 10 MiB (lower JPEG
   quality as needed).

   ```sh
   id=01
   screencapture -x -m -T 5 "$shots/$id.png"
   sips -s format jpeg -s formatOptions 85 -Z 4096 "$shots/$id.png" --out "$shots/$id-large.jpg"
   sips -s format jpeg -s formatOptions 85 -Z 2048 "$shots/$id.png" --out "$shots/$id-compact.jpg"
   sips -g pixelWidth -g pixelHeight "$shots/$id-large.jpg" "$shots/$id-compact.jpg"
   stat -f '%z bytes: %N' "$shots/$id-large.jpg" "$shots/$id-compact.jpg"
   ```

9. Run these two commands for each ID (twenty turns total); use the actual app, bundle ID,
   safe window title and chosen interface language for each capture, consistently between sizes.
   `--language he-IL` can check Hebrew output; Hebrew input reading should also work with
   `--language en-US`. Do not put the expected text from the body of the screen in the context.
   The probe provides the current date, weekday, time zone and a fixed list of possible actions.

   ```sh
   app=TextEdit bundle=com.apple.TextEdit title='Spike sample 01' language=en-US
   for size in large compact; do
     node "$probe" suggest --confirm-upload --model "$model" --image "$shots/$id-$size.jpg" \
       --app "$app" --bundle-id "$bundle" --window-title "$title" --language "$language"
   done
   ```

10. Per result, record ID, dimensions and bytes, elapsed turn milliseconds, JSON valid yes/no,
    screen fact read correctly yes/no, useful suggestions yes/no, and interface language correct
    yes/no. Review the suggestions before counting them: an empty list is valid JSON but not
    evidence the screen was read. Look specifically for correct 11-point English and Hebrew and
    any mistakes that occur at only one size. Compute timing median and nearest-rank p95, both
    overall and by size, and count valid results out of 20 (target ≥19). The timing is
    `turn/start` through `turn/completed`, including the data URL transfer; it does not measure a
    hotkey, newly capturing the screen, or drawing the future Look UI. If the schema option is
    rejected or the score misses, record that result before trying the same samples with
    `--no-schema`; report that second cohort separately. Do not silently replace a failed run.
11. Share aggregate results and failures only, with the OS/chip, model and Codex version. Delete
    the test fixtures in Finder (the folder is in `$shots`), then empty Trash if appropriate.

## Decisions if the evidence misses a gate

| Trigger | Options and recommendation (not decided here) |
| --- | --- |
| Rows 7 or 11 fail | Keep loopback only after the owner agrees to another bounded verification, or switch to the tool-free JSON plan (D46(b)); recommend the plan if the failure persists. A key-based tool loop changes routes; no loosened shell or third-party servers. |
| Row 8 fails | Verify the longest supported wait on the same version, or defer tools that require confirmation. Recommend measuring the safe wait before deploying any confirmation-dependent tools. |
| Row 10 fails | Stop on the security failure. Keep the route blocked pending an exclusion fix and a repeat process check, or use the tool-free plan if safe isolation cannot be shown. Recommend no act turn until the isolation is evidenced. |
| Row 12 reaches 1 s or more | Keep per-turn restart with its cost, or investigate a server address present from launch without enabling it or accepting any token outside an act turn. Recommend investigating the latter only if the owner wants to spend the seam budget. |
| JSON or small-text target misses | Compare structured and prompt-only JSON for the same screens; keep the large image, adjust encoding, or try a different model under D53. Recommend choosing from measured quality before lowering resolution. |
| Median suggestions miss 4 s | Keep the same chosen model (D53(a)) or compare a faster suggest-only model (b). Recommend a matched comparison before changing defaults. |

## Seam read (source only, no app change)

- `AIProviderFactory`, `ChatGPTSubscriptionManager` and `CodexTurnRunner` already pass
  `AIToolServerSession` per provider/turn. `CodexMCPLaunch` already supports a URL, a bearer token
  passed in the child environment, and prompt approval mode; `CodexTurnRunner.consent(to:)`
  routes the elicitation by active thread, server handle and tool. If rows 7 and 11 pass with the
  current protocol, Look can supply its own session and validate arguments at its own bridge;
  there is no demonstrated need to restructure those seams.
- `CodexTurnRunner` already combines text and image input, disables web search on request, and
  creates a read-only, ephemeral thread, but does not send `turn/start.outputSchema`. If that
  option proves useful, add an opt-in field at the request/runner seam in the later suggest step;
  otherwise a tool-free prompt plus strict parsing can use the current request.
- `CodexAppServerClient.start(toolServers:)` replaces the shared process when the server list
  changes, potentially stranding other chats. A slow restart or an isolation failure is not
  justification to restructure that seam in this step; report the measured result first.
