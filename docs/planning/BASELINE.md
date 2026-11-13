# Baseline

Task 1 of `IMPLEMENTATION_ROADMAP.md`: the untouched tree, checked on the owner's Mac on 2026-11-13
before any fork change. Every failure or warning below is **pre-existing**.

Tree: `universal-launcher` at `d9414598` ("Recognize Yandex Telemost meeting links (#1884)"), with
no source changes. Logs are in the ignored `build/` folder (`build/baseline-*.log`).

## Tools

| Tool | Version |
| --- | --- |
| macOS | 27.2 (Darwin 27.2.0), arm64 |
| Xcode | 27.2 (27B52), `xcode-select -p` is the Xcode path |
| Swift | 6.4.2 (swiftlang-6.4.2.1.9) |
| XcodeGen | 2.46.0 (Homebrew) |
| SwiftLint | 0.65.1 (Homebrew) |
| Node | 22.19.0 (nvm) |
| OpenSSL | 4.1.0 (Homebrew; the `openssl` on `PATH`) |

## Signing identity

`Tinycast Self-Signed` did not exist, so `docs/signing.md` section 1 was run. Its `security import`
failed with "MAC verification failed during PKCS12 import": OpenSSL 3 and later write a `.p12`
that the macOS keychain cannot read. The `.p12` had already been copied to
`~/Signing/launcher-signing.p12`, so the same key was re-exported with `openssl pkcs12 -export
-legacy` to `~/Signing/launcher-signing-legacy.p12` and imported from there. Both files hold the
same key; the password is the one in `docs/signing.md`. Import the `-legacy` file on another Mac.
`docs/signing.md` needs `-legacy` on its `pkcs12 -export` line when OpenSSL is 3 or later.

## Results

| Check | Result |
| --- | --- |
| `xcodegen generate` | Deterministic: no diff in `Tinycast.xcodeproj` |
| Row 2: Debug build, `CODE_SIGNING_ALLOWED=NO` | Succeeded in about 60 s |
| Build warnings (distinct ` warning: ` lines) | 2, both `appintentsmetadataprocessor: Metadata extraction skipped, no AppIntents.framework dependency found` (one per target, differing only in timestamp). No compiler warnings. |
| Row 1: `./Scripts/run-tests.sh` | All 113 harnesses passed in 144 s; none failed |
| Row 1: `./Scripts/lint.sh` | Clean (exit 0, `✓ lint-clean`): 0 errors, 78 SwiftLint warnings, which the script does not block on |
| Row 7: shell fallback (R2) | **Real.** Signed Dev build: typing `date` and choosing Run Shell Command ran it with no confirmation |
| Row 4: updater (R1) | **Real.** Unmodified Release build (`com.tinycast.app` 0.1.0, run from `build/`): Check for Updates showed an update pill offering upstream's **v0.12.11**. Update was not clicked. |

### Harness count: 113, not the audit's 114

No harness was skipped. At `d9414598`, `Scripts/run-tests.sh` has 121 `run` entries. Eight are
`index` entries, the performance harnesses the suite never runs, so 113 run, and all 113 appear in the
log. The audit's "114" is the count from before upstream commit `ff4fa05e` (#1796, 2026-11-07),
which removed the onboarding UI harness (`Tests/onboarding-test.swift`, an `exclusive` entry). That
commit left 122 entries with 114 runnable at 121 with 113. The audit section 1.12 figure is
stale; the 121-entry total is right.

### FormInputTests needs Dark mode

`FormInputTests` passes only while macOS is in Dark mode, so it is pre-existing and not a fork bug.
Its windows take the system appearance, and `inkBounds` counts only pixels whose red component is
above 0.2, so the theme's dark text in Light mode measures as no text at all (eight failures, starting
with "the placeholder rendering test captures visible text"). The baseline ran around midnight while
this Mac's Auto appearance was Dark. On 2026-11-13 at 08:46, in Light, it failed both with and without
the Task 3 changes, and passed with Task 3 applied once the owner switched to Dark. A
`-AppleInterfaceStyle Dark` launch argument does not change the harness's appearance. Run the suite
in Dark mode.

### Build log noise

Each `xcodebuild` run logs a non-fatal `DVTCoreDeviceCore` plug-in load failure ("Symbol not
found"), which is counted as one ` error: ` line. It comes from Xcode's device support, not from the
project; `xcodebuild -runFirstLaunch` is the usual cure. The build still succeeds.

### SwiftLint warnings by rule

| Rule | Count |
| --- | ---: |
| `closure_parameter_position` | 32 |
| `optional_data_string_conversion` | 28 |
| `force_cast` | 5 |
| `legacy_swiftui_aspect_ratio` | 4 |
| `line_length` | 3 |
| `implicit_optional_initialization` | 2 |
| `void_function_in_ternary`, `unneeded_synthesized_initializer`, `is_disjoint`, `for_where` | 1 each |

Upstream does not pin a SwiftLint version, so newer releases can add warnings. Fork changes are
judged against this count.

## Remaining Phase 0 checks (2026-11-13)

Run on the fork after Tasks 2 and 3, in the roadmap's order: rows 11, 13 and 12, then 3, 6, 8, 9, 10
and 15. Row 14 (a friend's Mac) and row 17 (a package install) are skipped. Hands-on steps were done
by the owner.

| Row | What it settles | Result |
| --- | --- | --- |
| 11 | On-device model, tools and typed output | **Pass.** A compiled Swift program got `available`. `LanguageModelSession(tools:)` called the tool, `respond(to:generating:)` filled a `@Generable` struct, and a plain session answered. About 7.5 s in all. |
| 13 | The installed `claude` accepts Tinycast's flags | **Pass.** Claude Code 2.1.323. Quick AI on the Claude route (Claude Opus 5.5, medium effort) streamed an answer. `--thinking-display` and `--max-turns` are not in `claude --help` but are accepted. |
| 12 | System frameworks can write WebP | **No.** ImageIO reads WebP but cannot write it. It writes JPEG, PNG, JPEG 2000, HEIC and AVIF. |
| 3 | Memory and CPU | **Within targets.** Measured on the Dev build in the table below. |
| 6 | A rebuild satisfies the previous build's designated requirement | **Pass.** Two Spotcast Release builds with different binaries share the requirement `identifier "io.github.guysabban.spotcast" and certificate leaf = H"91cd17d3…"`. `codesign -v -R=<old requirement>` accepts the new build. All three helpers are pinned to the same leaf. |
| 8 | R3: an outside extension link runs with no prompt | **Real.** `open 'tinycast-dev://extensions/nhojb/brew/search?fallbackText=test'` opened Brew's Search with `test` and asked nothing. |
| 9 | A fallback quicklink passes the query to an extension command | **Pass.** A quicklink to `tinycast-dev://extensions/nhojb/brew/search?fallbackText={argument}` opened Brew's Search with the typed text. This needs Quicklinks switched on: `quicklinksEnabled` defaults to off, and the fallback row is then missing. |
| 10 | Five Store extensions | **Four of five.** Brew, Port Manager, Kill Process and Image Modification (`sips`) work. Disk Usage shows "Scan failed": it spawns `du -k -P -x` and reads it through `stream/promises` `pipeline`, `readline` and `events.once`. The root cause in the runtime is not yet found. |
| 15 | Keychain items survive a rebuild | **Data survives; access prompts.** A secret saved by one build was intact after a clean rebuild with the same certificate, but macOS asked for the login-keychain password once ("Always Allow" cleared it). The likely cause: without a Team ID, the login keychain ties access to each build's code hash rather than to the certificate. Expect one prompt per new build for every Keychain scope. The probe was deleted afterwards. |

### Row 3 measurements

Tinycast Dev (Debug), `footprint` every second and the `com.tinycast.perf` signposts from `log stream
--signpost`, during a session of summons, a calculation, a file search and app names.

| Point | Result | Target |
| --- | --- | --- |
| Idle after launch, 45 s settled | 36 MB | Under 100 MB |
| Panel open | About 48 MB | Under 100 MB |
| Feature in use (file search, calculation) | Peak 65 MB | Under 100 MB |
| Panel closed, about 50 s settled | 63 MB, not back to idle | Under 100 MB |
| Idle CPU, panel hidden, 60 s | Under 0.1% (twelve 5 s samples, two non-zero) | Under 0.5% |
| `PaletteWindowController.show` | Median 23 ms, p95 42 ms, n=12 | Show is part of 100 ms p95 hotkey-to-panel |
| `AppIndex.rank` | Median 2 ms, p95 7 ms, max 17 ms, n=44 | 16 ms p95 |
| `AppIndex.scan` (each summon) | Median 38 ms, p95 46 ms, n=12 | None set |

## Trial merge (Appendix B row 16)

Run 2026-11-13 on `scratch/trial-merge`, cut from `universal-launcher` at `cdb5b1e6` with
`rerere.enabled` set. The branch was deleted afterwards and nothing reached `universal-launcher`.

- **Newest stable tag, `v0.12.11` (2026-11-08):** already an ancestor of the fork, which was cut from
  the later `d9414598`. "Already up to date."
- **`upstream/main` at `ede02bf3`, three commits beyond the fork point:** merged cleanly in seconds
  with no conflicts. They changed only `.github/` issue and discussion templates, two workflows
  (`issue-link.yml`, `triage.yml`) and `CONTRIBUTING.md`. No Swift, project or seam file and no
  entitlement changed. The only new hosts are github.com links in templates.
- **What it does not show:** none of the incoming commits touched a seam, so the cost of a merge
  that conflicts with the fork's lines is still unmeasured. The first real merge after an upstream
  release that changes `FallbackCoordinator`, `CustomCommandCoordinator`, `AppIndex`,
  `ExtensionDeepLink` or `project.yml` sets the real figure. Record it in the ledger.

## Step 7: AI setup

Done on the Dev build: Settings, AI, Enable AI; Manage, enable Claude; then Claude Opus 5.5 at medium
effort chosen as the default. Row 13 confirms the route works.

## Phase 1 step 8: hands-on run (2026-11-13)

The signed Dev build of `universal-launcher` at `09696f68`, driven by the owner, with every `brew`
process logged at 50 ms, the `com.tinycast.perf` signposts streamed and `footprint` sampled every
2 s. Each real install was approved by the owner first. Logs are in `build/p1s8-*.log`.

### The Install list in `MVP_SCOPE.md`

| Check | Result |
| --- | --- |
| `install blender` shows the card first | **Pass** |
| Return shows the approval dialog within about a second | **Pass.** `PackageInstall.lookup` median 163 ms, p95 311 ms, max 351 ms, n=15 |
| The dialog's command is what runs | **Pass.** The dialog said `Runs: brew install --cask blender`; the processes the app started were `brew.sh install --cask itsycal` and `… blender` (brew re-executes itself through `brew.sh`). The environment prefix in section 4.3 of the architecture is not shown |
| Installed, verified, found without a relaunch | **Pass.** `itsycal` 0.28.0 installed in about 4.5 s, and the owner found it by typing `itsycal`. Blender 5.3.0 also installed and verified (the run after Stop and Run Again) |
| A password cask never starts in the app; Terminal works | **Pass.** `blackhole-2ch` offered only "Install BlackHole 2ch in Terminal?". Open in Terminal ran `brew install --cask blackhole-2ch` there, and the owner pressed Ctrl-C at the password prompt. The abort left a Caskroom folder; see the fixes |
| Homebrew absent shows the setup command | **Not run.** The owner declined renaming `brew`. A `sandbox-exec` profile denying `file-read*` and `file-test-existence` on `/opt/homebrew/bin/brew` hides it from one process without touching Homebrew; it was tried on a shell, not on the app |
| An app already present is offered for opening | **Pass.** `maccy` (installed by hand) and `obsidian` (by Homebrew) both offered Open |
| A disabled cask is refused with Homebrew's reason | **Pass.** `affinity-photo` (discontinued, "Try affinity") and `prowlarr` (fails Gatekeeper check, its app missing) |
| Cancelling leaves nothing running | **Pass** for Cancel in a dialog (no `brew` started) and for Stop: 65 s into Blender's 360 MB download, `curl` and `brew` were both gone within one 50 ms poll. Run Again reopened the approval. Cancelling the lookup pill was not tried: it is up for about 0.2 s |

### Rows 2 to 7 of `PROPOSED_ARCHITECTURE.md` section 9

| Row | Result |
| --- | --- |
| 2 | **Settled, with a correction.** `blackhole-2ch` (a pkg) run through the shipped `CaskInstaller` with `HOMEBREW_NO_SUDO=1` exited 1 in 2.8 s under the pseudo-terminal, and downloaded nothing. Homebrew 7.0.13 refuses at its requirement check, before the download, with "The pkg artifact requires sudo, but HOMEBREW_NO_SUDO is set." (`cask/installer.rb`, for every artifact whose `requires_sudo?` is true). "sudo is disabled by HOMEBREW_NO_SUDO." is only for a sudo step it did not flag in advance. `refusedSudo` knew only the second |
| 3 | **Settled.** Nothing waited: both in-app installs ran to the end. Homebrew 7.0.13 asks only when the plan adds names the user did not request, that is dependencies (`install.rb`, `ask_prompt_needed?`), so `HOMEBREW_NO_ASK=1` matters for casks with dependencies |
| 4 | **Settled.** The harness's 50 names hit 49 (the known miss is "github desktop"), and the same 49 hit on the live file of 2026-11-13 (6,043 tokens) |
| 5 | **Settled.** Switching Install on in a running Dev app added 0.5 MB (36.3 to 36.8 MB). On its own the decoded index holds 984 KB of live heap |
| 6 | **Settled for fresh installs.** Itsycal (team `HFT3T55WND`) and Blender (`68UA947AUU`) pass `anchor apple or (<BundleSignature.developerID>)` with `codesign --strict --deep` |
| 7 | **Settled.** Neither fresh install made an App Management request (TCC log). The owner then replaced the installed Itsycal from the app: `brew reinstall --cask itsycal` with the installer's environment, through Run Shell Command. Homebrew's test write inside the bundle reached `tccd`, which refused Tinycast Dev without a prompt ("does not allow prompting for unentitled binaries") and added a denied App Management entry for `com.tinycast.app.dev`. Homebrew printed nothing, since its warning needs the undocumented `HOMEBREW_NO_APP_MANAGEMENT_PERMISSIONS_PROMPT`, and fell back to deleting and copying the app. The reinstall succeeded. The MVP's in-app runs are all fresh installs, and its reinstall goes to Terminal; an in-app upgrade (Phase 4) will meet this |

### Summon time and the other signposts

| Signpost | This run | Baseline |
| --- | --- | --- |
| `PaletteWindowController.show`, 22 hotkey summons | Median 21.5 ms, p95 26.1 ms, max 29.0 ms | Median 23 ms, p95 42 ms, n=12 |
| The same, every summon of the session | Median 20.8 ms, p95 26.3 ms, n=41 | |
| `AppIndex.rank` | Median 3.1 ms, p95 5.6 ms, n=233 | Median 2 ms, p95 7 ms |
| `AppIndex.scan` | Median 29.6 ms, p95 36.5 ms, n=44 | Median 38 ms, p95 46 ms |
| `PackageInstall.match` (Debug) | Median 2.7 ms, p95 10.2 ms, n=100 | Target is 2 ms p95 in a Release build, not measured here |

The show that runs once at launch (60 to 128 ms) is left out, as in the baseline.

### Memory and CPU: a leaked progress pill

During the run, footprint went from 36 MB to 153 MB at the first Return on a card and settled at
167 MB. A temporary launch probe (not committed) isolated it: the progress pill
(`MessageHUDController.showProgress`, which the lookup shows) added 53 MB, of which 46 MB was graphics
memory, and kept it after hiding, with the idle app at 6.6% CPU. A message pill added 1 MB.
`HUDPresenter` orders the panel out but kept its SwiftUI view, so the spinner's `variableColor`
effect went on animating unseen until the next message replaced it. After the fix the same probe
drops back to 38 MB once the pill hides, at 0.0% CPU. While the spinner is on screen it still costs
about 53 MB; the lookup shows it for about 0.2 s, but Quick Actions show it for seconds.

Also measured on the Dev build: a hotkey summon adds nothing measurable (35 MB with Install off,
45.5 MB with it on), a deep-link consent dialog adds 1.4 MB, and the Settings window adds 29 MB while
open. The four points of upstream's rule were not measured again after the fix. In the run, between
the two leaks, the app sat at 106 to 110 MB with the Settings window and the output windows open.

### Fixes from this run

- **`BrewInvocation.refusedSudo`** also matches "requires sudo, but HOMEBREW_NO_SUDO is set" (row 2).
  `PackageInstallTests` carries the real line.
- **`HUDPresenter`** drops the panel's content once it is ordered out, as above. Fork ledger P1.8.
- **`HomebrewEnvironment.hasInstallRecord`**: a Caskroom entry counts only when the newest
  `.metadata/VERSION/TIMESTAMP` holds `Casks/TOKEN.json`, which is Homebrew's own `installed?`. Ctrl-C
  at the password prompt left `blackhole-2ch` with that folder but an empty `Casks/`, so Homebrew
  would install it again while the card would have said "already installed". `InstallVerifier` uses
  the same test. `PackageInstallServiceTests` lays out the interrupted folder, and fails without the
  fix.

### Left open

- The Homebrew-missing dialog, and cancelling during the lookup pill, have not been seen by hand.
- After Blender.app went to the Trash (the Uninstall command's scanner ran at 18:24:54), a
  `brew reinstall --cask blender` started outside the app at 18:25:09 and ended about 3 s later. That
  is what the card's Reinstall in Terminal runs. Blender did not come back, and what Terminal printed
  was not captured.
- Re-measure the four memory points on a session with an install, now that the leak is fixed.
- The `tinycast-dev` scheme is registered to an older Dev build in
  `~/Library/Developer/Xcode/DerivedData`, so `open tinycast-dev://…` reaches that copy. Use
  `open -a "<the build>" "<link>"` when testing links.

Cleanup: `itsycal`, `blender` and `blackhole-2ch` were uninstalled with `brew uninstall --cask` and
sudo disabled, leaving the 14 casks there were before, and their cached downloads were deleted.
Blender.app is still in the owner's Trash, and the denied App Management entry from row 7 remains.

## Repository

On 2026-11-13 the clone was arranged as `RISKS_AND_DECISIONS.md` section 4 describes. `upstream` is
`abue-ammar/tinycast`, with its push URL set to an invalid value so a push cannot reach it. `origin`
is `guysabban/tinycast`. Actions are disabled on the fork. `main` was fast-forwarded to
`upstream/main` (`ede02bf3`), and `main` and `universal-launcher` are pushed to `origin`.
