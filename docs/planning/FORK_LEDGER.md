# Fork ledger

Every line the fork changes in an upstream file. On a merge conflict, check here what each line is for
before resolving it. New files the fork owns (`Scripts/fork/`, `docs/planning/`) are not listed.

## Changed lines

| Task | File | Symbol | Change | Why |
| --- | --- | --- | --- | --- |
| 2 | `project.yml` | `settings.configs.Release.TINYCAST_BUNDLE_IDENTIFIER` | Added `io.github.guysabban.spotcast` | Upstream's updater only follows `com.tinycast.app` (`ReleaseChannel`), so a renamed Release build is a local build and is never offered upstream's release (risk R1, D1) |
| 2 | `project.yml` | `settings.configs.Release.TINYCAST_URL_SCHEME` | Added `spotcast` | Links must not land in an installed upstream Tinycast, which owns `tinycast` (D1) |
| 2 | `project.yml` | `targets.Tinycast.settings.configs.Release` | Added the `Release:` key next to `Debug:` | Holds the Release-only product name below |
| 2 | `project.yml` | `targets.Tinycast.settings.configs.Release.PRODUCT_NAME` | Added `PRODUCT_NAME: Spotcast` | Gives the app its own name (D1). `DICTATION_EXECUTABLE_NAME` stays upstream's because `DictationWorker` hard-codes it |
| 2 | `Tinycast/Features/Extensions/Model/ExtensionDeepLink.swift` | the accepted-schemes array | Added `"spotcast"` | Without it, extension links on the fork's scheme are dropped |
| 2 | `Tinycast/Features/Launcher/Service/AppIndex.swift` | `suggestions(from:usage:hotKeys:)`, the `eligible` filter | Added `&& $0.bundleID != Bundle.main.bundleIdentifier` | Keeps the running app out of its own Suggestions. `ownBundlePrefix` only covers `com.tinycast.`, which Debug builds still use, so it stays |
| 3 | `Tinycast/Features/Launcher/UI/FallbackCoordinator.swift` | `isAvailable(_:)`, the `.runShellCommand` arm | `return true` became `return settings.customCommandsEnabled` | Typed text reaches a shell only while Custom Commands is on (risk R2) |
| 3 | `Tinycast/Features/Launcher/UI/FallbackCoordinator.swift` | `isAvailable(_:)` | Deleted the comment above the `.runShellCommand` arm | It said the shell is not the Custom Commands switch's to hold, which is no longer true |
| 3 | `Tinycast/Features/CustomCommands/UI/CustomCommandCoordinator.swift` | `runShellCommand(_:)` | The one-line `Task` now opens with `guard await core.confirm(...)`, using the same title, message, symbol, "Run" title, `.neutral` tone and `.standard` role as `perform` | Every run, including the output window's Run Again, shows the exact text and asks first (risk R2). Reuses `perform`'s strings, so no new localization |
| P1.1 | `Scripts/run-tests.sh` | the `run` list, after `MCPStdioTests` | Added `PI=Tinycast/Features/PackageInstall` and a two-line `run PackageInstallTests` entry | Registers the install model's harness. Kept together at the end of the list so a merge resolves by keeping both sides |
| P1.2 | `Scripts/run-tests.sh` | the `run` list, after `PackageInstallTests` | Added a `run CaskIndexStoreTests` entry, three lines since step 3 added `CaskAPI.swift` to it | Registers the index store's harness, in the same block |
| P1.3 | `Scripts/run-tests.sh` | the `run` list, after `CaskIndexStoreTests` | Added a six-line `run PackageInstallServiceTests` entry | Registers the services' harness. It also compiles upstream's `BundleSignature`, `PseudoTerminal`, `ProcessExit` and `ShellCommandRunner`, so a merge that renames one breaks this entry |
| P1.6 | `Scripts/run-tests.sh` | the `run` list, after `PackageInstallServiceTests` | Added an eight-line `run PackageInstallCoordinatorTests` entry | Drives the coordinator's card path end to end; it also compiles upstream's `Signposts` |
| P1.7 | `Tinycast/Resources/Localizable.xcstrings` | 73 new keys, in sorted position | Added every install-feature string with all eight translations; `%lld installs` and `%lld installs this month` carry plural forms | Upstream's rule that every shipped string is translated. Added lines only: `xcstringstool sync` rewrites upstream's `"" : {}`, a whitespace-only line and the missing final newline, so those three were put back as upstream spells them. Expect the same after any future `sync-strings.sh` run |
| P1.5 | `Tinycast/Features/Launcher/UI/LauncherList.swift` | `LeadCard` | Added `case package(PackageCandidate)`, its `sectionTitle` ("Install") and `rowID` ("package-card") arms | The install card is a lead card like the calculator's |
| P1.5 | `Tinycast/Features/Launcher/UI/LauncherList.swift` | `LeadCardView.body` | Added the `.package` arm drawing `PackageInstallCard` | The card's look stays in `PackageInstall/UI/` |
| P1.5 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | stored properties, `init` | Added `private let package: PackageCandidate?`, computed after `color` only when no calculation, colour or pinned row answers, and a `.package` branch in the `rows` chain before `meeting` | The card leads only for an install query; the calculator and colour cards keep priority |
| P1.5 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | `Row` | Added `case package(PackageCandidate)` and its `id` arm | The card is a row, so the flat selection still indexes `rows` |
| P1.5 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | `primaryActionTitle`, `isCardSelected`, `leadCard`, `actions(at:)`, `activate(at:)` | One `.package` arm each; `isCardSelected`'s first arm became `.calc, .meeting, .color, .package` | Each exhaustive switch must name the new row |
| P1.5 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | `hasPrimaryAction(at:)` | Added `if case .package(let candidate) = … { return candidate.hasAction }` first | Loading, no-match and unavailable cards drive neither the pill nor ⌘K |
| P1.5 | `Tinycast/App/AppCore.swift` | stored properties | Added `packageInstallSettings` and `caskIndex` (cache at `AppPaths.caches()/cask-index.json`) | `AppCore` owns every long-lived object |
| P1.5 | `Tinycast/App/AppCore.swift` | lazy coordinators | Added `packageInstallCoordinator` before `fileSearchCoordinator` | The feature's action surface |
| P1.5 | `Tinycast/App/AppCore.swift` | `start()` | Added `packageInstallCoordinator.applyEnabled()` after `currencyRates.start()`, and `packageInstallCoordinator.refreshInstalled()` inside the existing `onLauncherShown` closure | Starts the index store; keeps the card's installed and missing states current per show |
| P1.5 | `Tinycast/Features/Launcher/Settings/ApplicationsSettingsView.swift` | `body` | Added `PackageInstallSettingsSection()` after `SearchScopesSection()` | The feature's switch (decision D7) |
| P1.8 | `Tinycast/Windows/HUD/HUDPresenter.swift` | `dismiss()`, `scheduleDismissal()`, new `fadeAway(_:)` | Both fade-outs now go through `fadeAway`, which sets `panel.contentView = nil` once the panel is ordered out | An ordered-out panel kept its SwiftUI view, so the progress pill's spinner kept animating unseen: about 50 MB of graphics memory and 6.6% idle CPU until the next message replaced it (`BASELINE.md`, step 8). Every install lookup shows that pill. An upstream bug, also reachable through Quick Actions and clipboard OCR; worth offering upstream |
| P2.2 | `Scripts/run-tests.sh` | the `run` list, after `PackageInstallCoordinatorTests` | Added `WS=Tinycast/Features/WebSearch` and a one-line `run WebSearchTests` entry | Registers the web results model's harness, in the same end-of-list block |
| P2.3 | `Scripts/run-tests.sh` | the `run` list, after `WebSearchTests` | Added a one-line `run WebSearchSessionTests` entry | Registers the provider and session harness, in the same end-of-list block |
| P2.4 | `Scripts/run-tests.sh` | the `run` list, after `WebSearchSessionTests` | Added a two-line `run WebSearchSettingsTests` entry | Registers the settings harness, in the same end-of-list block. It also compiles upstream's `KeychainSecretStore`, so a merge that changes that file's API breaks this entry |
| P2.4 | `Tinycast/App/AppCore.swift` | stored properties | Added `webSearchSettings` after `packageInstallSettings` | `AppCore` owns every long-lived object; the Fallbacks section reads it from the environment |
| P2.4 | `Tinycast/Resources/Localizable.xcstrings` | 13 new keys, in sorted position | Added the web search settings strings with all eight translations | Same rule and the same `sync` rewrites as P1.7, put back as upstream spells them |
| P2.5 | `Scripts/run-tests.sh` | the `run` list, after `WebSearchSettingsTests` | Added a three-line `run WebSearchCoordinatorTests` entry | Drives the coordinator over the real store, Keychain scope, session and provider, in the same end-of-list block. It compiles upstream's `KeychainSecretStore` and `Signposts` |
| P2.5 | `Tinycast/App/AppCore.swift` | lazy coordinators | Added `webSearch` (the session, built with `WebSearchCoordinator.provider(for: webSearchSettings)`) and `webSearchCoordinator` before `fileSearchCoordinator` | `AppCore` owns the session; the coordinator's `init` points `webSearchSettings.onKeyRemoved` at `webSearch.forget()` |
| P2.5 | `Tinycast/Resources/Localizable.xcstrings` | 11 new keys, in sorted position | Added the web row, failure and menu strings with all eight translations | Same rule and the same `sync` rewrites as P1.7, put back as upstream spells them |
| P2.6 | `Tinycast/Features/Launcher/Model/CommandID.swift` | cases, `nameResource`, `sfSymbol` | Added `searchWeb = "command:search-web"`, its name "Search the Web" and the `magnifyingglass` symbol | The fallback takes its row name and glyph from a command |
| P2.6 | `Tinycast/Features/Launcher/Model/CommandID.swift` | `isQueryDriven` | Added `\|\| self == .searchWeb` | Never listed, ranked, pinned or bound as a standalone command, like Run Shell Command |
| P2.6 | `Tinycast/Features/Launcher/Model/Fallback.swift` | `Builtin`, `command`, `openVerb` | Added `case searchWeb` last, and one arm in each switch | Last, so a fresh install and an upgraded one both list it after Define Word |
| P2.6 | `Tinycast/Features/Launcher/UI/FallbackCoordinator.swift` | `run(_:query:)`, `isAvailable(_:)` | Added a `.searchWeb` arm to each: run calls `webSearchCoordinator.search`; available is `webSearchCoordinator.isAvailable` (on, with a key) | The fallback is offered only when a search can be sent |
| P2.6 | `Tinycast/Features/Launcher/UI/LauncherCoordinator.swift` | `run(_:)`, the query-driven arm | `.openInBrowser, .runShellCommand` became `.openInBrowser, .runShellCommand, .searchWeb` | Query-driven commands never run through this funnel |
| P2.6 | `Tinycast/Features/DeepLinks/Model/DeepLinkConsentPolicy.swift` | `requiresConsent(_:)` | Added `.searchWeb` to the consent arm | It would send text to a third party. It is query-driven, so no deep link reaches it today; the class is for the exhaustive switch |
| P2.6 | `Tests/HotKeyTests.swift` | the unbindable-commands check | `[.openInBrowser, .runShellCommand, .quit]` became `[.openInBrowser, .runShellCommand, .searchWeb, .quit]` | The roadmap's planned one-line harness edit: a query-driven command has no hotkey action |
| P2.6 | `Tinycast/Features/Launcher/UI/LauncherList.swift` | `web`, `WebSection`, `Row`, `webRows`, `rows`, `body` | Added `var web: WebSection?` after `files`, the `WebSection` struct, `case web(WebSearchRow, index:)` and its `id` arm, `webRows` (a "Web" header and the rows), `fileRows + webRows + fallbackRows`, `&& web == nil` in the empty check, and a `.web` arm drawing `WebSearchRowView` | The section sits between files and fallbacks; its look stays in `WebSearch/UI/` |
| P2.6 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | stored properties, `init` | Added `private let web: [WebSearchRow]`, read from `webSearchCoordinator.launcherRows(for:)` (not gated on a pinned row, since the fallbacks are not), and `+ web.map(Row.web)` before the fallbacks | Rows come from memory only, so typing never sends a request |
| P2.6 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | `Row`, `primaryActionTitle`, `isCardSelected`, `hasPrimaryAction(at:)`, `actions(at:)`, `activate(at:)` | Added `case web(WebSearchRow)` and one arm in each; a placeholder has no primary action; `activate` sends a Search the Web fallback to the new `searchWeb()`, and Return on No web results to Search Again (the owner's call) | Each exhaustive switch must name the new row |
| P2.6 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | `actions(at:)`, the `.fallback` arm | Passes `run: searchWeb` for the Search the Web fallback | The Cmd-K item moves the selection as Return does |
| P2.6 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | new `searchWeb()`, `selectFirstWebRow()`, `webSection`, `webRow(at:)`; `fileRow(at:)` | Added the four; `fileRow(at:)` now also subtracts `web.count`, wrapped to three lines | `searchWeb()` runs the fallback, then `selectFirstWebRow()` selects the first web row and calls `scrollToFollow()`; Search Again in a web row's menu does the same |
| P2.6 | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | new `move(_:axis:from:)` | Overrides `PaletteScreen`'s default, which returns nil; it adjusts only ↑/↓ into a placeholder past the first, through `WebSearchRow.landing` | Fewer rows can replace five placeholders, and the flat index would then fall on a fallback, so Return there would run, say, Quick AI |
| P2.6 | `Tinycast/Features/Launcher/UI/FallbackActionsMenu.swift` | `content(fallback:entry:query:core:)` | Added `run: (() -> Void)? = nil`; the primary item calls it when given, else `fallbackCoordinator.run` | The closure the roadmap names, so the screen can move the selection |
| P2.6 | `Tinycast/Features/Launcher/Settings/FallbacksSettingsView.swift` | `body` | Added `WebSearchSettingsSection()` after the fallbacks section | The feature's switch and key (decision D7) |
| P2.6 | `Tinycast/Resources/Localizable.xcstrings` | 2 new keys, in sorted position | Added "Search the Web" and "Web" with all eight translations | Same rule as P1.7. `sync-strings.sh` made no further change this time |

`Tinycast.xcodeproj/project.pbxproj` is regenerated from `project.yml` by `xcodegen generate` and is
never edited by hand.

## Merges

Each upstream merge, with what conflicted and how long it took (routine step 7). Details are in
`BASELINE.md`.

| Date | Upstream | Kept | Conflicts | Time |
| --- | --- | --- | --- | --- |
| 2026-11-13 | `upstream/main` `ede02bf3` (Phase 0 trial) | No | None | Seconds |
| 2026-11-13 | `v0.12.11`, the newest stable tag (Phase 1 step 9) | Nothing to merge | None: already an ancestor | 0 |
| 2026-11-13 | `upstream/main` `6fa8ba12`, eight commits (Phase 1 step 9 trial) | No | `project.pbxproj` only, resolved by the routine | About a minute |

At the next stable tag, upstream's move to `com.abueammar.tinycast` arrives. The Task 2
`AppIndex` note above then needs rewording, since `ownBundlePrefix` will match the Dev build's new
id. The fork must also never build or ship `TinycastHandoff`, which carries `com.tinycast.app`.

## Upstream doc errata

Upstream docs the fork knows are wrong. They are left unedited to keep merges clean.

- **`docs/signing.md` section 1:** with OpenSSL 3 or later (Homebrew installs 4.x), `security import`
  rejects the `.p12` with "MAC verification failed during PKCS12 import". Add `-legacy` to the
  `openssl pkcs12 -export` line. The owner's key is backed up in `~/Signing/`: the legacy-format
  `launcher-signing-legacy.p12` is the one to import. See `BASELINE.md`.

## Upstream docs the fork's behaviour contradicts

Upstream made the shell fallback ungated on purpose: in its view Custom Commands governs a library of
saved commands, not a line someone types deliberately, and the fallback's own checkbox is its switch.
The fork reverses that for risk R2. These upstream passages now describe upstream, not the fork, and
are left unedited:

- `docs/features/launcher.md`, the fallback table: the Run Shell Command row says it is available
  "always". In the fork it needs Custom Commands on.
- `docs/features/launcher.md`, "Run Shell Command carries its own switch, not the custom-command
  library's": in the fork it carries both, and it asks before every run.
- `docs/features/custom-commands.md`, "The ad-hoc run": "It is not gated on `customCommandsEnabled`".
  In the fork it is, and `runShellCommand` confirms first.
- `docs/features/launcher.md`, the fallback table, lists four built-in fallbacks. The fork adds a
  fifth, Search the Web, available when web search is on and a key is stored. See
  `docs/features/web-search.md`.

`Tinycast/Platform/KeychainSecretStore.swift` says every Keychain scope the app stores under is named
in that file. The fork leaves the file unedited and creates one more scope in its own code:

- `web-search-keys`: `WebSearchSettingsStore.keychain`, holding the Exa key (P2.4). A Keychain audit
  or a merge that renames scopes must look there as well as in the Platform file.
