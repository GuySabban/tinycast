# Implementation roadmap

Phases in dependency order, MVP first. The design each phase implements is in
`PROPOSED_ARCHITECTURE.md`; what counts as the MVP is in `MVP_SCOPE.md`; risks, open decisions (D1
to D14), the repository layout and the merge routine are in `RISKS_AND_DECISIONS.md`.

## How to read the estimates

Hours are the owner's own time, given as a range.

- **Who does the work.** The owner, working with a coding agent that drafts the Swift. The owner
  reviews, builds, runs and tests by hand.
- **Experience.** Three years of Lua and Roblox scripting; new to Swift, Xcode, AppKit and macOS
  permissions. The ranges include learning time.
- **Low end:** each step works on the first or second try. **High end:** one significant rework in
  the phase.
- **Merges.** Each phase's total includes one merge of upstream at its end. Routine merges between
  phases are extra: budget one to three hours each until real merges say otherwise.
- **Not included:** download and build waiting time.
- **Confidence** falls with distance. Phases 0 to 2 are planned in detail. Phases 3 to 7 are sized
  from the audit's touch sets and should be re-estimated when reached.

| Phase | Delivers | Hours |
| --- | --- | ---: |
| 0 | Toolchain, verified baseline, own identity, shell gate, first trial merge | 16–34 |
| 1 | App install from the main list (the MVP) | 45–95 |
| – | Friend-build gate | 8–19 |
| 2 | Web result rows | 35–70 |
| 3 | File ranking and aliases | 12–28 |
| 4 | Install refinements | 30–65 |
| 5 | Context actions on files, images and clipboard | 45–100 |
| 6 | Typed OS actions | 60–130 |
| 7 | AI answers in the main list (hard-fork checkpoint) | 60–150 |

## Phase 0. Foundations

**Objective.** A fork that builds, passes upstream's checks, cannot be replaced by upstream's updater,
and no longer runs typed text in a shell by default. Nothing else starts until this is closed.

**Existing files touched.** `project.yml`, `Tinycast/Features/Extensions/Model/ExtensionDeepLink.swift`,
`Tinycast/Features/Launcher/Service/AppIndex.swift`,
`Tinycast/Features/Launcher/UI/FallbackCoordinator.swift`,
`Tinycast/Features/CustomCommands/UI/CustomCommandCoordinator.swift`, and the regenerated
`Tinycast.xcodeproj/project.pbxproj`. About 15 lines in all; the seam budget in
`PROPOSED_ARCHITECTURE.md` section 7 lists them.

**New files.** `Scripts/fork/build-dmg.sh`, `docs/planning/BASELINE.md` for the recorded results, and
`docs/planning/FORK_LEDGER.md`.

### Steps

1. **Toolchain.** Install Xcode 27 (the owner does this), XcodeGen and SwiftLint, and confirm Node.
   Create the self-signed signing identity with the commands in `docs/signing.md` section 1, and keep
   a copy of the exported `.p12` file before the temporary files are deleted. Every build given to
   friends must be signed with this one certificate.
2. **Baseline checks, in the agreed order.** These are the audit's Appendix B rows. Only read-only and
   build commands are used.

   | Order | Appendix B row | What it settles | Where it happens |
   | --- | --- | --- | --- |
   | 1 | 2 | The Debug build compiles | Task 1 |
   | 2 | 1 | Harnesses and lint pass on the untouched tree | Task 1 |
   | 3 | 7 | Risk R2 is real: typed text runs in a shell | Task 1, with `date` as the typed text; again in Task 3 after the gate |
   | 4 | 4 | Risk R1 is real: an unmodified Release build is offered upstream's release | Task 1. Stop when the update pill appears; do not click Update. |
   | 5 | 5 | A renamed build is left alone by the updater | Task 2 |
   | 6 | 11 | The on-device model's tools and typed output work on this Mac | After Task 3: a small Swift program, compiled and run |
   | 7 | 13 | The installed `claude` accepts Tinycast's flags | After Task 3: one question in Quick AI |
   | 8 | 12 | Whether system frameworks can write WebP | After Task 3: one `swift -e` line |
   | 9 | 3, 6, 8, 9, 10, 14, 15 | Memory, signing continuity, extension links, Store extensions, Gatekeeper, Keychain | After Task 3. Row 14 needs a friend's Mac and can wait for the first friend build. |
   | 10 | 16 | What a merge costs | Step 6, on a scratch branch only |
   | – | 17 | The runtime bundle matches its source | Needs a package install, so it is skipped unless the owner approves it |

3. **Fork and remotes.** The owner creates the GitHub fork. The clone is then arranged as
   `RISKS_AND_DECISIONS.md` section 4 describes.
4. **Identity (risk R1).** Uses decisions D1 and D2.
   - In `project.yml`, give the Release configuration its own `TINYCAST_BUNDLE_IDENTIFIER` and
     `TINYCAST_URL_SCHEME`, and give the app target a Release `PRODUCT_NAME`. Leave
     `DICTATION_EXECUTABLE_NAME` alone: `DictationWorker` hard-codes the helper's name.
   - Add the new scheme to the list in `ExtensionDeepLink.swift`, or extension links on it are dropped.
   - In `AppIndex`, also keep the running app out of its own Suggestions by its actual identifier.
     The existing prefix check stays, because Debug builds keep upstream's Debug identifier.
   - Run `xcodegen generate`.
   - Add `Scripts/fork/build-dmg.sh`, adapted from upstream's script, which hard-codes `Tinycast.app`.
5. **Shell fallback gate (risk R2).**
   - In `FallbackCoordinator.isAvailable`, return `settings.customCommandsEnabled` for
     `.runShellCommand` and delete the comment above it, which becomes false.
   - In `CustomCommandCoordinator.runShellCommand`, ask through `core.confirm` before starting, with
     the same strings `perform` already uses. No new strings are needed.
6. **Trial merge (Appendix B row 16).** On a scratch branch cut from `universal-launcher`, merge the
   newest upstream stable tag. Record which files conflicted and how long it took, then delete the
   branch.
7. **AI setup on the owner's Mac.** Settings, AI: Enable AI; Manage, enable Claude; then pick a Claude
   model as the default. Installed CLIs are not detected until each is enabled, and enabling Claude
   does not select it.

### Risks

- Xcode 27 or the macOS 27 SDK surfaces new warnings or failures on the untouched tree. Record them in
  the baseline so they are not blamed on fork changes.
- `xcodegen generate` may not reproduce `project.pbxproj` byte for byte. Task 1 shows this at once.
- A harness needs Node (three do) or fails for an environment reason. Note it; do not edit harnesses.

### Tests

No new harness. `AppIndex.swift` and `ExtensionDeepLink.swift` are compiled by existing harnesses, so
the suite still covers them. `FallbackCoordinator.swift` and `CustomCommandCoordinator.swift` are
compiled by none, so the shell gate is checked by hand, before and after.

### Acceptance

- Appendix B rows 2 and 1 pass, or their failures are recorded as pre-existing.
- A Release build's `Info.plist` shows the fork's identifier. The launcher lists no Check for Updates
  command, and choosing Check for Updates from the menu-bar menu shows the "This is a local build"
  message. No update is offered, downloaded or staged.
- With Custom Commands off, a non-matching query shows no Run Shell Command row. With it on, the row
  asks before running and shows the exact text.
- `git diff` against the upstream commit shows about 15 changed lines in existing files, outside
  `project.pbxproj`.
- The trial merge is written up in `docs/planning/BASELINE.md`.

### Hours

| Step | Hours |
| --- | ---: |
| Toolchain and signing identity | 2–4 |
| Checks: rows 2 and 1 | 2–5 |
| Checks: rows 7, 4, 5 | 1–2 |
| Checks: rows 11, 13, 12 | 2–4 |
| Checks: the rest | 3–6 |
| Fork, remotes, branches | 1–2 |
| Identity | 2–5 |
| Shell gate | 1–2 |
| Trial merge and write-up | 1–3 |
| AI setup | 0.5–1 |
| **Total** | **16–34** |

## Phase 1. App install (the MVP)

**Objective.** Typing `install NAME` leads to a reviewed, verified Homebrew cask install, as specified
in `PROPOSED_ARCHITECTURE.md` section 4.

**Existing files touched.** `Tinycast/Features/Launcher/UI/LauncherScreen.swift`,
`Tinycast/Features/Launcher/UI/LauncherList.swift`, `Tinycast/App/AppCore.swift`,
`Tinycast/Features/Launcher/Settings/ApplicationsSettingsView.swift`,
`Tinycast/Resources/Localizable.xcstrings`, `Scripts/run-tests.sh`. Line counts are in the seam
budget.

**New modules.** `Tinycast/Features/PackageInstall/` with `Model/`, `Service/`, `UI/` and `Settings/`;
harnesses `Tests/PackageInstallTests.swift` and `Tests/CaskIndexStoreTests.swift`; fixtures in
`Tests/package-fixtures/`; `docs/features/package-install.md`, opening with an Invariants section as
upstream requires.

### Steps

1. **Model, test-first.** `InstallIntent`, `CaskIndex`, `CaskRecord`, `InstallPlan`,
   `InstallVerification`, `PackageCandidate`. Capture three real cask records as fixtures (an app
   cask, a pkg cask, a disabled cask) and a copy of the install-count file.
2. **Index store.** `CaskIndexStore`, modelled on `CurrencyRateStore`, with injectable base URL and
   protocol classes for its harness.
3. **Services.** `CaskAPI`, `HomebrewEnvironment`, `CaskInstaller`, `InstallVerifier`,
   `TerminalHandoff`.
4. **Coordinator and views.** `PackageInstallSettingsStore`, `PackageInstallCoordinator`,
   `PackageInstallCard`, `PackageActionsMenu`, `PackageInstallSettingsSection`.
5. **Seam edits**, in this order so each builds: `LauncherList` (the card case), `LauncherScreen`
   (the row case, its five switch arms and `hasPrimaryAction`), `AppCore` (ownership),
   `ApplicationsSettingsView` (one line for the section).
6. **Strings.** Add the strings, translate all eight languages, run `./Scripts/sync-strings.sh`.
7. **Checks.** Harnesses, lint, the Model purity search, a Debug build with no new warnings.
8. **Hands-on run** against the Install list in `MVP_SCOPE.md`, settling rows 1 to 7 of
   `PROPOSED_ARCHITECTURE.md` section 9 on the way.
9. **Merge upstream**, to confirm the seam edits still merge.

### Risks

- **The Terminal hand-off does not work as designed on macOS 27.** Fallback: copy the command and open
  Terminal. Settle it in the first week (decision D5).
- **Token matching misses common names.** Measured by the 50-name harness case. Fallback: the full
  catalogue (decision D4).
- **`brew` behaves differently under the pseudo-terminal** than its documentation suggests. Found in
  step 8; the flow already treats any non-zero exit as a failure with the log kept.
- **SwiftUI and Swift 6 concurrency are new to the owner.** The largest uncertainty in the estimate.

### Tests

| Harness | Compiles | Covers |
| --- | --- | --- |
| `PackageInstallTests` | `PackageInstall/Model/*.swift`, plus `LauncherMatch.swift`, `SearchRelevance.swift` and `ScriptRomanization.swift` for scoring | Intent parsing; index decoding; match order for 50 names; record decoding for the three fixtures; every `InstallPlan` outcome; every verification outcome; token validation |
| `CaskIndexStoreTests` | The store and the model | First fetch, cached start, offline keeps the cache, a malformed reply is ignored. Served by an in-process `URLProtocol`, as `DictationWorkerTests` does. |

`LauncherScreen` and `LauncherList` have no harness upstream, so the card's wiring is covered by the
hands-on run. A coordinator harness in the style of `UninstallCoordinatorTests` is worth adding only
if the flow proves fragile.

### Acceptance

What the user sees is the Install list in `MVP_SCOPE.md`. This phase adds the measured criteria:

- Matching takes under 2 ms at the 95th percentile (`PackageInstall.match` signpost).
- Return to approval dialog takes under one second at the median (`PackageInstall.lookup` signpost).
- Stop during a download ends the process within about two seconds.
- Resident memory is under 100 MB at the four pull-request-template points.
- All harnesses and lint pass; the Debug build has no new warnings.
- Lines changed in existing files are within 20% of the seam budget.

### Hours

| Step | Hours |
| --- | ---: |
| Model and its harness | 8–16 |
| Index store and its harness | 6–12 |
| Services | 8–16 |
| Coordinator and views | 10–22 |
| Seam edits and the settings section | 3–7 |
| Strings and lint | 3–6 |
| Hands-on run and fixes | 6–13 |
| Feature doc and upstream merge | 1–3 |
| **Total** | **45–95** |

## Friend-build gate

Not a phase. It sits between Phase 1 and the first build anyone else runs.

| Item | Hours |
| --- | ---: |
| The licence steps in `RISKS_AND_DECISIONS.md` section 5 | 2–4 |
| Own app icon and menu-bar icon | 1–3 |
| Names the user sees: the four command names that say "Tinycast" in `CommandID.swift`, and the About text, in eight languages | 2–5 |
| Decide what upstream's support reminders should do in a fork, and apply it | 1–2 |
| A disk image from `Scripts/fork/build-dmg.sh`, signed with the kept certificate | 1–2 |
| A short install note for friends, covering Open Anyway (audit Appendix B row 14) | 1–3 |
| **Total** | **8–19** |

Each edit to an existing file here goes in the fork ledger.

## Phase 2. Web result rows

**Objective.** Return on Search the Web shows up to five real results in the main list, as specified
in `PROPOSED_ARCHITECTURE.md` section 5.

**Existing files touched.** `LauncherScreen.swift`, `LauncherList.swift`, `FallbackActionsMenu.swift`,
`Fallback.swift`, `FallbackCoordinator.swift`, `CommandID.swift`, `LauncherCoordinator.swift`,
`DeepLinkConsentPolicy.swift`, `Tests/HotKeyTests.swift`, `AppCore.swift`,
`FallbacksSettingsView.swift`, `Localizable.xcstrings`, `Scripts/run-tests.sh`.

**New modules.** `Tinycast/Features/WebSearch/`; `Tests/WebSearchTests.swift` and
`Tests/WebSearchSessionTests.swift`; `docs/features/web-search.md`.

### Steps

1. Create an Exa account and key (the owner). Confirm decision D3 first.
2. Model, test-first: result, row, failure, request builder, reply decoder with cleaning rules.
3. `ExaSearchProvider` behind `WebSearchProvider`; `WebSearchSession`.
4. Settings: `WebSearchSettingsStore`, and `WebSearchSettingsSection` with the switch and the key
   field.
5. `WebSearchCoordinator`, the row view and its actions menu.
6. Seam edits: the fallback and its `CommandID`; the section in `LauncherList`; the row in
   `LauncherScreen`, including moving the selection on trigger; the closure in `FallbackActionsMenu`;
   one line in `FallbacksSettingsView`.
7. Strings, checks, hands-on run, upstream merge.

### Risks

- Exa changes its free tier or terms. The provider protocol limits the damage to one file.
- The web section's index arithmetic interacts badly with file rows. `LauncherScreen` has no harness,
  so this is found only by use. Test the combinations by hand: with and without files, with and
  without a lead card, first search and Search Again.
- The new `CommandID` breaks a harness that pins command lists. `HotKeyTests` is the known one.

### Tests

`WebSearchTests` covers request bodies, decoding of captured replies, text cleaning, link filtering
and failure mapping. `WebSearchSessionTests` uses an in-process `URLProtocol` for success, timeout,
401, 402, 429, a stale reply after a newer search, cancel, and the 20-query memory limit.

### Acceptance

- Results appear in under 1.5 seconds at the median and 3 seconds at the 95th percentile after the
  trigger.
- Typing never sends a request; one trigger sends exactly one.
- Five placeholder rows appear in the same frame as the trigger, with the selection on the first and
  scrolled into view, from both Return and the Cmd-K menu.
- With the network off, one row says so, and Return on it retries.
- The key is found in Keychain Access and nowhere on disk.
- A query searched earlier in the session shows its results again without a request.
- Harnesses, lint and build are clean, and changed lines are within 20% of the seam budget.

### Hours

| Step | Hours |
| --- | ---: |
| Model and harness | 6–12 |
| Provider, session and harness | 8–16 |
| Settings and key | 4–8 |
| Coordinator and views | 7–14 |
| Seam edits | 4–9 |
| Strings, checks, hands-on run, merge | 6–11 |
| **Total** | **35–70** |

## Phases 3 to 7

Sized from the audit's touch sets. Re-plan each when it is next.

| | Phase 3. Search refinements | Phase 4. Install refinements |
| --- | --- | --- |
| Objective | Opened files rise in the list; a file can carry an alias | Display names and descriptions on the card; alternates as rows; formulae; upgrade and uninstall through Homebrew; adopting an app installed by hand |
| Existing files touched | `FileSearchQuery.swift`, `FileSearchCoordinator.swift` | `LauncherScreen.swift`, `LauncherList.swift` (one tail section) |
| New modules | None; reuses `LauncherRankingStore` and `AliasStore` | Additions inside `PackageInstall/` |
| Main risk | File ranking changes results people have learned | The full catalogue's memory cost (decision D4) |
| Tests | Extend `FileSearchTests` | Extend `PackageInstallTests` |
| Acceptance | A file opened three times outranks an unopened match | The card shows the app's display name, read from memory, with no request while typing |
| Hours | 12–28 | 30–65 |

| | Phase 5. Context actions | Phase 6. Typed OS actions |
| --- | --- | --- |
| Objective | One action list for selected text, Finder files, images and clipboard items; originals kept | Questions such as "what is using port 3000" answered through a fixed set of typed operations |
| Existing files touched | `CommandID.swift` and its switches, `ClipboardScreen.swift` | `CommandID.swift` and its switches; possibly `Fallback.swift` |
| New modules | `Features/ContextActions/`, beside Quick Actions. A native Finder-selection reader, written again outside the extension folder. | `Features/SystemQueries/`, with its own Service file that calls FoundationModels for typed output |
| Main risk | WebP output may need third-party code (Appendix B row 12) | Whether the on-device model picks operations reliably in a 4K to 8K context (row 11) |
| Tests | Model harness per transform; hands-on for capture | Model harness for every operation's parsing and limits |
| Acceptance | No transform overwrites its input; every destructive step asks | No operation runs a shell string from a model; each asks with its parameters shown |
| Hours | 45–100 | 60–130 |

**Phase 7. AI answers in the main list.** This is the hard-fork checkpoint described in
`PROPOSED_ARCHITECTURE.md` section 8. Before any code: measure the merge history accumulated since
Phase 0, decide between continuing to merge and cutting, and only then design. Sixty to 150 hours if
it goes ahead, with low confidence.

## Performance targets

These are targets. None has been measured. Upstream states one hard number that applies here,
resident memory under 100 MB; its other numeric budgets are per-feature benchmarks in
`docs/testing.md`, and it guards launch and summon time without a number.

| Metric | Target | How to measure |
| --- | --- | --- |
| Hotkey to visible panel | 100 ms at the 95th percentile | The existing `PaletteWindowController.show` signpost for the show itself; a 120 fps screen recording for the whole path |
| Keystroke to local rows | 16 ms at the 95th percentile | The existing `AppIndex.rank` signpost |
| Install card match | 2 ms at the 95th percentile | A new `Signposts.interval("PackageInstall.match")` |
| Return to approval dialog | 1 s median | A new `PackageInstall.lookup` signpost |
| Trigger to web results | 1.5 s median, 3 s at the 95th percentile | A new `WebSearch.fetch` signpost |
| Idle CPU, panel hidden | Under 0.5% averaged over 60 s | `top -pid` for one minute; Instruments Time Profiler if it is higher |
| Resident memory | Under 100 MB at upstream's four points; the cask index adds under 2 MB | `footprint` on the Dev build: idle after launch, panel open, feature in use, panel closed and settled |
| Time to first AI token | 1.5 s on device, 4 s through the Claude CLI | No signpost exists. Time ten asks from a screen recording. |
| AI cancel | Streaming stops within 100 ms of Return or Cmd-period | Screen recording |
| Install stop | Process gone within 2.5 s | The output window's final status; existing behaviour |

All signposts use subsystem `com.tinycast.perf`. In Instruments, open the `os_signpost` instrument and
filter to it; nothing needs recompiling. New signposts wrap the work in `Signposts.interval`, which
ends the interval even when the work throws.

## The first three tasks

Each is written to be handed to a coding agent as it stands. Each ends with one commit on
`universal-launcher` with a one-line subject. Paths are relative to the repository root.

### Task 1. Record the baseline

- **Goal.** Prove the untouched tree builds and passes upstream's checks on this Mac, observe risks R1
  and R2 before anything is changed, and write the results down. No source file changes.
- **Before starting.** The owner has installed Xcode 27 and said so.
- **Steps.**
  1. Install XcodeGen and SwiftLint (`brew install xcodegen swiftlint`) and confirm `node --version`.
  2. Run `security find-identity -p codesigning | grep "Tinycast Self-Signed"`. If it prints an
     identity, skip to step 3. Otherwise run the commands in `docs/signing.md` section 1, and before
     its final `rm`, copy `/tmp/tc.p12` to a location the owner names. That file holds the private
     key; its password is in the same section.
  3. Run `xcodegen generate`, then `git status --porcelain -- Tinycast.xcodeproj`. No output means
     regeneration is deterministic. If there is output, record the diff summary and run
     `git checkout -- Tinycast.xcodeproj`.
  4. Appendix B row 2: run `xcodebuild build -project Tinycast.xcodeproj -scheme Tinycast
     -configuration Debug CODE_SIGNING_ALLOWED=NO` and save the log. If `xcode-select -p` prints the
     Command Line Tools path, prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
     Count warnings as the number of distinct lines containing ` warning: `.
  5. Appendix B row 1: run `./Scripts/run-tests.sh`, then `./Scripts/lint.sh`.
  6. Appendix B row 7, before the gate: build a signed Debug app with `xcodebuild build -project
     Tinycast.xcodeproj -scheme Tinycast -configuration Debug -derivedDataPath build/DerivedData` and
     open `build/DerivedData/Build/Products/Debug/Tinycast Dev.app`. Type `date`, select the Run Shell
     Command row and press Return. Record whether it ran and whether anything asked first.
  7. Appendix B row 4, before the identity change: run `./Scripts/build-dmg.sh`, then open the app it
     built under `build/` without copying it to `/Applications`. Choose Check for Updates from the
     menu-bar menu. Record whether an update pill offers upstream's release. Do not click Update.
     Quit the app.
- **Output.** `docs/planning/BASELINE.md` with tool versions, the warning count, every failing harness
  with its message, the lint result, whether step 3 left a diff, and what steps 6 and 7 showed.
- **Done when.** The file exists, `git status --porcelain` shows no change outside `docs/planning/` and
  the ignored `build/` folder, and each failure is marked as pre-existing.
- **Do not.** Fix anything, edit a harness, run `./Scripts/format.sh`, click Update, or copy a built
  app into `/Applications`.

### Task 2. Give the build its own identity

- **Goal.** A Release build that upstream's updater ignores (risk R1).
- **Before starting.** Task 1 is committed. The owner has chosen the app name, bundle identifier and
  URL scheme (decision D1). They are written `<AppName>`, `<bundle-id>` and `<scheme>` below.
- **Steps.**
  1. In `project.yml`, under the top-level `configs:` entry `Release:`, add
     `TINYCAST_BUNDLE_IDENTIFIER: <bundle-id>` and `TINYCAST_URL_SCHEME: <scheme>`. In the `Tinycast`
     target's `configs:`, add a `Release:` entry with `PRODUCT_NAME: <AppName>`, next to the existing
     `Debug:` one. Four added lines.
  2. In `Tinycast/Features/Extensions/Model/ExtensionDeepLink.swift`, add `"<scheme>"` to the array
     of accepted schemes.
  3. In `Tinycast/Features/Launcher/Service/AppIndex.swift`, in `suggestions(from:usage:hotKeys:)`,
     add one condition to the `eligible` filter: `&& $0.bundleID != Bundle.main.bundleIdentifier`.
     Leave `ownBundlePrefix` as it is.
  4. Run `xcodegen generate`.
  5. Create `Scripts/fork/build-dmg.sh` from `Scripts/build-dmg.sh` with these changes: the first
     `cd` goes up two folders (`cd "$(dirname "$0")/../.."`); the app path, the disk image's file
     name and its volume name use `<AppName>`; and `LICENSE` is copied into the folder the disk image
     is made from.
  6. Create `docs/planning/FORK_LEDGER.md` with one entry per line changed in steps 1 to 3: file,
     symbol, what changed and why.
- **Verify.**
  - Run `./Scripts/fork/build-dmg.sh`. It finishes and leaves a disk image under `build/`.
  - `/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier'
    "build/DerivedData/Build/Products/Release/<AppName>.app/Contents/Info.plist"` prints
    `<bundle-id>`.
  - Open that app from `build/` (Appendix B row 5). The launcher lists no Check for Updates command.
    Choosing Check for Updates from the menu-bar menu shows the "This is a local build" message and
    offers nothing.
  - `./Scripts/run-tests.sh` gives the same result as the baseline.
- **Done when.** All four hold, and the diff outside `project.pbxproj`, the new script and the ledger
  is six lines.
- **Do not.** Rename `DICTATION_EXECUTABLE_NAME`, touch `Tinycast/Info.plist`, edit
  `ReleaseChannel.swift` or `ReleaseFeed.swift`, change the Debug configuration, or edit
  `Scripts/build-dmg.sh`.

### Task 3. Gate the shell fallback

- **Goal.** Typed text never reaches a shell without the Custom Commands switch and an explicit
  confirmation (risk R2).
- **Before starting.** Task 2 is committed.
- **Steps.**
  1. In `Tinycast/Features/Launcher/UI/FallbackCoordinator.swift`, in `isAvailable`, change the
     `.runShellCommand` arm to `return settings.customCommandsEnabled`, and delete the comment line
     above it.
  2. In `Tinycast/Features/CustomCommands/UI/CustomCommandCoordinator.swift`, in `runShellCommand`,
     add a confirmation as the first statement inside the existing `Task`: `guard await
     core.confirm(...) else { return }`, with the same arguments `perform` passes a few lines below
     (title `command.name`, the same localized message with `command.command` interpolated, `symbol:
     command.symbol`, confirm title "Run", `tone: .neutral`, `confirmRole: .standard`).
  3. Append to `docs/planning/FORK_LEDGER.md`: the two edits, and the three places in upstream's docs
     they make wrong (`docs/features/launcher.md`, the fallback table row that says "always" and the
     sentence that the fallback carries its own switch; `docs/features/custom-commands.md`, the
     sentence that it is not gated on `customCommandsEnabled`). Note that upstream chose the original
     behaviour deliberately.
- **Verify by hand**, since no harness compiles either file. Use a Debug build as in Task 1 step 6.
  - With Custom Commands off (Settings, Commands), type text that matches nothing: no Run Shell
    Command row.
  - Turn Custom Commands on: the row appears. Return shows a dialog containing the exact text.
  - Cancel: no output window opens. Confirm with `date` as the text: the window shows the date.
  - Run Again in the output window asks again.
- **Done when.** All four hold, harnesses and lint match the baseline, and the diff is one changed
  line, one removed line and about seven added.
- **Do not.** Edit upstream's docs or delete any preferences.
