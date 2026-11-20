# Look capture spike (Phase L step 2)

Throwaway code for `docs/planning/IMPLEMENTATION_ROADMAP.md` Phase L step 2. It is not part of the
app target, nothing in `Tinycast/` imports it, and it is deleted when step 5's `ScreenCapturer`
lands. Results are in `docs/planning/BASELINE.md`, "Phase L step 2"; the re-ask log is
`docs/planning/SCREEN_RECORDING_LOG.md`.

It is a small accessory app, `io.github.guysabban.spotcast.look-capture-spike`, signed with the kept
`Tinycast Self-Signed` identity (R10), so it gets its own Screen Recording grant. It takes one
still of the display under the pointer (D32) with `SCScreenshotManager` (direct capture, D35),
long side capped at 4096 px, cursor hidden, and can exclude its own process or another app by
bundle identifier through `SCContentFilter(display:excludingApplications:exceptingWindows:)`.

## Build

Run every command here from the repository root, in Terminal.

```sh
./Scripts/fork/look-capture-spike/build.sh            # stamp = current time
./Scripts/fork/look-capture-spike/build.sh rebuild2   # any stamp; it changes the cdhash
```

Needs the `Tinycast Self-Signed` identity (`docs/signing.md`). Output: `build/LookCaptureSpike.app`
(ignored by git). Every run appends to `~/Library/Logs/LookCaptureSpike.log`: bundle, pid, build
stamp, cdhash, macOS build, preflight, the windows excluded, timings and decoy pixel checks. It
logs no image content.

## Modes

Always launch it through LaunchServices:

```sh
open -n -g -W build/LookCaptureSpike.app --args <mode> [options]
```

`-n` starts a new copy, `-g` keeps the frontmost app in front, and `-W` waits until the run
ends. Never run `build/LookCaptureSpike.app/Contents/MacOS/LookCaptureSpike` directly: macOS then
charges the capture to Terminal, denies it, and asks to give Terminal itself Screen Recording.
If that prompt appears, deny it. A launched app starts in `/`, so give `--save` an absolute or `~`
path.

| Mode | Does |
| --- | --- |
| `status` | Logs `CGPreflightScreenCaptureAccess()`; never prompts |
| `request` | Calls `CGRequestScreenCaptureAccess()`, then stays alive up to `--wait` s (180), logging preflight changes and trying a capture every 5 s, so a grant can be tested without a relaunch |
| `capture` | Takes `--repeat` stills of the display under the pointer |

| Option | Meaning |
| --- | --- |
| `--exclude-self` | Exclude this process's own windows |
| `--exclude-bundle <id>` | Exclude every window of a running app, e.g. `com.abueammar.tinycast.dev` |
| `--decoys` | Show three coloured panels like `PalettePanel`, `MenuPanel` (a child window of the palette-like one) and `HUDPanel`, and check their pixels in the image |
| `--delay <s>` | Wait before the first capture |
| `--repeat <n>`, `--interval <s>` | Several captures |
| `--hold <s>` | Stay alive after the last capture |
| `--save <path.png>` | **Diagnostic only:** writes the image to disk. Look itself never does (LOOK.md 3.5); delete the files after checking |

## Hands-on checks for the owner's Mac

Run these with the spike on the owner's Mac, Apple silicon, the macOS he uses daily. Write the
macOS version and build (`sw_vers`) next to each result. Copy the log lines into the PR or
`BASELINE.md`.

**Row 4: does a grant need a relaunch?**

1. `./Scripts/fork/look-capture-spike/build.sh`
2. `tccutil reset ScreenCapture io.github.guysabban.spotcast.look-capture-spike` for a clean
   start. Before the spike's first launch this exits 64 with "No such bundle identifier": there is
   no grant to reset, so go on.
3. `open -n -g -W build/LookCaptureSpike.app --args request`
4. In the macOS prompt choose Open System Settings and turn LookCaptureSpike on. When macOS offers
   "Quit & Reopen", choose **Later**.
5. If a "bypass the system private window picker" alert appears, note it in
   `SCREEN_RECORDING_LOG.md` (row 1) and choose Allow.
6. Wait for `request done` in the log. Record whether a `t+…s in-process: capture ok` line
   appeared before it, and the final `preflight` value.
7. `open -n -g -W build/LookCaptureSpike.app --args status`, and record `preflight`.

**Row 2: does a rebuild with the same certificate keep the grant?**

1. After row 4, `./Scripts/fork/look-capture-spike/build.sh rebuild2`. The `CDHash` it prints must
   differ from the first build's; the `designated` line must name the same certificate leaf.
2. `open -n -g -W build/LookCaptureSpike.app --args capture --exclude-self`
3. Record `preflight`, whether capture is `ok`, and whether any prompt or alert appeared.
4. Later, the same for the Release app itself: once Look exists (step 10), grant
   `io.github.guysabban.spotcast`, rebuild Release, Look again.

**Row 3: are the palette, `MenuPanel` and HUDs left out?**

1. Build and run the Dev build (`Tinycast Dev.app`, `com.abueammar.tinycast.dev`).
2. In Terminal, start this and switch away within 8 s:

   ```sh
   spike() { open -n -g -W build/LookCaptureSpike.app --args capture "$@"; }
   sleep 8; spike --save ~/Desktop/look-row3-shown.png; \
     spike --exclude-bundle com.abueammar.tinycast.dev --repeat 4 --interval 0.5 \
       --save ~/Desktop/look-row3-excluded.png
   ```

3. Within the 8 s: summon the launcher, type `calc`, press ⌘K so the actions menu is open.
4. Repeat steps 2 and 3, but this time run a command that shows a HUD (Toggle Mute shows one when
   an audio output exists) so the HUD is up at capture time.
5. Open the PNGs: `look-row3-shown.png` must show the launcher (and menu or HUD);
   every `look-row3-excluded-*.png` must show none of them. The log lists each excluded window
   with its layer. Delete the PNGs.

This excludes Spotcast from another process. Step 5 repeats it from inside Spotcast, which is how
Look will run.

**Row 6: is there a menu-bar recording indicator for one still?**

1. `open -n -g -W build/LookCaptureSpike.app --args capture --exclude-self --delay 3 --hold 15`
2. Watch the right end of the menu bar from before the capture until 20 s after.
3. Record whether a purple indicator appears, for how long, and which app Control Center names
   when clicked while it shows. Close any screen-sharing or remote-desktop app first: it shows the
   same indicator.

**Row 1: the six-week log.** See `docs/planning/SCREEN_RECORDING_LOG.md`.

**Clean-up.** `tccutil reset ScreenCapture io.github.guysabban.spotcast.look-capture-spike`, and
`rm -rf build/LookCaptureSpike.app` when the spike is deleted.
