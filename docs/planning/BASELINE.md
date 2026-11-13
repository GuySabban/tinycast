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

## Repository

On 2026-11-13 the clone was arranged as `RISKS_AND_DECISIONS.md` section 4 describes. `upstream` is
`abue-ammar/tinycast`, with its push URL set to an invalid value so a push cannot reach it. `origin`
is `guysabban/tinycast`. Actions are disabled on the fork. `main` was fast-forwarded to
`upstream/main` (`ede02bf3`), and `main` and `universal-launcher` are pushed to `origin`.
