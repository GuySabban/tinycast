# Implementation roadmap

Phases 0 to 7 in dependency order, MVP first. The design each phase implements is in
`PROPOSED_ARCHITECTURE.md`; what counts as the MVP is in `MVP_SCOPE.md`; risks, open decisions (D1
to D15), the repository layout and the merge routine are in `RISKS_AND_DECISIONS.md`.

Phases U1 to U5 extend the installer beyond Homebrew. They follow the Order bullet below, not their
place in this file. Their design, threats T14 to T21 and decisions D16 to D31 are in
`UNIVERSAL_INSTALL.md`. They are a plan under review: none starts before the owner approves that
document (D28).

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
  from the audit's touch sets and should be re-estimated when reached. U1 and U2 are planned in
  detail; U3 to U5 are sized from the research behind `UNIVERSAL_INSTALL.md`.
- **Order.** U1 needs only Phase 1, which is done apart from its feature document (U1 step 2) and
  the Homebrew-absent check (U1 step 6). U2 needs U1. U3 and U4 each need U2. U5 needs Phase 2, U2
  and U3, and U4 for packages. The recommended order is U1, U2, U3, U4, with Phase 2 any time before
  U5 (D27).

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
| U1 | Trust rules as tested code, and the Homebrew flow pinned by invariants | 21–42 |
| U2 | Official DMG and ZIP installs: casks without Homebrew, recorded addresses, a pasted address | 59–120 |
| U3 | Mac App Store: found through Apple, finished in the Store, confirmed afterwards | 26–54 |
| U4 | Official PKG installers: checked, described, opened in Installer | 28–58 |
| U5 | AI-assisted source discovery for apps in no catalogue (a hidden page, if built, is a further 15–35) | 50–99 |

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

- **The Terminal hand-off does not work as designed on macOS 27.** Settled on 2026-11-13 in step 3:
  it works with no prompt (decision D5).
- **Token matching misses common names.** Measured by the 50-name harness case. Fallback: the full
  catalogue (decision D4).
- **`brew` behaves differently under the pseudo-terminal** than its documentation suggests. Settled
  on 2026-11-13 in step 8: nothing waited for input, but Homebrew refuses a sudo cask before the
  download, with a second message that `refusedSudo` now also recognises (`BASELINE.md`).
- **SwiftUI and Swift 6 concurrency are new to the owner.** The largest uncertainty in the estimate.

### Tests

| Harness | Compiles | Covers |
| --- | --- | --- |
| `PackageInstallTests` | `PackageInstall/Model/*.swift`, plus `LauncherMatch.swift`, `SearchRelevance.swift` and `ScriptRomanization.swift` for scoring | Intent parsing; index decoding; match order for 50 names; record decoding for the three fixtures; every `InstallPlan` outcome; every verification outcome; token validation |
| `CaskIndexStoreTests` | The store and the model | First fetch, cached start, offline keeps the cache, a malformed reply is ignored. Served by an in-process `URLProtocol`, as `DictationWorkerTests` does. |

`LauncherScreen` and `LauncherList` have no harness upstream, so the card's wiring is covered by the
hands-on run. `PackageInstallServiceTests` covers the services, and `PackageInstallCoordinatorTests`
was added after a gap the plan-level cases missed (prowlarr, step 5): it drives
`PackageInstallCoordinator.candidate(for:)` end to end over a real store, a scratch Caskroom and
stand-ins for the app's own collaborators, in the style of `UninstallCoordinatorTests`. Since the
Phase 1 follow-up it also drives Return's lookup against a stubbed API, timing the progress pill.

### Acceptance

What the user sees is the Install list in `MVP_SCOPE.md`. This phase adds the measured criteria:

- Matching takes under 2 ms at the 95th percentile in a Release build (`PackageInstall.match`
  signpost). A Debug build runs `LauncherMatch` unoptimised and is about ten times slower.
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
   Give `WebSearchProvider.search` an options parameter with a default (search type, excluded
   domains), and build `ExaSearchRequest` from it. Phase U5 needs both, and adding the parameter
   later means changing the protocol. Record the signature in `PROPOSED_ARCHITECTURE.md` section
   5.2.
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

**Phase 4 and the universal install.** Phase 4's work goes through Homebrew and is unchanged. Two of
its items gain a case. An app that phase U2 installed natively is, to Homebrew, an app installed by
hand: `brew install --cask` stops on it, and `brew upgrade` and `brew uninstall` ignore it, until it
is adopted with `--adopt`. And nothing updates such an app unless it updates itself, so Phase 4 also
compares natively installed apps against their cask records.

## Universal install: phases U1 to U5

The design is `UNIVERSAL_INSTALL.md`; section and row numbers below refer to it.

- Each phase ends with the checks every phase ends with (harnesses, lint, the Model purity search, a
  Debug build with no new warnings), a hands-on run, and an upstream merge.
- **The regression check for the Homebrew flow** is the Install list in `MVP_SCOPE.md`, run with
  Homebrew present. It is run in U1 step 5 and after every later phase, and must not change. Its
  line about Homebrew being absent is replaced by U2's acceptance.
- U1 to U4 are planned on the recommended outcomes of D16, D17, D18, D22, D23, D24, D26 and D29. The
  owner confirms them with D28. A different choice is re-estimated before the phase that uses it.
- Every phase that adds a Swift file regenerates `Tinycast.xcodeproj/project.pbxproj` with
  `xcodegen generate`.

## Phase U1. Trust rules and the Homebrew guard

**Objective.** The rules that decide whether a download may be installed exist as pure, tested code,
and the Homebrew flow is pinned by written invariants, before anything new can install. Nothing the
user sees changes.

**Existing files touched.** `Scripts/run-tests.sh` (one entry), `NOTICE.md` (an appended notice),
the regenerated `project.pbxproj`, and four planning documents: `PROPOSED_ARCHITECTURE.md`,
`RISKS_AND_DECISIONS.md`, `MVP_SCOPE.md` and `FORK_LEDGER.md`. No existing file under
`Tinycast/Features/PackageInstall/` changes.

**New files.** In `PackageInstall/Model/`: `ArtifactEvidence.swift`, `SourceTrust.swift`,
`SourceTrustPolicy.swift`, `DownloadOrigin.swift`, `PublisherPin.swift`, `PublisherName.swift`,
`HopPolicy.swift`, `TeamAnchors.swift` and `TeamAnchors.generated.swift`. Also
`Scripts/fork/gen-team-anchors.js`, `Tests/SourceTrustTests.swift` and
`docs/features/package-install.md`.

### Steps

1. **Planning documents.** Apply section 11: move T14 to T21 and D16 to D31 into
   `RISKS_AND_DECISIONS.md`, amend T3, T4, T7, T9 and T11, lift the MVP non-goal (D28), and correct
   the four places where `PROPOSED_ARCHITECTURE.md` no longer matches the code (section 3.6). T1
   waits for U5.
2. **Feature document.** `docs/features/package-install.md`, owed since Phase 1, opening with
   Invariants: the fixed script and the token pattern; no network on a keystroke; the dialog's
   command is what runs; verification after `brew`; quarantine never cleared; a password only in
   Terminal or in Installer; and the new one, that no fact from a page, an address or a model sets a
   download's class.
3. **Model, test-first.** `DownloadOrigin`, `ArtifactEvidence`, `PublisherPin`,
   `PublisherName.fold`, `SourceTrust`, `SourceTrustPolicy.classify` and `HopPolicy.judge` (section 5.2), written against
   the cases in the Tests table below.
4. **Publisher table.** `gen-team-anchors.js` reads a pinned Installomator commit's label files as
   text and writes `TeamAnchors.generated.swift`, with a literal download address where a label has
   one. It prints the Team IDs that changed since the last run. Its `--self-test` mode must pass.
   Append Installomator's notice to `NOTICE.md`.
5. **Checks**, then the Install list in `MVP_SCOPE.md` by hand with Homebrew present, to record the
   flow before any phase touches it.
6. **Prove how Homebrew is hidden** (row 13). Launch the signed Dev app under a `sandbox-exec`
   profile that denies all of `/opt/homebrew`, run the Install list's Homebrew-absent line, which
   has never been run, and record the exact command in `BASELINE.md`. If it does not work, choose
   another method before U2.
7. **Merge upstream.**

### Risks

- **The label format moves.** The generator skips what it cannot read and reports the count. A drop
  of more than a few labels between runs fails the run.
- **Table names differ from what people type.** The table says "Microsoft Word"; the user types
  "word". The match is exact after folding, so a miss means "publisher unknown" and never a wrong
  anchor. Measure the miss rate on the 50 names the install harness already uses (D25).
- **A recorded address goes stale.** It is only a place to start, so a dead address costs a failed
  download, not a wrong install.
- **Hiding Homebrew may not work on the app.** `BASELINE.md` records the profile as tried on a shell
  only. Step 6 finds out before U2 depends on it.

### Tests

| Harness | Compiles | Covers |
| --- | --- | --- |
| `SourceTrustTests` (new) | `PackageInstall/Model/*.swift`, plus `LauncherMatch.swift`, `SearchRelevance.swift` and `ScriptRomanization.swift`, as `PackageInstallTests` does | **Anchors.** A checksum match is anchored; a mismatch is refused; a cask with no checksum and no other anchor is first seen; a pasted or discovered origin never classifies by checksum. A recorded publisher match is anchored; a different Team ID is refused as a publisher change, naming the table. A pin match by bundle identifier; a pin conflict by bundle identifier; a pinned name under a new bundle identifier with a different Team ID is refused. **Names.** A paste with no typed name whose folder is named like a recorded app and signed by another team is refused; a typed name and a bundle name with different entries are both checked; a look-alike spelling in another script folds to the recorded entry; a fuzzy name never anchors; labels sharing a name pool their Team IDs. **Never inputs.** Two different final hosts give the same class; notarized with no anchor is first seen, never anchored. **Gates.** An unsigned or un-notarized build, a `com.apple.` identifier, a name that folds to an Apple app's, an Intel-only build, a version below the cask's, an existing app and a missing quarantine flag are each refused. `HopPolicy`: an `http` hop, a user name, a port, an IP literal, a punycode label and six redirects are each refused by name. |
| `PackageInstallTests` (unchanged file) | The same sources, which now include the new Model files | That the existing cases still pass with the new files compiled in |

The generator's safety is checked by its own `--self-test`, not by a Swift harness: a label holding
`$(…)`, a Team ID that is not ten characters, and an address with a `$` or a space each yield
nothing.

### Acceptance

- Every existing harness passes. Before the upstream merge, `git diff --stat` against the phase's
  start shows only new files and the files listed under "Existing files touched".
- Each rule of section 2 has a case that fails when the rule is removed.
- The generator gives the same file when run twice, and its self-test passes.
- The feature document exists and opens with Invariants.
- `BASELINE.md` records the command that hides Homebrew from the app, and what the Homebrew-absent
  line showed.

### Hours

| Step | Hours |
| --- | ---: |
| Planning documents amended | 1–2 |
| Feature document | 2–4 |
| Trust model and its harness | 9–18 |
| Publisher table generator, its self-test, the generated file, the notice | 6–12 |
| Checks, the regression run, hiding Homebrew, upstream merge | 3–6 |
| **Total** | **21–42** |

## Phase U2. Official DMG and ZIP installs

**Objective.** A plain app cask installs on a Mac without Homebrew; an app with a recorded download
address installs with no web search; and `install https://…` downloads, checks and installs a disk
image or zip. All as specified in sections 4, 5.3 and 5.4. Needs U1.

**Existing files touched.** Fork-owned, all under `Tinycast/Features/PackageInstall/`:
`Model/CaskRecord.swift` (decode `sha256`, `container`, `url_specs`, `auto_updates` and the macOS
requirement), `Model/InstallPlan.swift` (`.download`, a second factory),
`Model/InstallVerification.swift` (one field and one case renamed from "Caskroom" to "install
record"), `Model/InstallIntent.swift` (an `https` address), `Model/PackageCandidate.swift` (`.link`,
and an action on no match when the table has an address), `Service/InstallVerifier.swift` (an
overload that takes app paths; `isTrusted` no longer private), `UI/PackageInstallCoordinator.swift`,
`UI/PackageInstallCard.swift`, `UI/PackageActionsMenu.swift`, both Settings files, and the four
harnesses. Upstream-owned: `Tinycast/App/AppCore.swift` (two lines), `Scripts/run-tests.sh`,
`Tinycast/Resources/Localizable.xcstrings`, and the regenerated `project.pbxproj`.
`LauncherScreen.swift` and `LauncherList.swift` take no change.

**New files.** Model: `InstallSource`, `DownloadOffer`, `ArtifactKind`, `DiskImageTrailer`,
`ZipDirectory`, `StagedContents`, `DownloadApproval`. Service: `ArtifactDownloader`,
`DiskImageService`, `ZipArchiveService`, `BundleInspector`, `AppPlacer`, `PublisherPinStore`.
`Tests/PackageDownloadTests.swift`, and three more cask fixtures: a disk-image cask with a checksum,
a zip cask, and one whose checksum is `no_check`.

### Steps

1. **Model, test-first.** The record's new fields; `InstallSource`; `DownloadOffer`; the plan's new
   case; `ArtifactKind`, `DiskImageTrailer`, `ZipDirectory`, `StagedContents`; `DownloadApproval`
   with each dialog's text, buttons and default.
2. **Downloader**, with an in-process protocol stub as its harness. Settles row 8.
3. **Disk image and zip services**, exercised on scratch files the harness builds itself
   (`diskutil image create`, `ditto -c -k`). Settles rows 6, 7 and 11.
4. **Row 5.** Read `diskutil image` in Apple's macOS 26 manual, or run it in a macOS 26 virtual
   machine. If it is absent there, attach with `hdiutil` under an availability check on 26 only.
5. **Inspector and placer**, with a `PackageInstall.inspect` signpost around the check. A scratch
   bundle signed ad hoc must fail; a scratch "Applications" folder stands in for the real one.
6. **Pins and settings.** `PublisherPinStore`; the unknown-publisher switch under a raw key (D16);
   buttons that forget one remembered publisher or all of them; the section's title, header and
   sentence about what leaves the Mac (section 3.6).
7. **Coordinator.** The native path where the flow shows the Homebrew setup dialog today, kept as a
   second button; a recorded address on the no-match card; the card for a pasted address; consent,
   download with progress lines in the output window, checks, the approval for each class, Keep
   Download, placement, rescan; `lastRun` as an `InstallSource`.
8. **Strings**, eight languages, `./Scripts/sync-strings.sh`.
9. **Checks.**
10. **Hands-on run.**
    - With the app launched normally and Homebrew present: paste an address for an app with a
      recorded publisher, one for an app without, and one for an unsigned app. Settle rows 1 to 4,
      9, 10 and 12 here, because a sandbox profile could change what they show.
    - With Homebrew hidden as U1 step 6 recorded: install three plain casks natively, one of them
      with no checksum.
11. **Feature document, fork ledger, upstream merge.**

### Risks

- **Translocation.** A quarantined app copied by the launcher may run from a randomised path, which
  stops some apps from updating themselves. Row 1 measures it; D17's recommendation is to leave
  macOS's behaviour alone and say so in the approval.
- **`diskutil image attach` on macOS 26.** It is the current tool on 27, where `hdiutil` is
  deprecated. Step 4 checks 26.
- **Disk space.** This Mac has run below 1 GB free. The downloader checks free space before it
  starts and refuses politely.
- **The seal check on a large app** takes seconds. The output window says "Checking…" while it
  runs.
- **The downloader is the hardest new code for the owner**: a delegate, a stream, hashing and
  cancellation together.
- **About 35 strings** in eight languages.

### Tests

| Harness | Compiles | Covers |
| --- | --- | --- |
| `PackageInstallTests` (extended) | As today | The record's new fields on the fixtures; every new plan outcome; `ArtifactKind` on byte fixtures; each `ZipDirectory` danger; `StagedContents` for one app, two apps, a package, and an `Applications` shortcut; `DownloadApproval` for every class with and without the switch: Install is the default only when anchored, and a first seen dialog never defaults to Install or to a page |
| `PackageDownloadTests` (new) | The model sources as `PackageInstallTests` lists them, the new services, and upstream's `ToolRunner.swift`, `BundleSignature.swift` and `Quarantine.swift` | Downloader through the stub: a redirect chain followed and recorded, an `http` hop refused, six redirects refused, the cap, a non-200 status, the hash of known bytes, quarantine set on the file, cancel leaving nothing behind. Disk image: build, attach, choose, detach; a licence image is never opened unless its hash matches a cask checksum; an encrypted one refused. Zip: expand; a link that leaves the tree refused. Inspector: ad hoc, unsigned and tampered bundles refused; the declarations read from a scratch `Info.plist`. Placer: an occupied target, a changed hash and a missing quarantine flag each refused. |
| `PackageInstallCoordinatorTests` (extended) | As today, plus the new sources and stand-ins for the new collaborators | Homebrew missing and a plain cask gives the consent, then the approval; a recorded address gives the same from the no-match card; a pasted address downloads and then asks; Keep Download moves the file and installs nothing; Stop deletes the staging folder; a pasted package is refused as not supported yet; the card's Return contacts only the stub's Homebrew host |

No harness can hold a real notarized app, so the passing case of the signature gate is covered by
the hands-on run.

### Acceptance

- With Homebrew hidden, `install rectangle` shows the consent, then the approval with the signer,
  and installs Rectangle. The download's hash equals the cask's, the installed app carries the
  quarantine attribute, and typing its name finds it without a relaunch.
- With Homebrew hidden, a cask with no checksum whose publisher is not on record ends in the first
  seen dialog, not an install.
- With Homebrew present, the Install list in `MVP_SCOPE.md` passes unchanged, and the `brew`
  processes the app starts are the same as before.
- A pasted address for an app with a recorded publisher installs after its approval. For an app
  without one, the dialog says the publisher is unknown, its default is Cancel, and Keep Download
  leaves the checked file in `~/Downloads`, still quarantined. With the switch off there is no
  Install Anyway.
- An unsigned app, a zip with an escaping link, an image with two apps and an `http` hop are each
  refused with their own message, and the staging folder is gone. An app that is signed but not
  notarized is refused too: by a real download if step 10 finds one, otherwise shown through a
  captured evidence value in the harness.
- Stop during a download ends the transfer within a second and leaves no file.
- No existing app is ever replaced.
- The staged app check takes under 3 s at the 95th percentile for apps under 500 MB.
- Resident memory stays under 100 MB at the four points and during a 500 MB download. The publisher
  table adds under 0.5 MB.
- Lines changed in upstream-owned files are within 20% of section 9's budget.

### Hours

| Step | Hours |
| --- | ---: |
| Record additions, plan case, dialog text, harness cases | 5–10 |
| Downloader and its harness | 8–16 |
| Disk image, zip and contents rules, with the scratch-file harness | 10–20 |
| The macOS 26 check for `diskutil image` | 1–3 |
| Inspector and placer, with harness | 9–18 |
| Pins, the unknown-publisher switch, settings | 4–8 |
| Coordinator: three sources, two dialogs, progress, Stop, Keep Download | 10–20 |
| Strings and lint | 3–6 |
| Hands-on run and fixes | 8–16 |
| Feature document and upstream merge | 1–3 |
| **Total** | **59–120** |

## Phases U3 and U4

Sized from the research. Re-plan each when it is next. Both need U2; they can be done in either
order.

| | Phase U3. Mac App Store | Phase U4. Official PKG installers |
| --- | --- | --- |
| Objective | When no cask matches and the publisher list has no address, Return asks Apple. A listing opens the Store on the product page, and the launcher confirms the app once it arrives (section 5.5). | A notarized Developer ID package is checked, described truthfully and opened in Installer: a package cask without Homebrew, a package inside a disk image, a pasted address (section 5.6). |
| Existing files touched | Fork-owned: `PackageCandidate.swift` (`hasAction` on every no match), `PackageInstallCard.swift`, `PackageActionsMenu.swift`, `PackageInstallCoordinator.swift`, `InstallPlan.swift` (`.openAppStore`), `InstallSource.swift`, `InstallVerifier.swift` (the Store requirement). Upstream-owned: `Scripts/run-tests.sh`, `Localizable.xcstrings`, the regenerated `project.pbxproj`. | Fork-owned: `CaskRecord.swift` (the package artifact), `InstallPlan.swift` (`.openInstaller`), `StagedContents.swift`, `DownloadApproval.swift`, `PackageInstallCoordinator.swift`. Upstream-owned: `Scripts/run-tests.sh`, `Localizable.xcstrings`, the regenerated `project.pbxproj`. |
| New files | `AppStoreListing`, `AppStoreAPI`, `AppStoreArrivalMonitor`, `Tests/AppStoreTests.swift`, three captured search replies | `PackageSummary`, `PackageSignature`, `PackageInspector`, `InstallerHandoff`, `Tests/PackageInspectionTests.swift`, captured `Distribution`, `PackageInfo`, `pkgutil` and `spctl` output |
| Steps | Model against captured replies. The search service behind a stub, with a `PackageInstall.storeLookup` signpost. The no-match card, the listing dialog with up to three choices, Open in App Store. The monitor and the Store signature check. One more button on the "moved to the Mac App Store" notice. A hands-on run that settles rows 14 to 17: a free app never obtained, a paid app, and the Store signed out. | A hands-on run first, to capture real output (rows 18 and 19). Model against the captured files. The inspector on scratch packages from `pkgbuild`. The package dialog and the hand-off, with the hash compared just before it. The receipt check afterwards. |
| Main risk | Name search misses real apps ("xcode" does not return Xcode) and ranks copycats, so nothing is chosen without an exact name match. The storefront may be wrong (row 14). | The signature can only be read from two tools' text output. The Team ID is taken from the end of the leaf's line, both tools must agree, and whatever does not parse is refused. |
| Tests | `AppStoreTests`: decoding; the exact-match rule; a copycat never auto-chosen; free and paid; a reply edited to need macOS 99 is stopped with the reason; the link's form; an ID that is not digits rejected. The service through a stub. Coordinator: Return on no match sends one request, to Apple's host only; a new flow stops the monitor. | `PackageInspectionTests`: flags from each fixture; a legal name that contains a parenthesised ten-character group does not fool the parser; the two tools disagreeing is a refusal; an unsigned scratch package refused; captured output edited to drop the notarization line refused; a first seen package offers no Open Installer; no `installer` or `sudo` process ever started. |
| Acceptance | Return to the listing dialog in under 1.5 s at the median. Open in App Store lands on the product page. After the user clicks Get, the launcher confirms within 10 s of the app appearing, having checked the Store signature and the bundle identifier. A paid app shows its price and nothing attempts to buy it. | With Homebrew hidden, `install zoom` shows the signer, Team ID, identifiers, locations and the scripts line, and Open Installer opens Installer on the package. After it finishes, the launcher confirms from the receipt. An unsigned package is refused. With Homebrew present, package casks behave as today. |
| Hours | 26–54 | 28–58 |

## Phase U5. AI-assisted source discovery

**Objective.** For an app in no catalogue, the choice "Search the Web for a Download" finds the
vendor's own download and hands it to U2's executor, as specified in section 6. Needs Phase 2, U2
and U3, and U4 for packages.

**Existing files touched.** Fork-owned: `PackageInstallCoordinator.swift`,
`PackageActionsMenu.swift`, the Settings section, and Phase 2's `WebSearchProvider` if it lacks the
options parameter. Upstream-owned: `Tinycast/App/AppCore.swift` (one or two changed lines),
`Scripts/run-tests.sh`, `Localizable.xcstrings`, the regenerated `project.pbxproj`. Nothing under
`Tinycast/Features/AI` changes.

**New files.** Model: `LinkExtractor`, `DownloadCandidate`, `CandidateScorer`, `PageWall`,
`PickPrompt`. Service: `PageFetcher`, `SourceDiscovery`, `DownloadLinkPicker` (the only file that
imports `FoundationModels`). `Tests/SourceDiscoveryTests.swift` and `Tests/discovery-fixtures/`.

### Steps

1. Phase 2's provider options, if they are not already there.
2. Save 20 vendor download pages as fixtures. Choose apps the publisher table lists and Homebrew
   lacks, so "the right download" can be checked by Team ID.
3. Model, test-first, against the fixtures.
4. The page fetcher and the GitHub releases reader, behind a stub.
5. The on-device picker, sized to the model's reported window, with the error types under an
   availability check (row 23).
6. The flow, with a `PackageInstall.discover` signpost: the choice, the candidate dialog, Try Next
   Result, the hand-over to the executor.
7. Strings and checks.
8. A live run on the 20 apps.
9. If the live run finds fewer than 15 of the 20 with no model, run the hidden-page spike by section
   6.5's criteria (D21).
10. The feature document, the T1 amendment, upstream merge.

### Risks

- Vendor pages change, so fixtures go stale and the live run is the real measure.
- The on-device model may pick no better than the scorer. Measure both, and keep the model only if
  it adds hits.
- Search results for small apps may be poor.
- The page helper's memory is outside the app's own footprint.

### Tests

`SourceDiscoveryTests` compiles the model sources and covers:

- links extracted from each fixture; `data:`, `javascript:` and `file:` links and a hostile base
  address dropped; the 200-link cap;
- the scorer's choice on each fixture, and that a host containing the app's name earns nothing;
- every seeded sign-in, payment and CAPTCHA page detected;
- the prompt holds only the built list and no page body; a reply that is not a position is "none";
- the same class with and without a model's pick.

`PackageInstallCoordinatorTests` adds: the card's Return sends nothing to the search provider or a
vendor; one discovery choice sends exactly one search and reads at most two pages; a refusal waits
for Try Next Result.

### Acceptance

- On the 20 apps: the right download for at least 15 with no model, and at least 18 with the
  on-device tie-break, or the model is left out.
- No build is installed whose Team ID differs from the table's.
- Every seeded wall is detected and nothing is filled in.
- With AI off, the flow completes with the person choosing.
- The choice to the candidate dialog takes under 8 s at the median.
- The app's own footprint stays under 100 MB. The page helpers, if built, stay under 150 MB together
  and are gone afterwards.

### Hours

| Step | Hours |
| --- | ---: |
| Phase 2's provider options, if not already there | 1–3 |
| Extractor, scorer, wall detector, pick prompt, with the page fixtures | 10–20 |
| Page fetcher, releases reader, harness | 5–10 |
| On-device picker | 5–12 |
| The flow, the candidate dialog, the hand-over | 8–16 |
| Strings and lint | 3–6 |
| Live run on 20 apps, and fixes | 8–16 |
| Hidden-page spike, only if step 9 calls for it | 8–12 |
| Feature document, T1 amendment, upstream merge | 2–4 |
| **Total** | **50–99** |

Without the spike the total is 42 to 87. Neither figure covers building the hidden page. If the
spike says go, that is a further 15 to 35 hours, with low confidence.

## Performance targets

These are targets. None has been measured. Upstream states one hard number that applies here,
resident memory under 100 MB; its other numeric budgets are per-feature benchmarks in
`docs/testing.md`, and it guards launch and summon time without a number.

| Metric | Target | How to measure |
| --- | --- | --- |
| Hotkey to visible panel | 100 ms at the 95th percentile | The existing `PaletteWindowController.show` signpost for the show itself; a 120 fps screen recording for the whole path |
| Keystroke to local rows | 16 ms at the 95th percentile | The existing `AppIndex.rank` signpost |
| Install card match | 2 ms at the 95th percentile, Release build | A new `Signposts.interval("PackageInstall.match")` |
| Return to approval dialog | 1 s median | A new `PackageInstall.lookup` signpost |
| Trigger to web results | 1.5 s median, 3 s at the 95th percentile | A new `WebSearch.fetch` signpost |
| Idle CPU, panel hidden | Under 0.5% averaged over 60 s | `top -pid` for one minute; Instruments Time Profiler if it is higher |
| Resident memory | Under 100 MB at upstream's four points; the cask index adds under 2 MB | `footprint` on the Dev build: idle after launch, panel open, feature in use, panel closed and settled |
| Time to first AI token | 1.5 s on device, 4 s through the Claude CLI | No signpost exists. Time ten asks from a screen recording. |
| AI cancel | Streaming stops within 100 ms of Return or Cmd-period | Screen recording |
| Install stop | Process gone within 2.5 s | The output window's final status; existing behaviour |
| Download stop (U2) | Transfer ended and staging deleted within 1 s | The output window's final status and the staging folder |
| Staged app check (U2) | 3 s at the 95th percentile for apps under 500 MB | A new `PackageInstall.inspect` signpost |
| No match to the App Store dialog (U3) | 1.5 s median | A new `PackageInstall.storeLookup` signpost |
| Discovery choice to candidate dialog (U5) | 8 s median | A new `PackageInstall.discover` signpost |
| Memory during discovery (U5) | The app under 100 MB; the page helpers, if built, under 150 MB together and gone after the run | `footprint` on each process |

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
