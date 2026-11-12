# Tinycast architecture audit

Audit of Tinycast as the base for a personal AI launcher. Research only: no source, dependency,
project or script file was changed, and nothing was built or run.

- **Audited tree:** commit `d9414598` (2026-11-12) on branch `universal-launcher`, identical to
  upstream `main` and tag `v0.12.12-beta.139`.
- **Date:** 2026-11-12.
- **How claims are marked.** A statement about code with a path and symbol was read in source. A
  statement marked DOC-ONLY comes from a repo document and was not checked in code. UNVERIFIED means
  nothing settled it; where a build or a run would, Appendix B gives the command. Appendix C explains
  how claims were checked and where the checking is weak.
- **Paths** are relative to the repo root.

## Corrections to the brief

The evidence contradicts six points in the brief. Each is detailed in the section named.

| Brief | What the repo shows | Section |
| --- | --- | --- |
| Self-signed distribution "as upstream does" | Upstream releases have been Developer ID signed and notarized since commit `dc265b26` (2026-11-05, #1803) and ship through the official Homebrew cask. Only local builds use the self-signed identity. The self-signed release pipeline survives in git history. | 9 |
| "Spotlight-based file search" | Replaced on 2026-10-13 (#1537) by Tinycast's own disk index. No `NSMetadataQuery`, `MDQuery` or `mdfind` remains in the app. | 1.6, 2 |
| "My fork" | `origin` is `abue-ammar/tinycast` itself and the local branch is 0 commits ahead. There is no fork remote yet. | 7 |
| "No backends" | The app calls a service upstream runs (`tinycast.dev/api/v1/currencies`), Raycast's unofficial store API, the GitHub API and Hugging Face. | 1.11 |
| "No cloud API key yet", so on-device first | Tinycast's code can use an installed, signed-in `claude` or `codex` CLI with no API key (read in code, not run). The on-device route in Tinycast is text-only, although Apple's SDK supports tools and guided generation. | 3 |
| Build on this Mac | This Mac has the Command Line Tools only: no Xcode app, XcodeGen or SwiftLint. The docs require Xcode 27. | 1.12 |

## 1. Map of the codebase

### 1.1 Modules and size

About 133,000 lines of Swift in the app, 47,000 in tests, 8,000 lines of JavaScript for the extension
runtime, and 15,000 lines of documentation.

| Folder | Lines | Files | Holds |
| --- | ---: | ---: | --- |
| `Tinycast/App` | 1,227 | 4 | `@main`, `AppDelegate`, `AppCore` (the composition root) |
| `Tinycast/Palette` | 4,285 | 22 | The panel, its window controller, `RootPaletteView`, modes and screens |
| `Tinycast/DesignSystem` | 4,512 | 37 | Shared visual primitives; `Theme.swift` holds the tokens |
| `Tinycast/Platform` | 2,525 | 41 | System shims: `AppPaths`, `Permissions`, `KeychainSecretStore`, `ExecutableLocator`, `PseudoTerminal` |
| `Tinycast/Windows` | 1,326 | 16 | Dialogs, HUD, About, titled windows |
| `Tinycast/Features` | 119,547 | 750 | One folder per feature (below) |
| `Tests` | 47,285 | 127 | Single-file harnesses, no XCTest |
| `Scripts/raycast-runtime/src` | 7,960 | 20 | JavaScript source of the extension runtime |

Features relevant to this audit, by size: `AI` 21,793 lines, `Extensions` 14,583, `Calculator` 9,643,
`Launcher` 6,200, `Settings` 4,799, `HotKeys` 4,377, `Clipboard` 4,132, `Snippets` 3,738,
`FileSearch` 3,418, `MCP` 2,874, `CustomCommands` 2,670, `Quicklinks` 2,457, `QuickActions` 2,293,
`Uninstall` 1,417, `TextInjection` 1,282, `Updates` 1,235, `SystemActions` 1,117, `Dictionary` 810,
`DeepLinks` 793, `AppleShortcuts` 253.

Features outside the audit's questions, one line each:

- `WindowManagement` (9,116 lines): window snapping, layouts and rooms.
- `Notes` (5,656): a floating Markdown note.
- `Emoji` (3,524): emoji and symbol picker.
- `Backup` (3,015): settings backup archives.
- `Dictation` (2,912): local speech-to-text with its own helper app.
- `Calendar` (2,687): meetings in the launcher and a menu-bar item.
- `MenuSearch` (856): search the front app's menus.
- `WindowSwitcher` (560): switch windows from the palette.
- `Onboarding` (537), `Camera` (495), `Support` (261).

The project has four build targets (`project.yml`, `targets`): the `Tinycast` app, the
`ClipboardTextHelper` and `FileIndexHelper` tools, and the `DictationHelper` app. The `website/`
folder in the same repo is upstream's site and the Cloudflare Worker that serves the currency API.

### 1.2 Startup and lifecycle

- The `@main` type is `TinycastLaunch` (`Tinycast/App/TinycastApp.swift`). It pins the interface
  language and runs `TinycastApp`, which declares only two `MenuBarExtra` scenes.
- `AppDelegate.applicationDidFinishLaunching` (`Tinycast/App/AppDelegate.swift`) calls
  `AppCore.shared.start(launchedByUser:)`.
- `AppCore` (`Tinycast/App/AppCore.swift`) is a `@MainActor @Observable` singleton. Stores,
  `HotKeyManager`, `PaletteState`, `ExtensionManager` and the AI stores are built in `init`. Its 35
  coordinators, the palette window controller, dialogs and the HUD are lazy.
- `AppCore.start` sets the accessory activation policy, calls `applyEnabled()` on most feature
  coordinators, wires every hotkey callback to a coordinator through closures, and defers the app and
  emoji index loads into tasks. The panel itself is built on the first `show()`.
- A coordinator is one feature's action surface. Views receive `AppCore` through `@Environment`
  (`Tinycast/Palette/PaletteEnvironment.swift`, `paletteEnvironment`) and call
  `core.someCoordinator.method()`. The documented rule is that new long-lived state goes on `AppCore`
  and is wired in `start()`, never in a second singleton (`docs/architecture.md`, DOC-ONLY).
- Setting changes reach features through `AppCore.track`, which re-arms `withObservationTracking`
  inside a task.

### 1.3 Global hotkey to visible panel

1. `HotKeyCenter.activate` (`Tinycast/Features/HotKeys/Service/HotKeyCenter.swift`) registers each
   chord with Carbon `RegisterEventHotKey`.
2. `HotKeyManager.perform` (`Tinycast/Features/HotKeys/Service/HotKeyManager.swift`) checks
   `allowsAction`, then switches exhaustively over `HotKeyAction`.
3. The `onTogglePalette` closure set in `AppCore.start` calls `PaletteCoordinator.togglePalette`
   (`Tinycast/Palette/PaletteCoordinator.swift`), which calls `showPalette`.
4. `PaletteWindowController.show` (`Tinycast/Palette/PaletteWindowController.swift`) records the
   previous app, positions the panel, then calls `makeKeyAndOrderFront` and `orderFrontRegardless`.

No default chord is registered. First launch shows onboarding, which records the shortcut.
Modifier-only bindings use a separate listen-only event tap (`ModifierTapMonitor`).

### 1.4 Panel window

- `PalettePanel` (`Tinycast/Palette/PalettePanel.swift`) is a borderless, non-activating `NSPanel` on
  all Spaces. Its hosting view has `sizingOptions = []`, so `PaletteWindowController` owns the frame.
- The panel hides when it loses key status, unless a dialog, a menu or a modal is up
  (`PaletteWindowController.windowDidResignKey`).
- Hiding schedules a pop-to-root timer (`popToRootTimeout`); `popToRoot` resets the screen to the
  launcher and leaves a chat untouched.
- The Cmd-K action menu is a child panel (`Tinycast/Palette/MenuPanel.swift`).

### 1.5 Modes and screens

`PaletteMode` (`Tinycast/Palette/PaletteMode.swift`) is a closed enum with 23 cases: `launcher`,
`clipboard`, `ai`, `aiHistory`, `calculatorHistory`, `emoji`, `fileSearch`, `menuSearch`,
`switchWindows`, `rooms`, `roomWindows`, `schedule`, `eventEditor`, `customCommandEditor`,
`customCommands`, `meetingDetails`, `uninstall`, `quicklinks`, `quicklinkEditor`, `snippets`,
`snippetEditor`, `dictionary`, `extensionCommand`.

Each mode maps to one struct conforming to the `PaletteScreen` protocol
(`Tinycast/Palette/PaletteScreen.swift`). The mapping is an exhaustive switch in
`RootPaletteView.screen` (`Tinycast/Palette/RootPaletteView.swift`), rebuilt on every access. A screen
must supply `rows`, `primaryActionTitle`, `activate(at:)`, `secondary(at:)` and
`body(selection:scroll:)`; everything else has a default. `PaletteState`
(`Tinycast/Palette/PaletteState.swift`) holds the mode, the back stack, the query and the selection.

### 1.6 Query pipeline

There is no single router function. The path from keystroke to rows is:

1. The search field binds to `PaletteState.query`.
2. One `onChange(of: vm.query)` block in `RootPaletteView.stateObservers` runs the per-mode side
   effect. In `launcher` mode it calls `FileSearchCoordinator.searchFromLauncher`. In other modes it
   calls that mode's search or, for an extension command, dispatches the text to the JavaScript
   runtime. The shell adds no debounce.
3. Root rows are not pushed anywhere. Each render builds a `LauncherScreen`
   (`Tinycast/Features/Launcher/UI/LauncherScreen.swift`), and `LauncherScreen.init` assembles `rows`
   synchronously on the main actor.

`LauncherScreen.Row` is a closed enum with six cases: `calc`, `meeting`, `color`, `entry`, `file`,
`fallback`. The order is fixed:

1. At most one lead card: calculator, else colour, else the next meeting.
2. Pinned favorites.
3. Entry results from `AppIndex.orderedResults`. A typed web address inserts an Open in Browser row
   first (`CommandCatalog.openInBrowser(for:)`).
4. Up to five file rows. Indexed files need a query of three or more characters; a favorite file can
   match a shorter one.
5. Fallback rows, for any non-blank query.

`AppIndex` (`Tinycast/Features/Launcher/Service/AppIndex.swift`) keeps one private array per source.
Each is replaced by its own setter (`setExtensionCommands`, `setQuicklinks`, `setCustomCommands` and
so on), called by that feature's coordinator. `publishEntries` joins the arrays in a fixed order and
bumps a revision that keys two memos (`MatchKey`, `ResultsKey`). Sources are applications and System
Settings panes, meetings, extension commands, quicklinks, Apple Shortcuts, snippets, system actions,
window layouts, rooms, window commands, custom sizes, custom commands, Quick Actions and built-in
commands.

Two things run off the main actor: the application scan (`AppIndex.refresh`, detached, utility
priority) and file search (`FileSearchSession`, a single worker that keeps only the latest request).
File rows read the session's last published results, which makes file search the only asynchronous
source feeding the root list.

`AppEntry.Kind` is a closed 14-case enum: `application`, `systemSettings`, `command`, `quickAction`,
`customCommand`, `snippet`, `systemAction`, `windowCommand`, `windowLayout`, `windowRoom`,
`quicklink`, `appleShortcut`, `extensionCommand`, `meeting`.

**Applications** are found by directory enumeration (`SearchScopes.appBundles`,
`Tinycast/Features/Launcher/Model/SearchScopes.swift`), not by Spotlight or a file watcher. A rescan
runs at start, on every launcher-mode palette show, on a scope edit and after an uninstall. A newly
installed app therefore appears on the next palette open.

**File search** is Tinycast's own index (`Tinycast/Features/FileSearch`). A separate `FileIndexHelper`
process crawls with at most eight workers and writes a memory-mapped snapshot; FSEvents keeps it
current (`FileSystemWatcher`). It stores each entry's name, directory flag and modification time, and
does not store size (`FileIndexCrawler`). It needs Full Disk Access and deactivates without it
(`FileIndexer.activate`). The default scope is the home folder with 22 ignore patterns.

### 1.7 Ranking and presentation

| Concern | Where | Behaviour |
| --- | --- | --- |
| Match | `Tinycast/Features/Launcher/Model/LauncherMatch.swift` (`SearchSensitivity`) | Alignment scorer with word-start and camel-hump points; three sensitivity levels |
| Order | `Tinycast/Features/Launcher/Model/LauncherOrder.swift` (`LauncherOrder.compare`) | Exact alias first, then boosted terms, then match quality with usage, then kind priority and name |
| Usage | `Tinycast/Features/Launcher/Model/LauncherRankingStore.swift` | +100 per visit, 10-day half-life, up to three remembered search terms for 17 days, saved to `launcher-ranking.json` |
| Aliases | `Tinycast/Features/Launcher/Service/AliasStore.swift` | Any entry can carry one; a file row cannot |
| Favorites | `Tinycast/Features/Launcher/Service/FavoritesStore.swift` | Apps and files, with Cmd-1 to Cmd-0 slots |
| Hidden items | `Tinycast/Features/Launcher/Service/VisibilityStore.swift` | Per kind and per item |
| Suggestions | `Tinycast/Features/Launcher/Model/LauncherSuggestions.swift` (`LauncherSuggestions.select`) | Shown while the field is empty. At most five; up to two are apps or extension commands added in the last five minutes |

File rows are ordered by `FileSearchQuery.score` (name match plus a prior), never by launcher usage.
Sections are drawn by `LauncherList` (`Tinycast/Features/Launcher/UI/LauncherList.swift`), which
hard-codes the section order as an array of kinds. Secondary actions are `PopoverMenuItem` values with
an action closure (`Tinycast/DesignSystem/PopoverMenu.swift`), built per row type.

### 1.8 Dispatch

Dispatch is by switch, not by a closure or protocol on the row.

- `LauncherScreen.activate(at:)` switches over `Row` and calls a coordinator function per case.
- `LauncherCoordinator.launch` (`Tinycast/Features/Launcher/UI/LauncherCoordinator.swift`) records a
  visit, then routes by `AppEntry.Kind` through an if-chain and a final exhaustive switch.
- `LauncherCoordinator.runCommand` is an exhaustive switch over `CommandID`
  (`Tinycast/Features/Launcher/Model/CommandID.swift`), a closed enum of 46 built-in commands. Global
  command hotkeys use the same function.
- `HotKeyManager.perform` switches over `HotKeyAction`
  (`Tinycast/Features/HotKeys/Model/HotKeyAction.swift`), a closed enum that names an entry by
  identifier. Deep links reuse it: `DeepLink.entry(HotKeyAction, DeepLinkInput)`
  (`Tinycast/Features/DeepLinks/Model/DeepLink.swift`).
- `FallbackCoordinator.run` (`Tinycast/Features/Launcher/UI/FallbackCoordinator.swift`) switches over
  `Fallback`: four built-ins (`quickAI`, `searchFiles`, `runShellCommand`, `define`) or a quicklink.

### 1.9 Keyboard handling

Layers, in the order they see a key:

1. `PalettePanel.sendEvent`: Emacs-style arrows, a key freeze while a menu is open, Escape in native
   editors, bare Backspace, arrows at the field's edge, and Cmd chords.
2. SwiftUI `onKeyPress` handlers in `RootPaletteView.keyHandlers`, which ignore keys while an input
   method is composing.
3. A session event tap for Cmd-Escape (`Tinycast/Palette/CommandEscapeTap.swift`), active only while
   the panel is key, and a local monitor for Cmd-V.

Escape is resolved by `PaletteEscapeAction.resolve` (`Tinycast/Palette/PaletteEscapeAction.swift`) in a
fixed order. Tab is resolved by `PaletteTabAction.resolve` (`Tinycast/Palette/PaletteTabAction.swift`);
from the launcher with AI enabled it sends the typed text to Quick AI. Return activates the selected
row; Cmd-Return, Ctrl-Cmd-Return and Option-Return are secondary actions. Cmd-K opens the action menu.

### 1.10 Persistence and settings

- **Preferences** live in `UserDefaults`, keyed by the 119-case `AppSettingsKey`. Most are `didSet`
  properties on `AppSettings` (`Tinycast/Features/Settings/AppSettings.swift`); AI, MCP and Quick
  Actions keep theirs in their own settings stores.
- **Files** are rooted by `AppPaths` (`Tinycast/Platform/AppPaths.swift`) under
  `~/Library/Application Support/<bundle id>/` and `~/Library/Caches/<bundle id>/`. Chats and
  quicklinks use SQLite; ranking, presets and custom Quick Actions use JSON.
- **Secrets** are Keychain generic passwords (`Tinycast/Platform/KeychainSecretStore.swift`).
- **`settings.json`** is an opt-in mirror keyed by `SettingsFileKey`
  (`Tinycast/Features/Settings/Model/SettingsFileKey.swift`).

Everything persisted is keyed by the bundle identifier, so a build with a different identifier starts
with empty preferences, data and Keychain items.

A new preference must be added in each of these places:

| Place | Enforced by |
| --- | --- |
| A property on `AppSettings` or on the feature's own settings store, and an `AppSettingsKey` case | Compilation |
| `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift`: mirrored or deliberately excluded | `Tests/SettingsBackupTests.swift` |
| `Tinycast/Features/Backup/Model/SettingsBackup.swift`: a field, an export line and an import block, when the preference is backed up | Nothing |
| `SettingsFileKey` case and its binding in `Tinycast/Features/Settings/SettingsFileSchema.swift` | An exhaustive switch with no default |
| Strings in `Tinycast/Resources/Localizable.xcstrings`, translated into eight languages | `Scripts/check-localizations.js`, run by `Scripts/lint.sh` |
| A Settings search entry, when the pane has one | `Scripts/check-settings-search.js` |

### 1.11 Permissions and network

- The app is not sandboxed (`Tinycast/Tinycast.entitlements`). Entitlements cover JIT (for
  JavaScriptCore), Apple events, camera, audio input and calendars. The hardened runtime is on in
  Release only (`project.yml`).
- Accessibility is the main privacy permission; `Permissions.ensureAccessibility`
  (`Tinycast/Platform/Permissions.swift`) is called from 22 sites. File Search and parts of
  Uninstall need Full Disk Access, which is probed and never requested.
- `Tinycast/Info.plist` sets `LSUIElement`, six usage strings, the URL schemes `raycast`, `com.raycast`
  and the channel scheme (`tinycast`, or `tinycast-dev` in Debug), and `TinycastUpdatePublicKey`.

Outbound hosts in the Swift sources:

| Host | Used by | Purpose |
| --- | --- | --- |
| `tinycast.dev` | `Tinycast/Features/Calculator/Service/CurrencyRateStore.swift` | Currency rates from upstream's own service |
| `api.github.com` | `Tinycast/Features/Updates/Service/UpdateCheckStore.swift`, `Tinycast/Features/Extensions/Service/ExtensionStoreClient.swift` | Update check against upstream's releases; extension source installs |
| `www.raycast.com` | `Tinycast/Features/Extensions/Model/ExtensionStoreResponse.swift` | Extension store search and download (the code calls this API unofficial) |
| `raw.githubusercontent.com` | `Tinycast/Features/Extensions/Model/ExtensionGitHubSource.swift` | Extension source files |
| `huggingface.co` | `Tinycast/Features/Dictation/Service/DictationModelDownloader.swift` | Dictation model downloads |
| `api.openai.com`, `api.anthropic.com`, `openrouter.ai`, `generativelanguage.googleapis.com` | `Tinycast/Features/AI/Model/AIConnection.swift` | AI providers, only when the user adds a connection |

The documented rule for a networked feature is a private ephemeral `URLSession` with no cache;
`CurrencyRateStore` is the reference and serves its cached file when offline.

### 1.12 Tests, build and performance

- **Tests.** Each harness is one `Tests/<Name>.swift` file with its own `@main`, compiled by `swiftc`
  together with the shipped sources named on its line in `Scripts/run-tests.sh` (121 entries, of
  which the suite runs 114). There is no XCTest target.
- **No CI runs tests or lint.** The six GitHub workflows are release, website, mirror, triage,
  issue-link and co-author checks. The definition of done is five local checks
  (`docs/testing.md`, DOC-ONLY).
- **Seam files.** This document uses that name for the nine files through which a feature is wired
  into the shell: `AppCore.swift`, `RootPaletteView.swift`, `PaletteWindowController.swift`,
  `PaletteMode.swift`, `LauncherScreen.swift`, `LauncherCoordinator.swift`, `AppIndex.swift`,
  `CommandID.swift` and `AppSettings.swift`.
- **Six of the nine seam files have no harness.** No line in `Scripts/run-tests.sh` compiles
  `AppCore.swift`, `RootPaletteView.swift`, `PaletteWindowController.swift`, `LauncherScreen.swift`,
  `LauncherCoordinator.swift` or `AppSettings.swift`. `PaletteMode.swift`, `AppIndex.swift` and
  `CommandID.swift` are compiled by harnesses, as are the pure model files beneath the seams
  (matching, ordering, ranking, fallbacks, escape and tab resolution).
- **Build.** XcodeGen generates `Tinycast.xcodeproj` from `project.yml`. Deployment target macOS 26.0,
  Swift 6.0, complete strict concurrency, manual signing with the identity "Tinycast Self-Signed".
  The docs require Xcode 27, XcodeGen, SwiftLint and Node (`docs/development.md`); `CONTRIBUTING.md`
  says Xcode 26.
- **Channels.** Release builds use `com.tinycast.app`, Debug builds `com.tinycast.app.dev` with the
  name "Tinycast Dev", and the beta identifier is assigned only by the release workflow.
- **Performance.** Eight signpost intervals are emitted through `Signposts.interval`
  (`Tinycast/Platform/Signposts.swift`), including `AppCore.start`, `PaletteWindowController.show`,
  `AppIndex.scan` and `AppIndex.rank`. The one
  numeric budget in the docs is resident memory under 100 MB (`docs/standards.md`, DOC-ONLY). The docs
  say launch time has never been captured as a number.

## 2. Features A to F: what exists and what is missing

| Feature | State today | Delta |
| --- | --- | --- |
| A. App and file search | Largely exists | Small addition |
| B. Inline web search | Missing | New subsystem |
| C. Inline AI answers | Exists on its own screen of the panel, not in the result list | None for that reading; significant refactor to put answers in the list |
| D. Natural-language app install | Missing; building blocks only | New subsystem |
| E. Context actions | Selected text only | Significant refactor |
| F. Natural-language OS actions | 32 fixed actions with no typed parameters or results | New subsystem |

### A. App and file search

| Clause | State | Where |
| --- | --- | --- |
| Fuzzy matching of apps and commands | Exists | `Tinycast/Features/Launcher/Model/LauncherMatch.swift` |
| Usage ranking of apps and commands | Exists | `Tinycast/Features/Launcher/Model/LauncherRankingStore.swift`; the visit is recorded in `LauncherCoordinator.launch` |
| Aliases | Exists for entries, missing for files | `Tinycast/Features/Launcher/Service/AliasStore.swift` |
| Files in the main list | Partial: at most five rows, ordered by the index's own score | `Tinycast/Features/FileSearch/Model/FileSearchQuery.swift` (`launcherResults`) |
| Usage ranking of files | Missing: opening a file records no visit | `Tinycast/Features/FileSearch/UI/FileSearchCoordinator.swift` (`open`) |
| Previews | Partial: Quick Look, PDF, media and text previews exist, only on the separate Search Files screen | `Tinycast/Features/FileSearch/UI/FileSearchPreview.swift` |
| Low CPU and memory | Not measured. The crawl runs in a helper process, apps are rescanned on each palette open, and the docs set a 100 MB budget. | Appendix B |

**Missing:** usage ranking and aliases for files, and a preview in the main list. File search also
needs Full Disk Access on each Mac.

### B. Inline web search

| Clause | State | Where |
| --- | --- | --- |
| Results from a search API | Missing. No search engine URL or search client exists in the app. | Search of `Tinycast/` |
| Rows with title, snippet, source and link | Missing | `LauncherScreen.Row` has no such case |
| Keyboard navigation | Exists for any row a screen lists | `Tinycast/Palette/PaletteScreen.swift` |
| Offline handling | A pattern only. No reachability code exists in the app. | `Tinycast/Features/Calculator/Service/CurrencyRateStore.swift` |
| No scraping | Holds; nothing scrapes | |

What exists nearby does not meet the feature. A typed address offers Open in Browser, and a quicklink
with a placeholder can be a fallback that opens the browser (none ship). AI web search returns prose
with links on the AI screen and needs a cloud key or the Codex CLI.

Free tiers checked on 2026-11-12: Tavily gives 1,000 credits a month with no card; Serper 2,500
queries once; Exa 10 dollars of credit a month; Brave asks for a card; Google's Programmable Search is
closed to new customers; Bing's API is retired. Each provider's terms on storing and displaying
results were not read (UNVERIFIED).

### C. Inline AI answers

| Clause | State | Where |
| --- | --- | --- |
| Streamed | Exists | `AIProvider.stream` |
| In the panel | Exists as the `ai` screen of the same panel, reached by Tab or a fallback row | `Tinycast/Features/AI/UI/AIScreen.swift` |
| In the result list | Missing | `LauncherScreen.Row` has no AI case |
| Follow-ups in place | Exists | `AIScreen.activate(at:)` |
| Apple on-device, Anthropic, OpenAI | Exists, plus the keyless CLI routes | `Tinycast/Features/AI/Service/AIProviderFactory.swift` |
| Cancellable | Partial: Return, Cmd-period and Stop Response cancel; Escape does not | `Tinycast/Palette/PaletteEscapeAction.swift` |
| Keys in Keychain | Exists | `Tinycast/Platform/KeychainSecretStore.swift` |
| Deterministic first, AI only when needed | Partial: calculator and colour cards lead, and AI is always the user's choice. Nothing routes a query. | `LauncherScreen.init` |

**The delta depends on what "inline" must mean.** An answer on the same panel after Tab exists today.
An answer drawn as a row of the result list does not; it needs a new row kind and chat state the
launcher can show.

### D. Natural-language app install

| Step | State | Where |
| --- | --- | --- |
| "Install Blender" recognised in the main query | Missing. A query reaches only the trailing fallback rows. | `Tinycast/Features/Launcher/Model/Fallback.swift` |
| Resolve the real package | Missing. Nothing calls Homebrew or its API. | Search of `Tinycast/` |
| Already installed? | Partial: answered by bundle identifier only | `AppIndex.isUninstalled(bundleID:)` |
| Show source and method | Missing | |
| Approve | Partial: a generic dialog exists | `AppCore.confirm` |
| Install with progress | Partial: streamed shell output exists, but its input is closed, so a password prompt cannot be answered | `Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift` (`stream`), `Tinycast/Platform/PseudoTerminal.swift` |
| Verify | Partial: a Developer ID check for any bundle exists, used only for Tinycast's own updates | `Tinycast/Features/Updates/Service/BundleSignature.swift` (`trustedHash`) |
| Immediately searchable | Partial: the app appears on the next palette open; nothing rescans when an install ends | `Tinycast/Palette/PaletteCoordinator.swift` |
| Detect Homebrew and guide its setup | Missing. Homebrew appears only as search-path entries. | `Tinycast/Platform/ExecutableLocator.swift` |
| No AI-written scripts, no unattended installers | Holds by absence; nothing enforces it | |

Three outside facts shape the gap (Homebrew documentation and API, checked 2026-11-12):

- A cask record carries token, names, description, homepage, URL, checksum, version and artifacts,
  but no bundle identifier. The existing installed-check cannot be used on it directly.
- Homebrew on Apple silicon needs no Command Line Tools for casks, but installing Homebrew itself
  needs administrator rights, and casks that run a package installer may ask for a password.
- Homebrew quarantines cask downloads, and its official casks must pass Gatekeeper.

Without Homebrew there is less still: the app has no code that mounts a disk image, runs a package
installer or requests administrator rights. The update pipeline in `Tinycast/Features/Updates` only
handles a zip holding one app.

### E. Context actions

| Clause | State | Where |
| --- | --- | --- |
| Selected text | Exists, up to 32,768 bytes | `QuickActionRunner.selection` |
| Selected files | Missing natively. The only reader of Finder's selection is private to the extension bridge. | `Tinycast/Features/Extensions/Service/ExtensionHostBridge.swift` (`finderSelection`) |
| Images | Partial: chat accepts a pasted, dropped or picked image; no action runs on a selected one | `Tinycast/Features/AI/UI/AIChatCoordinator.swift` |
| Clipboard | Partial: history holds text, image and file items; its one transform is text recognition on images | `Tinycast/Features/Clipboard/UI/ClipboardScreen.swift` (`ClipboardActionsMenu`) |
| "Explain this" | Partial: a custom Quick Action prompt does it, for text | `Tinycast/Features/QuickActions/Model/QuickAction.swift` |
| "Convert to WebP", "format this JSON" | Missing. Every image encoder writes PNG and nothing formats JSON for the user. | Search of `Tinycast/` |
| Originals preserved by default | Partial: custom actions preview first; Fix Grammar replaces directly | `Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift` |
| Confirm before anything destructive | Partial: the dialog exists; replacing a selection does not ask | `AppCore.confirm` |

**Missing:** file, image and clipboard inputs, any non-AI transform, and output as a new file. The
Quick Action pipeline is typed text in, text out.

### F. Natural-language OS actions

| Clause | State | Where |
| --- | --- | --- |
| A typed, restricted action set | Partial: 32 fixed actions (lock, sleep, volume, trash and similar) | `Tinycast/Features/SystemActions/Model/SystemAction.swift` (`SystemAction.ID`) |
| Processes, ports, disk usage | Missing. The file index does not store size. | Search of `Tinycast/` |
| Parameters and typed results | Missing: every action but Set Volume takes no parameter, and none returns more than a feedback title | `Tinycast/Features/SystemActions/Service/SystemActionRunner.swift` |
| Natural language to a structured operation | Plumbing only: tool calls with schema parameters exist, built only from MCP servers; no structured output; the on-device route has no tools | Section 3.9 |
| Never raw shell | No built-in path has a model produce a command. With a user-added MCP server that offers a shell tool, a model's command can run after one per-server approval that does not show the command (#1543). The typed-text shell fallback is a separate case (risk R2). | Section 3.9 |
| Approval | Partial: per MCP server, or per fixed action | `MCPTrustPolicy`, `SystemAction.Confirmation` |

**Missing:** every layer between the question and the execution.

## 3. The existing AI layer

### 3.1 Shape

`AIProvider` (`Tinycast/Features/AI/Service/AIProvider.swift`) is a protocol with one requirement,
`stream(_:)`, returning `AsyncThrowingStream<AIStreamEvent, Error>`. `AIRequest`
(`Tinycast/Features/AI/Model/AIRequest.swift`) carries instructions, messages, a token cap, a web
search flag and a tools array. It has no response-format or schema field.

`AIModelSelection` (`Tinycast/Features/AI/Model/AIConnection.swift`) is a closed seven-case enum that
names the route: `appleIntelligence`, `codex`, `claude`, `grok`, `openCode`, `cursor`, or
`api(connection:model:effort:)`. `AIProviderFactory.make`
(`Tinycast/Features/AI/Service/AIProviderFactory.swift`) turns a selection into a provider.

### 3.2 Providers

| Route | Implementation | Wire format |
| --- | --- | --- |
| OpenAI at `api.openai.com` | `Tinycast/Features/AI/Service/HTTPAIProvider.swift` | Responses API |
| OpenAI elsewhere, Gemini, OpenRouter, any compatible endpoint (including a local server on loopback) | `HTTPAIProvider` | Chat Completions |
| Anthropic | `HTTPAIProvider` | Messages API |
| Apple on-device | `Tinycast/Features/AI/Service/AppleIntelligenceProvider.swift` | FoundationModels framework |
| Codex | `Tinycast/Features/AI/Service/CodexAppServerClient.swift`, `CodexTurnRunner.swift` | A long-lived `codex app-server` child over JSON-RPC |
| Claude, Grok, OpenCode, Cursor | `Tinycast/Features/AI/Service/InstalledCLIProvider.swift` | One CLI process per turn, newline-delimited JSON |

Request bodies are built by `AIRequestBody` and streams decoded by `AIStreamDecoder` and
`AIResponsesDecoder` (all under `Tinycast/Features/AI/Model`). Endpoints must be `https`, or `http`
on loopback only (`AIEndpointPolicy.validate`).

### 3.3 What "installed AI account" means

Tinycast runs the vendor's own command-line tool as a subprocess, and that tool uses its own stored
sign-in. Tinycast reads no credential file. The executable is found by asking the login shell, with
fallbacks to Homebrew and other well-known paths (`Tinycast/Platform/ExecutableLocator.swift`).

For Claude with no MCP server attached, `InstalledCLITurnRunner.arguments` runs `claude -p` with
stream-JSON input and output, an empty tool list, all tools disallowed, one turn, and session
persistence off. In that form the route is a text transport, not an agent. With MCP servers attached,
the Claude and Codex CLIs become the MCP client and run their own tool loop
(`AIModelSelection.runsItsOwnTools`), limited to those servers. Codex runs in a read-only sandbox with
network access off (`CodexTurnRunner.prepareThread`). Grok and Cursor never get tools.

Two consequences for this project:

- The code supports cloud AI through an installed, signed-in `claude` CLI with no API key. Whether
  the installed version accepts the flags Tinycast passes is UNVERIFIED (Appendix B, row 13).
- The Claude permission channel uses an undocumented control format kept in
  `Tinycast/Features/AI/Model/ClaudeControlProtocol.swift`. `docs/features/mcp.md` warns that a CLI
  release may change it (DOC-ONLY). This route depends on upstream, or the fork, keeping pace with CLI
  releases.

### 3.4 Apple on-device

`AppleIntelligenceProvider` uses `SystemLanguageModel`, `LanguageModelSession(model:transcript:)` and
`streamResponse(to:options:)`. It handles four availability states (available, device not eligible,
Apple Intelligence not enabled, model not ready). It sends text and instructions only: the transcript
is built with `toolDefinitions: []`, tool and system messages are skipped, and images are never read.
The 6,000 context budget, counted in bytes of history, and the 1,024-token output cap are Tinycast
constants (`Tinycast/Features/AI/Model/AppleIntelligence.swift`), not Apple limits.

The SDK allows more than Tinycast uses. The FoundationModels interface in the installed macOS 26.2 SDK
declares a `Tool` protocol, a `LanguageModelSession` initializer that takes tools, the `Generable`
protocol, `GenerationSchema`, and `streamResponse` with a `generating` parameter. Only two files
import FoundationModels and neither uses any of these. Apple's documentation gives a 4,096-token
context window on macOS 26 and up to 8K on macOS 27, and advises offering three to five tools at most
(developer.apple.com, checked 2026-11-12). Whether tool calling works acceptably on a given Mac needs
a run (Appendix B).

### 3.5 Keys

API keys are Keychain generic passwords. The service name is the bundle identifier plus a scope, and
there are four scopes: `ai-api-keys`, `ai-request-headers`, `mcp-secrets` and
`installed-ai-environment` (`KeychainSecretStore`). No accessibility class, access group or
synchronization attribute is set. Keys are not part of settings backups or `settings.json`.

### 3.6 Streaming and cancellation

Every provider streams from a task and cancels it in `continuation.onTermination`. HTTP streams are
parsed as server-sent events. `AIChatState` (`Tinycast/Features/AI/UI/AIChatState.swift`) applies an
event only while its `replyGeneration` counter is unchanged, and `cancel()` bumps the counter, so late
events from a cancelled reply are dropped. CLI turns are also terminated as processes.

### 3.7 How the palette invokes it

There are six ways in, all ending in `AIChatState`:

- The Quick AI command row and its hotkey: `LauncherCoordinator.runCommand(.quickAI)` calls
  `QuickAICoordinator.show()` (`Tinycast/Features/AI/UI/QuickAICoordinator.swift`), which opens the
  screen and sends nothing.
- Tab from the launcher, and the Quick AI fallback row: both call `QuickAICoordinator.ask(_:)` with
  the typed text, which starts a new chat and sends it.
- A deep link, which seeds the text without sending.
- Pasting files at the launcher or on the AI screen, which stages them as attachments.

The answer appears on the `ai` screen of the same panel (`Tinycast/Features/AI/UI/AIScreen.swift`):
the search field becomes the composer and the body is the transcript. No AI answer is ever a row in
the root result list. Follow-ups are ordinary sends into the same `ChatSession`; regenerate, a model
picker, presets and a SQLite history exist. A separate AI Chat window shares the same state.

Escape does not cancel a streaming reply; it clears the query, goes back or hides the panel, and the
reply keeps streaming. Return on the AI screen, Cmd-period or the Stop Response row cancels.

### 3.8 How Quick Actions invoke it

`Tinycast/Features/QuickActions` has four built-ins (Fix Grammar, Rewrite, Translate, Summarize) and
custom prompts. Translate uses Apple's Translation framework, not a model.

- **Input** is selected text only, capped at 32,768 bytes. It is read through Accessibility, then
  through a borrowed Cmd-C (`QuickActionRunner.selection`,
  `Tinycast/Features/QuickActions/Service/QuickActionRunner.swift`).
- **Request** is one user message, with no images, documents or tools
  (`AppCore.quickActionProvider(for:)`).
- **Route** is a per-action override, else the Quick Action default, else chat's default.
- **Result** replaces the selection through `TextInjector`
  (`Tinycast/Features/TextInjection/Service/TextInjector.swift`) or shows in a separate floating
  panel with Copy and Replace. There is no follow-up and no hand-off into chat.

### 3.9 Tool and function calling

The provider layer models tools: `AITool` and `AIToolCall`
(`Tinycast/Features/AI/Model/AITool.swift`), tool events in `AIStreamEvent`, and an agent loop in
`AIToolLoopProvider` (`Tinycast/Features/AI/Service/AIToolLoopProvider.swift`) with caps on rounds,
result size and history.

The limits that matter here:

- **MCP is the only tool source.** In production code an `AITool` is built only by `MCPTool.aiTool`
  (`Tinycast/Features/MCP/Model/MCPTool.swift`). Chat gets tools from `MCPCoordinator`
  (`Tinycast/Features/MCP/UI/MCPCoordinator.swift`): `tools(scopedTo:)` for API routes and OpenCode,
  and `toolServers(scopedTo:)` for Claude and Codex. Both return nothing unless AI and MCP are both
  enabled. As the code stands, a tool cannot exist without an MCP server.
- **The loop itself is not tied to MCP.** `AIToolLoopProvider` takes a list of tools and an invoke
  closure.
- **Which routes get tools.** API connections, Claude, Codex and some OpenCode models. The Apple,
  Grok and Cursor routes do not. Quick Actions never do.
- **Approval is per server.** `MCPTrustPolicy.decide` (`Tinycast/Features/MCP/Model/MCPTrustPolicy.swift`)
  resolves ask, always or never per MCP server, with an "allow this chat" grant held in memory. The
  dialog names the server and the tool but does not show the call's arguments.
- **No structured output.** A search of the app for `response_format`, `json_schema`, `Generable`,
  `GenerationSchema` and `outputSchema` finds nothing.

MCP itself supports HTTP and stdio transports, OAuth for HTTP servers, and per-chat scoping. Tinycast
declines every request a server sends back to the client.

### 3.10 Web search and attachments

Web search is provider-hosted only: OpenAI on the Responses API, Anthropic at `api.anthropic.com`,
OpenRouter, and Codex. It was added for OpenAI and Anthropic on the audited commit's day (#1883). The
setting `aiWebSearch` is off by default. The stream carries the query and URL citations; a citation is
rendered as a host-labelled link and no result title or snippet is kept (`AICitationLinker` in
`Tinycast/Features/AI/Model/AIStreamDecoder.swift`). On Anthropic and OpenAI each search costs about
one cent on top of tokens (vendor pricing pages, checked 2026-11-12).

Chat accepts images, PDFs and text files, chosen by an extension allowlist
(`Tinycast/Features/AI/Model/AIAttachmentPolicy.swift`), up to 6 files and 10 MiB (`AIAttachmentBudget`
in `Tinycast/Features/AI/Model/AIRequest.swift`). The AI feature never reads the selection, the
clipboard history or the frontmost app as context.

## 4. The Raycast extension runtime

### 4.1 How it runs

Each command runs in a JavaScriptCore `JSContext` on a private serial queue
(`Tinycast/Features/Extensions/Service/ExtensionRuntime.swift`). The context is discarded when the
command stops. The JavaScript side (`Scripts/raycast-runtime/src`, committed as the 269 KB bundle
`Tinycast/Resources/RaycastRuntime.generated.js`) carries React 19 and a custom reconciler that
commits a JSON tree. Swift decodes the tree into `RenderNode` values and draws List, Grid, Detail and
Form roots as palette screens (`Tinycast/Features/Extensions/UI/ExtensionScreen.swift`); any other
root is unsupported. `MenuBarExtra` is drawn as a native status item.

### 4.2 Supported API

`Scripts/raycast-runtime/src/api/index.js` assembles the `@raycast/api` module: `List`, `Grid`,
`Detail`, `Form`, `ActionPanel`, `Action`, `MenuBarExtra`, `showToast`, `showHUD`, `confirmAlert`,
`Clipboard`, `LocalStorage`, `Cache`, `getPreferenceValues`, `open`, `closeMainWindow`, `popToRoot`,
`getApplications`, `getFrontmostApplication`, `getSelectedText`, `getSelectedFinderItems`,
`launchCommand`, `OAuth`, `environment`, `useNavigation` and about 30 deprecated aliases.
`@raycast/utils` is not provided; an extension must bundle it.

Exported but rejecting as unsupported:

- The whole `AI` namespace (`ask`, `experimental_decide`, `refreshModels`).
- `BrowserExtension` and `WindowManagement`.
- `Action.CreateSnippet`, `Action.CreateQuicklink`, `Action.ToggleQuickLook`,
  `Action.InstallMCPServer`, and `getFrontmostBrowserTab`.

### 4.3 Install and storage

| Route | Needs Node on the Mac | Mechanism |
| --- | --- | --- |
| Raycast Store | No | Downloads the store's prebuilt zip and unpacks it with `ditto` (`Tinycast/Features/Extensions/Service/ExtensionInstaller.swift`) |
| GitHub source | Yes, plus a package manager | Installs dependencies with lifecycle scripts skipped, then runs the extension's build |
| Import from Raycast | No | Copies already-built bundles |
| Local folder | No | Any folder with a manifest and built files |

Installed extensions live under `~/Library/Application Support/<bundle id>/extensions/`. Only
store-installed extensions update, and the check runs when the Settings pane opens.

### 4.4 What an extension can and cannot do

| Capability | State | Where |
| --- | --- | --- |
| Network | `fetch` reads the whole response before replying. No streaming, and an abort is not honoured. | `Tinycast/Features/Extensions/Service/ExtensionFetcher.swift`, `Scripts/raycast-runtime/src/polyfills.js` |
| Shell | `child_process` runs real processes. `spawn` delivers output as it arrives, but input is collected before the process starts, so a prompt cannot be answered. The synchronous variants block the runtime. | `Tinycast/Features/Extensions/Service/ExtensionNodeShims.swift`, `Tinycast/Features/Extensions/Service/ExtensionFetcher.swift` (`ExtensionAsyncProcess`), `Scripts/raycast-runtime/src/node-shims.js` |
| Files | Unrestricted, no path allow-list | `ExtensionNodeShims` |
| Selected text, Finder selection, clipboard | Available; Finder selection goes through AppleScript | `Tinycast/Features/Extensions/Service/ExtensionHostBridge.swift` |
| Preferences, LocalStorage, Cache, OAuth tokens | One plaintext JSON file per extension, password preferences included. Nothing uses the Keychain. | `Tinycast/Features/Extensions/Service/ExtensionStorage.swift` |
| Tinycast's AI | Not reachable; the `AI` namespace throws | `Scripts/raycast-runtime/src/api/index.js` |
| Background work | Menu-bar and interval commands run with the palette closed | `Tinycast/Features/Extensions/Service/ExtensionManager.swift` |
| Rows in the main result list | Not possible (below) | `ExtensionManager` |

**Contributing to the main search list.** Each manifest command becomes one static `AppEntry` of kind
`extensionCommand`, published from manifest data by `ExtensionManager.publishLauncherEntries` through
`AppIndex.setExtensionCommands`. No path leads from the JavaScript side to `AppIndex`, so an extension
cannot add result rows for a typed query. Raycast's fallback commands are not implemented, and an
extension command cannot be a Tinycast fallback. A view command sees typed text only in its own search
bar, or as `fallbackText` in a deep link or `launchCommand`. Commands can take hotkeys and aliases.

**Trust model.** There is no sandbox. The only consent is one dialog when extensions are first
enabled (`ExtensionCoordinator.setExtensionsEnabled`,
`Tinycast/Features/Extensions/UI/ExtensionCoordinator.swift`). `docs/not-planned.md` states that an
extension can do anything the user can do.

### 4.5 Known gaps and status

- `docs/features/extensions.md` lists as unsupported: `AI`, `BrowserExtension`, `WindowManagement`,
  aborting a fetch, interactive `spawn` input, `net` and `tls`, streaming HTTP, and Raycast's tool
  entry points (DOC-ONLY for the last three).
- `docs/not-planned.md` says Raycast compatibility "has stopped" at about 80% and that the future is
  native Tinycast extensions, which do not exist yet. It also declines letting extensions use
  Tinycast's AI.
- Work has not in fact stopped: 23 commits touched the runtime or `Tinycast/Features/Extensions` in the
  last 30 days, several adding capability.
- The bundle includes React and react-reconciler with licence comments stripped
  (`Scripts/raycast-runtime/build.mjs`, `legalComments`), and `NOTICE.md` does not list them (section 8).

## 5. Where each feature fits best

Classification is by launcher experience, not by cost. "Stock" means unmodified Tinycast.

| Feature | Fits best | What already works on stock Tinycast |
| --- | --- | --- |
| A | FORK, small | Search as shipped, with File Search enabled |
| B | FORK | A quicklink fallback that opens a search engine in the browser |
| C | CONFIG/EXISTING for an answer on the same panel; FORK for anything more | Tab from the launcher, on the Claude CLI or the on-device route |
| D | FORK | The Raycast Store's Brew extension, or a custom command |
| E | FORK | A custom Quick Action for text; the Store's Image Modification extension |
| F | FORK | Custom commands; Store extensions for ports, processes and disk usage; an MCP server for the natural-language step |

No Store extension named in this section was run in Tinycast. Each fit is a reading of the extension's
source against the runtime's abilities, so every one is UNVERIFIED until run.

A fork entry below is a touch set: the existing files that could not stay unchanged, and the
constraint that forces each. It is not a design.

### A. App and file search

| Route | Gives | Lacks or costs |
| --- | --- | --- |
| CONFIG/EXISTING | Fuzzy, usage-ranked, aliased apps and commands; up to five file rows; favorite files; previews one step away in Search Files | File usage ranking, file aliases, a preview in the main list |
| EXTENSION | A file list with its own previews and usage counts, in the extension's own screen | No access to Tinycast's index, ranking or aliases. Files would sit in a second list with a second ranking. |
| FORK | The three gaps closed inside the one list | Small |

Touch set: `FileSearchQuery.launcherResults` (the only place launcher file rows are ordered and
capped); `FileSearchCoordinator` (`open` records no visit, and `launcherFiles` is the launcher's only
file source); `LauncherScreen.init`; `LauncherList`, where files always follow every entry section.
Reusable as they are: `LauncherRankingStore` and `AliasStore` are keyed by an opaque string, and
`FileSearchPreview` takes a file result.

### B. Inline web search

| Route | Gives | Lacks or costs |
| --- | --- | --- |
| CONFIG/EXISTING | A quicklink with a placeholder, enabled as a fallback, opens a search engine. AI web search gives a prose answer with links. | No results in the panel. The quicklink opens the browser, which the brief wants to avoid. AI web search needs a cloud key. |
| EXTENSION | A new view command could call a search API and list title, snippet and source in its own screen, keyboard-navigable, with a cache | Not in the main list and not a fallback. The API key would sit in a plaintext file, not the Keychain. No existing Store extension returns real results without a paid key. |
| FORK | Result rows in the main list, the key in the Keychain, a cached copy offline | New subsystem |

Touch set: `LauncherScreen.Row` and its exhaustive switches; `LauncherList`, which has its own closed
row type and a fixed section order; the query `onChange` block in `RootPaletteView`, one of three
places the launcher starts its asynchronous source; `AppCore.start`; the settings registries of
section 1.10;
`KeychainSecretStore`, whose scopes are fixed. Reusable as shapes: `CurrencyRateStore` for a networked
feature with an offline copy, and `FileSearchSession` for an asynchronous source read by the
synchronous row builder. `docs/not-planned.md` declines AI "smart" search on the ground that search
stays on-device; it does not address web results.

### C. Inline AI answers

| Route | Gives | Lacks or costs |
| --- | --- | --- |
| CONFIG/EXISTING | Streamed answers on the same panel after Tab, follow-ups, the on-device and Claude CLI routes with no key, Anthropic and OpenAI with keys in the Keychain, calculator answers first | Escape does not cancel. Nothing decides when AI is needed. The answer is not in the result list. |
| EXTENSION | Not viable | The runtime's `AI` namespace throws, `fetch` cannot stream, and the on-device model cannot be reached from JavaScript |
| FORK | Escape-to-cancel and a routing rule are small. An answer inside the result list is a significant refactor. | See the touch set |

Touch set for the small changes: `PaletteEscapeAction.resolve`, which `Tests/PaletteEscapeTests.swift`
pins, and its switch in `RootPaletteView`. For an answer in the list, add `LauncherScreen.Row`,
`LauncherList`, `QuickAICoordinator.ask` (it always switches the panel to the `ai` screen),
`AIChatSurfacesState` (a chat is live in one surface at a time) and `FallbackCoordinator.run`.
Reusable: `AIProviderFactory`, `AIChatCoordinator`'s send and stop, and the transcript view.

### D. Natural-language app install

| Route | Gives | Lacks or costs |
| --- | --- | --- |
| CONFIG/EXISTING | The Store's Brew extension searches casks and formulae, shows details and installs, in its own screen. A custom command `brew install --cask "$1"` with confirmation and output streams an install. | No "Install Blender" from the main query. The custom command needs the exact token and checks nothing, and its confirmation shows the template with `$1`, not the package. Neither handles a missing Homebrew. |
| EXTENSION | A new extension could resolve names from Homebrew's catalogue, check for the app, show source and method, confirm, run `brew` with streamed output and check again | It cannot add a row to the main list or be a fallback, so a typed request never reaches it. It cannot answer a password prompt, trigger a rescan, or use Tinycast's AI to resolve a name. |
| FORK | The whole flow in the main list, a native approval that shows source and method, a rescan when the install ends | New subsystem |

Touch set:

- For the entry point: `Fallback.Builtin` with `FallbackCoordinator.run` (exhaustive), or
  `LauncherScreen.Row` and `LauncherList` if candidates are rows.
- For a command: `CommandID` with `LauncherCoordinator.runCommand`,
  `DeepLinkConsentPolicy.requiresConsent` (`Tinycast/Features/DeepLinks/Model/DeepLinkConsentPolicy.swift`)
  and `SettingsTab.ownedCommands` (`Tinycast/Features/Launcher/Model/CommandCatalog.swift`).
- For a preview or progress screen: `PaletteMode` and `RootPaletteView.screen`.
- For any new state or preference: `AppCore.start` and the settings registries.

Reusable as they are: `ShellCommandRunner.stream` with `CommandOutputPresenter` (streamed output and
Stop); `ToolRunner` (`Tinycast/Features/Updates/Service/ToolRunner.swift`), which runs an executable
without a shell and with a timeout; `BundleSignature.trustedHash`; `AppCore.confirm`;
`AppIndex.refresh`; `ExecutableLocator`, which already searches Homebrew's prefixes; and
`CurrencyRateStore` as the shape for fetching and caching Homebrew's catalogue.

Three steps have no precedent anywhere in the repo: answering a password prompt, setting up Homebrew,
and installing an app without Homebrew.

### E. Context actions

| Route | Gives | Lacks or costs |
| --- | --- | --- |
| CONFIG/EXISTING | A custom Quick Action such as "Explain this" on selected text, with a preview. A shell custom command for one fixed transform. The Store's Image Modification extension converts to WebP with its own bundled encoder. | AI on text only. No single menu across text, files, images and clipboard. Image Modification replaces the original by default. |
| EXTENSION | One view command could read the selection, Finder's selection and the clipboard, offer transforms and write copies | No on-device model and no Tinycast AI. Its selected-text read has no copy fallback. It sits behind its own command. |
| FORK | One native surface across the sources, with preview and confirmation | Significant refactor |

Touch set: `QuickActionRunner`, typed text in and text out with a size cap; `QuickActionCoordinator`,
whose `Target` has two cases and whose delivery always replaces text; the closed `QuickAction` and
`BuiltInQuickAction` enums; the `CommandID` chain named under D; `ClipboardActionsMenu`, a hard-coded
action list; and `ExtensionHostBridge.finderSelection`. That last one is private to the extension
folder, and the rule that extension code stays there means the Finder read would exist a second time
outside it. Reusable: `AccessibilityText`, `TextInjector`, `QuickActionPanel`, `AIAttachmentPolicy`,
`ChatAttachmentReader` (`Tinycast/Features/AI/UI/ChatAttachmentReader.swift`) and `AppCore.confirm`.

Whether system frameworks can encode WebP is not established (Appendix B). If they cannot, WebP
output would need the app's first third-party code. Upstream declines sending a selection or file to
AI, showing Quick Action results in the palette, and acting on selected text or files from anywhere
(`docs/not-planned.md`).

### F. Natural-language OS actions

| Route | Gives | Lacks or costs |
| --- | --- | --- |
| CONFIG/EXISTING | Custom commands with arguments answer both example questions deterministically, with output shown. Store extensions exist for ports, processes and disk usage. An MCP server exposing fixed tools gives a natural-language route through chat. | Natural language needs a cloud or CLI route, because the on-device route has no tools. MCP approval is per server and does not show arguments, and answers return as prose. Custom commands are shell text, not a typed set. |
| EXTENSION | A view command could map a question to fixed operations by spawning the Claude CLI and show typed results | Depends on the CLI. No on-device model. Not reachable from the main query. |
| FORK | A typed, parameterized action set with per-operation confirmation, usable from the on-device model | New subsystem |

Touch set: `AppleIntelligenceProvider.stream`, which builds its session with no tools;
`AIProviderFactory`; `AIRequest` and `AIStreamEvent`, with no structured-output field and a closed
event enum; the `CommandID` chain; `PaletteMode` and `RootPaletteView.screen` if results get a screen;
`Fallback.Builtin` if it is offered as a fallback. Reusable: `AIToolLoopProvider`, `AITool`,
`SystemAction.Confirmation`, `AppCore.confirm`, and `UninstallScanner`
(`Tinycast/Features/Uninstall/Service/UninstallScanner.swift`), which already sums file sizes.

### What the classification adds up to

- All six features fit best in Tinycast's own code. For C, stock behaviour already covers the
  narrower reading.
- Four verified limits rule extensions out as the home of any feature: no rows in the main list, no
  access to Tinycast's AI, no streaming `fetch`, and secrets in plaintext. Existing Store extensions
  remain usable stopgaps for D, E and F.
- Every touch set crosses the same files: the seam files of section 1.12, `LauncherList`, the settings
  registries and the strings file.

## 6. Unification

### 6.1 What exists today

Six closed vocabularies, each with its own dispatch. Counts were recounted by an independent verifier.
An exhaustive switch has no `default`, so adding a case fails the build until that switch names it. A
switch with a `default` compiles unchanged and silently takes the default.

| Type | Cases | Says | Switch sites |
| --- | ---: | --- | --- |
| `LauncherScreen.Row` | 6 | What a row of the main list is | 5 exhaustive, all in `LauncherScreen` |
| `AppEntry.Kind` | 14 | What an entry is | 7, of which 4 exhaustive, plus a hard-coded order in `LauncherList` |
| `CommandID` | 46 | Which built-in command | 4 exhaustive: `nameResource`, `sfSymbol`, `runCommand` and `DeepLinkConsentPolicy.requiresConsent` |
| `HotKeyAction` | 16 | Which entry to invoke, by identifier | 8 exhaustive |
| `Fallback` | 4 built-ins, or a quicklink | What to do with the typed query | 4 exhaustive: `Builtin.command`, `openVerb`, `FallbackCoordinator.run` and `isAvailable` |
| `PaletteMode` | 23 | Which screen | 8, of which 3 exhaustive |

Each feature executes through its own coordinator. There is no shared execution protocol: system
actions, custom commands, quicklinks, Quick Actions and AI each have a separate path, and secondary
actions are closures.

### 6.2 What is already shared

- **One funnel for rows and hotkeys.** A row and a global hotkey for the same command both end in
  `LauncherCoordinator.runCommand`.
- **A typed, serializable "invoke this entry with this input".** Deep links carry a `HotKeyAction`
  and a `DeepLinkInput`, and `DeepLinkConsentPolicy` classes which actions need consent. This is the
  closest thing to a typed action model. Its parameters are identifiers and one text input, and it
  returns nothing.
- **A precedent for an asynchronous source in the main list**: file rows, read from an observable
  session.
- **A precedent for deterministic-first routing**: one lead card, calculator before colour before
  meeting, chosen in `LauncherScreen.init`.
- **A precedent for typed confirmation**: `SystemAction.Confirmation`, and the plan, preview, confirm
  flow of `Tinycast/Features/Uninstall`.
- **One hand-off into AI**: Tab and the Quick AI fallback call the same `QuickAICoordinator.ask`.

### 6.3 What keeps them apart

1. Row sources are named in code. `LauncherScreen.init` lists them one by one, synchronously.
2. AI sits outside the entry model. An answer is state in `AIChatState` shown on another screen; a
   Quick Action result is shown in another window. Neither is a row or an entry kind.
3. Actions have no common shape. A system action takes no parameter (Set Volume aside) and returns a
   feedback title. A custom
   command takes up to three strings and returns a text stream. A quicklink expands a template. A
   Quick Action takes a selection and returns text.
4. The AI layer cannot emit a typed operation: no structured output, tools only from MCP servers, and
   none on the on-device route.
5. Extensions are walled off by a stated invariant (`AGENTS.md`: extension code stays inside
   `Tinycast/Features/Extensions`) and cannot add rows.

### 6.4 Can they share one query router and one typed action model?

Yes. Nothing in the code prevents it, and 6.2 lists the pieces it would grow from. It is a change to
the seams, not a configuration.

**What would have to change**

- To admit new row sources: `LauncherScreen.Row` and `LauncherScreen.init`, `LauncherList`, and the
  query `onChange` block in `RootPaletteView`.
- To give actions one typed shape with parameters and results: `HotKeyAction`, `AppEntry.Kind`,
  `CommandID`, `SystemAction` with its runner, and the custom-command and Quick Action coordinators.
- To let AI produce typed operations: `AIRequest`, the tool source and executor in `MCPCoordinator`,
  and `AppleIntelligenceProvider`.
- To place AI answers in the list: `AIChatSurfacesState`, `PaletteTabAction` and `PaletteEscapeAction`.

**What would break or need rework**

- **Harnesses pinned to current behaviour**: `Tests/PaletteTabTests.swift`,
  `Tests/PaletteEscapeTests.swift`, `Tests/FallbackTests.swift`, `Tests/DeepLinkTests.swift`,
  `Tests/HotKeyDispatchTests.swift` and `Tests/AppInstallationTests.swift`, which compiles
  `AppIndex.swift` against hand-written stubs of its dependencies.
- **Documented invariants**: `AppEntry.Kind` is the only thing that says what an entry is; a file row
  is not an entry; a chat is live in one surface at a time; model folders stay free of AppKit and
  SwiftUI.
- **Stored identifiers.** `CommandID` raw values and `HotKeyAction.defaultsKey` are persisted keys for
  hotkeys, hidden items, aliases and ranking. Renaming them orphans user data.
- **Consent gates tied to the current split**: deep-link consent, per-command confirmation and MCP
  trust each guard one path. Two of them already have a path around them (risks R2 and R3).
- **Alignment with upstream.** The change lands in the seam files, which upstream edits most (section
  7.2) and six of which no harness compiles.

**Size.** Admitting new row sources beside the existing ones has a measured precedent: upstream's
Files section added 58 lines across five seam files, and 27 more in `LauncherList.swift`. Replacing
the six vocabularies with one touches
every exhaustive switch in the table above. The typed AI operation path does not exist at all today.

## 7. Upstream maintenance

All figures come from read-only `git log` and `git blame` on the audited commit, plus GitHub's public
API for the community fork. No merge was attempted, so the conflict burden is inferred, not observed.
Time windows count back from the hour of measurement on 2026-11-12, so a recount at another hour can
differ by one or two commits.

### 7.1 Pace

- 940 commits since the first on 2026-06-28. 591 in the last 90 days, 409 in the last 60, 122 in the
  last 30.
- The pace is falling: weekly commits peaked at 93 in ISO week 38 and were 28, 18 and 38 in weeks 43
  to 45.
- One maintainer wrote 384 of the last 591 commits. The next three contributors wrote 46, 28 and 23.
- Pull requests are squash-merged, one commit each. The median commit changes 132 lines, the average
  830, and one in ten more than 1,565. Of the 590 that changed files, 50 touched more than 30.
- 135 tags, 27 of them stable releases. Betas land every one to three days. The latest stable is
  `v0.12.11` (2026-11-08); the audited commit is 9 commits later.
- Files move often: 130 renames or moves in the last 30 days, 373 in 180.
- Upstreaming is not a route for this project's features. A pull request needs a linked issue
  (enforced by `.github/workflows/issue-link.yml`) that is marked approved (`CONTRIBUTING.md`,
  DOC-ONLY). `docs/not-planned.md` declines AI smart search, AI command suggestions, sending a
  selection or file to AI, acting on selected text or files from anywhere, Quick Action results in
  the palette, and letting extensions use Tinycast's AI. Its closing list ends "Fork Tinycast and make
  it yours."

### 7.2 How often the files a fork would touch change

Commits touching each file in the last 30 and 90 days.

| Group | File | 30 d | 90 d |
| --- | --- | ---: | ---: |
| Seam files | `Tinycast/Palette/RootPaletteView.swift` (1,679 lines) | 19 | 98 |
| | `Tinycast/App/AppCore.swift` | 14 | 87 |
| | `Tinycast/Features/Settings/AppSettings.swift` | 14 | 62 |
| | `Tinycast/Palette/PaletteWindowController.swift` | 11 | 56 |
| | `Tinycast/Features/Launcher/Service/AppIndex.swift` | 5 | 45 |
| | `Tinycast/Features/Launcher/UI/LauncherCoordinator.swift` | 3 | 40 |
| | `Tinycast/Features/Launcher/UI/LauncherScreen.swift` | 8 | 34 |
| | `Tinycast/Features/Launcher/Model/CommandID.swift` | 6 | 33 |
| | `Tinycast/Palette/PaletteMode.swift` | 2 | 16 |
| Other busy file | `Tinycast/Features/AI/UI/AIChatCoordinator.swift` | 9 | 34 |
| Registries | `Tinycast/Features/Settings/SettingsSearchCatalog.swift` | 18 | 64 |
| | `Tinycast/Features/Backup/Model/SettingsBackupCoverage.swift` | 14 | 62 |
| | `Tinycast/Features/Settings/AppSettingsKey.swift` | 13 | 60 |
| | `Tinycast/Resources/Localizable.xcstrings` (143,804 lines; created 2026-10-17, so both windows show its whole history) | 28 | 28 |
| | `Scripts/run-tests.sh` | 28 | 137 |
| Generated | `Tinycast.xcodeproj/project.pbxproj` | 26 | 154 |
| | `Tinycast/Resources/RaycastRuntime.generated.js` | 7 | 51 |
| Quiet | `Tinycast/Features/AI/Service/HTTPAIProvider.swift` | 3 | 6 |
| | `Tinycast/Features/AI/Service/AIToolLoopProvider.swift` | 3 | 5 |
| | `Tinycast/Features/AI/Service/AppleIntelligenceProvider.swift` | 2 | 4 |
| | `Tinycast/Features/MCP/UI/MCPCoordinator.swift` | 1 | 5 |
| | `Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift` | 3 | 7 |
| | `Tinycast/Features/SystemActions/Model/SystemAction.swift` | 2 | 4 |
| | `Tinycast/Features/Launcher/UI/FallbackCoordinator.swift` | 1 | 4 |
| | `Tinycast/Features/Updates/Service/UpdateInstaller.swift` | 5 | 8 |

Commits touching the body of each seam function or type:

| Function or type | 30 d | 90 d |
| --- | ---: | ---: |
| `AppCore.start` | 8 | 43 |
| `CommandID` enum | 5 | 32 |
| `LauncherCoordinator.runCommand` | 2 | 25 |
| `RootPaletteView.screen` | 1 | 20 |
| `RootPaletteView.keyHandlers` | 8 | 19 |
| `LauncherCoordinator.launch` | 1 | 19 |
| `HotKeyManager.perform` | 1 | 17 |
| `LauncherScreen.init` | 3 | 16 |
| `PaletteMode` enum | 2 | 16 |
| `AIProviderFactory.make` | 5 | 14 |
| `AppEntry.Kind` enum | 0 | 12 |
| `PaletteScreen` protocol | 0 | 10 |
| `Fallback` enum | 2 | 5 |
| `AIStreamEvent` enum | 1 | 4 |
| `AppleIntelligenceProvider.stream` | 1 | 2 |

Of the commits in the last 90 days, 211 (36%) touched at least one of the nine seam files, and 107
touched two or more.

### 7.3 What kind of change upstream makes in the seams

To see whether upstream rewrites seam code or adds beside it, ten feature pull requests from
2026-09-16 to 2026-11-02 were traced with `git blame`: how many of the lines each added to the nine
seam files are still attributed to it today.

| Pull request | Seam files touched | Lines added | Still unchanged |
| --- | ---: | ---: | ---: |
| #756 Apple Shortcuts in the launcher | 4 | 56 | 50 |
| #848 Define Words | 5 | 22 | 21 |
| #903 Inline custom-command arguments | 5 | 40 | 28 |
| #1047 AI Chat window | 5 | 60 | 56 |
| #1057 Ranking rebuild and Suggestions | 5 | 199 | 158 |
| #1186 `settings.json` mirror | 2 | 100 | 93 |
| #1488 Launcher forms | 7 | 164 | 153 |
| #1608 Files section in the launcher | 5 | 58 | 53 |
| #1720 File and folder favorites | 1 | 73 | 73 |
| #1753 Deep links with input and consent | 6 | 92 | 92 |
| **Total** | | **864** | **777 (89%)** |

Two readings follow, and one limit:

- Upstream mostly inserts beside existing seam lines. The files had between 6 and 47 later commits
  each, yet nine lines in ten survived.
- A feature in upstream's own style wires into one to seven seam files with 22 to 199 lines.
- The measure covers upstream's code only. It says nothing about a fork that restructures the seam
  functions themselves, where every later upstream insertion would have to be re-expressed by hand.

### 7.4 Evidence from an existing fork

`docs/not-planned.md` names one community fork, `conversun/tinycast-cn`. GitHub's public API on
2026-11-12 shows it created 2026-07-31 and 9 commits behind upstream, with a merge base four days
old. It syncs through its own workflow, `.github/workflows/sync-upstream-release.yml`.

Its difference from upstream is about 70 files in the part of the comparison that was read (the last
7% of the response was not read). They are localization resources, the updater's identity files
(`ReleaseFeed.swift`, `ReleaseChannel.swift`, `BundleSignature.swift`, `UpdateInstaller.swift`),
release workflows and tests. In the seam files it changes 9 lines of `RootPaletteView.swift` and 4 of
`TinycastApp.swift`.

So a thin fork demonstrably keeps up. There is no evidence either way for a fork that changes the
launcher core.

### 7.5 Expected burden of a fork that keeps merging

- **Mechanical conflicts** in files both sides append to: the five settings registries (each changes
  12 to 18 times a month), `Localizable.xcstrings` (28 commits in 30 days), `Scripts/run-tests.sh`
  (28) and `project.pbxproj` (26, regenerable with XcodeGen).
- **Adjacent-insertion conflicts** in the seams, wherever the fork has added lines: `AppCore.start`
  sees 8 upstream commits a month, `RootPaletteView.keyHandlers` 8, the `CommandID` enum 5,
  `LauncherScreen.init` 3.
- **Drift in shared types** that fork code must follow: the `PaletteScreen` protocol changed in 10
  commits over 90 days, `PaletteMode` in 16, `AppEntry.Kind` in 12. All three were nearly still in the
  last 30 days.
- **Renames.** 130 in the last 30 days. Git follows a rename of a file the fork modified in most
  cases, but not when the file was also split.
- **Gates.** Merged code is expected to pass upstream's local definition of done, including
  translations in eight languages. Nothing enforces it, so a fork can relax a gate, and each
  relaxation is one more divergence.
- **Little safety net in the seams.** Six of the nine seam files have no harness (section 1.12), so a
  bad merge there shows up only when the app is built and used.

An hours-per-month figure is UNVERIFIED. It would take trial merges, which this task did not allow.

### 7.6 What a fork that stops syncing gives up

The last 60 days hold 409 upstream commits. A commit can count in more than one row.

| What the commit touches | Commits | Share |
| --- | ---: | ---: |
| AI, MCP or Quick Actions | 75 | 18% |
| App, Palette, Launcher or File Search | 143 | 35% |
| The extension runtime | 109 | 27% |
| Updates, the release workflow or signing docs | 19 | 5% |
| Only other features (window management, notes, calendar, clipboard, calculator and the rest) | 97 | 24% |
| No app, test or script file (website, docs, repo housekeeping) | 24 | 6% |

By the first word of the subject line, 99 of the 409 read as fixes, 214 as features and 96 as other
work. That split is a rough heuristic.

**Security and trust fixes.** A keyword search of all history finds 58 commits; on reading, 13 are
clearly security or trust changes. Eight of those fall in the last 60 days:

- #1808 update trust through a release key or the running identity, and #1803 Developer ID signing
  (both 2026-11-05).
- #1772 "lifecycle, data-safety and blocking bugs from the code audit" (2026-11-03).
- #1753 ask-once consent for deep links (2026-11-02).
- #1739 extension requests opted out of the macOS single sign-on broker (2026-11-01).
- #1718 Hyper Key recovery protected by instance ownership (2026-10-27).
- #1635 and #1624 safer uninstall (2026-10-17 and 18).

Several concern the updater and signing, which a renamed fork replaces in any case.

**macOS compatibility fixes.** 15 commits mention macOS 26, macOS 27 or Tahoe in their message, all
within the last 90 days and 11 within the last 60. Not every one is a compatibility fix; some only
name the system in passing. Clear examples: Show Desktop on macOS 27 (#1156), the compact bar's
shadow on macOS 26 (#1872), Liquid Glass panels (#1046). Separately, 6 commit messages in the last 60
days mention a crash and 6 a hang or freeze.

**Features this brief would want.** From the last 60 days:

- AI: web search on OpenAI and Anthropic (#1883), a fix for OpenAI MCP tool calling (#1773), OpenCode
  v2 with MCP (#1795), a reasoning-effort picker (#1830), chat presets (#1796), custom request headers
  (#1680), MCP tools that can run commands and read files (#1543).
- Launcher: the Files section (#1608), Tinycast's own disk index replacing Spotlight (#1537), file and
  folder favorites (#1720), the ranking rebuild with Suggestions (#1057), deep links with input
  (#1753).
- Upkeep of the installed-CLI routes: finding CLIs under a fish login shell (#1153), starting Codex
  when launched from Finder (#1134).

Three observations frame the loss:

- The largest stream is the launcher and palette itself: 143 commits in 60 days, in the code that
  feature A and every touch set of section 5 sit in.
- AI upkeep is 75 commits in 60 days. The keyless Claude route rests on undocumented CLI formats
  (section 3.3), so someone has to follow CLI releases.
- 24% of commits touch only other features and 6% touch no app code. The first figure overstates
  what is irrelevant, because that row includes clipboard and calculator, which features E and C lean
  on.

How cleanly a single upstream fix can be taken later depends on the files it touches. The AI service
files are quiet (2 to 6 commits each in 90 days), but `AIChatCoordinator.swift` has 34 and most
feature commits also touch registries, strings, docs and tests.

## 8. AGPL-3.0 obligations

This section reports what the licence text and the FSF's FAQ say. It is not legal advice.

### 8.1 Licence facts in the repo

- `LICENSE` is the GNU Affero General Public License version 3, with an "or (at your option) any later
  version" grant in its header and no additional terms.
- `CONTRIBUTOR_LICENSE_AND_FEEDBACK_AGREEMENT.md` licenses contributions under the project licence,
  adds a patent licence and a feedback licence, and leaves copyright with contributors. It gives
  upstream no right to relicense (DOC-ONLY).
- `NOTICE.md` covers the dictation model resources, 16 AI brand marks, and two MIT-licensed sources
  (Rooms and fsearch). It is copied into the app bundle but no code displays it.
- The About window (`Tinycast/Windows/About/AboutView.swift`) shows a licence line and links to
  upstream's site and repository.

### 8.2 If builds are given to friends

Handing someone a build is conveying under the licence. The concrete obligations:

1. **Provide the Corresponding Source for each build** (section 6). For a download, access to the
   source from the same place, or clear directions to it, is enough (6d). A Git repository readable by
   every recipient, tagged at the commit each build came from, meets this.
2. **Include everything needed to rebuild** (section 1). That covers `project.yml`, `Scripts/`, the
   generators for the `*.generated.swift` files, and `Scripts/raycast-runtime/src` with its lockfile,
   since `Tinycast/Resources/RaycastRuntime.generated.js` is built from it.
3. **Ship the licence text and keep existing notices intact** (sections 4 and 5b).
4. **Mark the work as modified, with a date** (section 5a).
5. **Keep Appropriate Legal Notices in the interface** (section 5d): copyright, no warranty, and how
   to view the licence. The About window is where these live today.
6. **License the fork's own code under the same terms** when it is conveyed as part of the app
   (section 5c), and add no further restrictions (section 10).
7. **Close the inherited notice gap.** The MIT licence requires its copyright and permission notice in
   copies. The runtime bundle includes React and react-reconciler with licence comments stripped
   (`Scripts/raycast-runtime/build.mjs`), and `NOTICE.md` does not list them.

Three things the licence does not require or grant:

- **No trademark rights.** The licence gives no right to the Tinycast name or icon, and `NOTICE.md`
  warns that the bundled AI brand marks are third-party trademarks.
- **Section 13 is not triggered** by a desktop app that offers no remote interaction over a network.
- **Installation Information** (section 6) is required when object code is conveyed in or with a
  consumer product as part of transferring that product. A download for a friend's own Mac is not
  that transaction. The FSF's FAQ does not address general-purpose computers directly, so treat this
  reading as UNVERIFIED.

### 8.3 If it is only ever run privately

Section 2 allows making, running and modifying the work "without conditions" as long as it is not
conveyed. No source has to be published, no notice changed and no third-party notice added. The
obligations in 8.2 begin with the first build handed to anyone else.

## 9. Distribution

### 9.1 How upstream ships today

- **Signing.** `.github/workflows/release.yml` is started by hand, builds on Xcode 27, and signs with
  upstream's Developer ID. `Scripts/package-release.sh` builds the DMG, notarizes and staples it, and
  zips the app. `Scripts/verify-signature.sh` fails any binary without a timestamped Developer ID
  authority, so the workflow as written cannot pass with a self-signed build.
- **Update signature.** `Scripts/sign-update.swift` signs the zip with an Ed25519 key whose public half
  is `TinycastUpdatePublicKey` in `Tinycast/Info.plist`.
- **Homebrew.** `tinycast` and `tinycast@beta` are in the official `homebrew/cask` and bumped by
  Homebrew's bot (DOC-ONLY, `docs/release.md`). Upstream's own tap now carries only the universal
  build for Intel.
- **In-app updates.** The app polls GitHub Releases for the repository named in
  `ReleaseFeed.repository` (`Tinycast/Features/Updates/Model/ReleaseFeed.swift`), 30 seconds after
  launch and then daily. It only offers an update; download starts when the user clicks, and the swap
  happens at quit.

### 9.2 How upstream shipped self-signed, until 2026-11-05

The earlier pipeline is in history at `dc265b26^`:

- The release workflow signed with the "Tinycast Self-Signed" certificate imported from a secret, with
  no notarization.
- The README told DMG users: "It's self-signed, so run `xattr -dr com.apple.quarantine
  "/Applications/Tinycast.app"` once."
- The Homebrew cask removed the quarantine flag after install (DOC-ONLY, old `docs/signing.md`).
- The updater accepted a sealed bundle signed by upstream's own Developer ID team, or one whose leaf
  certificate equalled the running copy's.

### 9.3 What applies to a build without Developer Program membership

| Fact | Source |
| --- | --- |
| Developer ID signing and notarization both need paid membership. | Apple Developer Forums, DTS reply (2022) |
| Apple silicon runs only signed code; an ad-hoc signature is enough to run but cannot pass Gatekeeper. | Apple, macOS 11 release notes |
| Since macOS 15 there is no Control-click override. The route is System Settings, Privacy & Security, Open Anyway. | Apple Support article 102445 (2026-05-27) |
| Privacy grants such as Accessibility follow the code's designated requirement. An ad-hoc signature changes every build, so grants are lost; one stable certificate keeps them. | Apple TN3127; `docs/signing.md` |
| Official Homebrew casks must pass Gatekeeper, so a non-notarized app cannot be one. | docs.brew.sh, Homebrew 5.0.0 release notes |
| Removing the quarantine flag with `xattr` still lets an app that Apple has not notarized open on macOS 26. | Third-party tests on macOS 26.6, not Apple documentation; UNVERIFIED on macOS 27 |

### 9.4 The simplest equivalent for the fork

Stated as the minimum the facts above require, not as a design:

1. **Give the build its own identity.** `ReleaseChannel`
   (`Tinycast/Features/Updates/Model/ReleaseChannel.swift`) treats every bundle identifier other than
   upstream's two as development, which never checks for updates. The constants that carry upstream's
   identity are the bundle identifier and URL scheme in `project.yml`, the schemes and
   `TinycastUpdatePublicKey` in `Tinycast/Info.plist`, `ReleaseFeed.repository`, the `com.tinycast.app`
   literal in `Tinycast/Platform/AppPaths.swift` and several stores, the scheme list in
   `Tinycast/Features/Extensions/Model/ExtensionDeepLink.swift`, the `tinycast.dev` hosts, the About
   links and the icon. Three details matter when they change: a new URL scheme has to be added to
   that scheme list, or extension links on it are dropped; `DictationWorker` hard-codes the Dictation
   helper's name; and `Scripts/build-dmg.sh` hard-codes `Tinycast.app`.
2. **Sign every build with one self-signed certificate**, created as `docs/signing.md` section 1
   describes, and keep that certificate. A friend who receives a build signed with a different one
   must grant Accessibility again.
3. **Hand over a DMG.** `Scripts/build-dmg.sh` already builds a self-signed Release DMG locally. As
   written it does not override the bundle identifier, so it produces `com.tinycast.app` on the stable
   channel (see risk R1).
4. **Tell friends the one-time step**: Open Anyway in System Settings, or the `xattr` command.
5. **Point them at the source**, as section 8.2 requires.

Updates for the fork have two simple shapes. Under a new bundle identifier the updater is inert, so
friends install a new DMG by hand. Re-pointing the updater at the fork's own releases needs changes in
`ReleaseFeed`, `ReleaseChannel` and the trust rule, because a zip with a valid signature is required
to be Developer ID signed (`BundleSignature.trustedHash`,
`Tinycast/Features/Updates/Service/BundleSignature.swift`). The community fork changed exactly these
files. Whether a self-signed build can then update itself needs a run (Appendix B).

## 10. Risks carried forward

R1 and R2 were traced in code by two readers and re-checked by an independent verifier. Neither has
been run (Appendix B).

### R1. A build that keeps upstream's identity would offer to replace itself with upstream's app

The chain, each link read in code:

1. `project.yml` gives a Release build the identifier `com.tinycast.app` and the version 0.1.0.
   `Scripts/build-dmg.sh` does not override the identifier, and overrides the version only when it is
   given one.
2. `ReleaseChannel` maps that identifier to the stable channel, and `ReleaseFeed.repository` is
   `abue-ammar/tinycast`. Version 0.1.0 is older than every upstream release, so the update pill
   appears.
3. If the user clicks Update, upstream's zip is downloaded. Its signature verifies against
   `TinycastUpdatePublicKey` in `Tinycast/Info.plist`, which is upstream's key.
4. A verified signature makes `BundleSignature.trustedHash` apply its Developer ID rule, which accepts
   any team. Upstream's notarized build passes.
5. `UpdateInstaller` swaps the bundle at quit. The fork is gone.

Limits: it needs a click on Update and a writable install folder, and Debug builds never update. Any
other bundle identifier puts the build on the development channel, where the updater does nothing.

### R2. Typed text can run in a shell with no confirmation

With default settings, a query that matches no entry and is not a calculation, a colour or a web
address shows only fallback rows. AI, File Search and Quicklinks are off by default, so the first row,
selected by default, is Run Shell Command. Return runs the typed text under `/bin/zsh -ilc` and
streams the output to a window.

The path is `FallbackCoordinator.run`, then `CustomCommandCoordinator.runShellCommand`
(`Tinycast/Features/CustomCommands/UI/CustomCommandCoordinator.swift`), then `streamOutput`. It skips
`perform`, which holds both the Custom Commands switch and the confirmation gate. The fallback is
enabled by default (`Tinycast/Features/Launcher/Service/FallbackStore.swift`) and reports itself
available whatever the settings.

This is the one place where typed text becomes a shell command, which feature F rules out for anything
a model produces.

### R3. Extension-command links run without consent

A `tinycast://extensions/...` or `raycast://extensions/...` link from outside the app runs the named
extension command with its arguments. `AppCore.handleOpenURL` passes it to
`ExtensionCoordinator.runDeepLink`, which checks only that extensions are enabled and the command
exists. The consent policy that guards other deep links is never consulted on this path.

### Other risks

| # | Risk | Evidence |
| --- | --- | --- |
| R4 | Extension code is unconfined: no sandbox, unrestricted files and processes, one consent dialog, and secrets in plaintext JSON | Section 4.4 |
| R5 | The keyless Claude and Codex routes rest on CLI flags and an undocumented control format. A CLI update can break them, and the fork would have to follow. | Section 3.3 |
| R6 | Several features use private or unofficial interfaces: four Dictionary symbols resolved at runtime (`Tinycast/Features/Dictionary/Service/DictionaryService.swift`), private lock-screen and Bluetooth calls in `SystemActionRunner`, and Raycast's store API | Sections 1.11 and 4.3 |
| R7 | Currency rates come from a service upstream runs | Section 1.11 |
| R8 | The seam files have no harness, and nothing runs tests automatically | Section 1.12 |
| R9 | Preferences, data and Keychain items are keyed by bundle identifier, so a renamed build starts empty. Whether Keychain items stay readable across self-signed rebuilds is UNVERIFIED. | Sections 1.10 and 3.5 |
| R10 | Every build given to friends must be signed with the same certificate, or they must grant Accessibility again. Each friend also has to pass Gatekeeper once by hand. | Section 9.3 |
| R11 | The React notices missing from the bundle become the fork's gap once a build is given to anyone | Section 8.2 |
| R12 | The on-device model has a 4,096-token context on macOS 26 and needs Apple Intelligence enabled there. Tinycast's route gives it no tools. Whether it can drive D or F on a given Mac needs a run. | Section 3.4 |
| R13 | Building needs Xcode 27, XcodeGen and SwiftLint. This Mac has none of them yet. | Section 1.12 |

## Appendix A. Where the docs and the code disagree

Code wins in every row. Rows that bear on a risk or a feature come first.

| Document | The document says | The code says |
| --- | --- | --- |
| `docs/features/deeplinks.md` | Any link from outside that carries input asks first. | Extension-command links run through `AppCore.handleOpenURL` and `ExtensionCoordinator.runDeepLink` with no consent prompt. |
| `docs/features/custom-commands.md` | `runCustomCommand(id:)` is the one funnel, so the confirmation gate cannot be bypassed. | `CustomCommandCoordinator.runShellCommand` is a second path that skips the gate. |
| `docs/features/updates.md` | A bundle is trusted with a valid signature and Developer ID, or if it meets the running copy's requirement. | The two are exclusive. A valid signature selects only the Developer ID rule, so a self-signed build with a valid signature is refused. |
| `website/content/docs/install.md` | Extension sign-ins are stored in the login Keychain. | `ExtensionStorage` keeps OAuth tokens and password preferences in a plaintext JSON file. |
| `docs/not-planned.md` | Raycast compatibility work has stopped. | 23 commits touched the runtime or `Tinycast/Features/Extensions` in the last 30 days. |
| `docs/not-planned.md` | Pinning a snippet and copying one to the clipboard will not be added. | Both shipped on 2026-11-12 (#1881). |
| `docs/features/ai.md` | The on-device route carries no instructions. | True for chat only. A Quick Action on the on-device route sends its instructions. |
| `docs/features/ai.md` | Deleting a chat asks first. | Deleting from the palette's Chat History (`QuickAICoordinator.deleteChat`) does not ask. |
| `docs/features/ai.md` | Does not mention it. | Pasting a file at the launcher opens Quick AI and attaches it (`PaletteWindowController.attachPastedFile`). |
| `docs/features/quick-actions.md` | Enabling the feature is the only place Accessibility is requested. | `QuickActionRunner.selection` may prompt on every shortcut press. |
| `docs/features/extensions.md` | `Action` ships with every convenience variant. | Four variants and `getFrontmostBrowserTab` reject as unsupported. |
| `docs/features/extensions.md` | An aborted fetch gives the caller its error promptly. | The caller sees the abort only after the whole response has arrived. |
| `docs/features/extensions.md` | The runtime bundle is about 200 KB. | It is 269 KB. |
| `docs/features/palette.md` | The mode table lists 17 modes. | `PaletteMode` has 23 cases. |
| `docs/features/palette.md` | Adding a mode means adding a conformer, not a branch. | `RootPaletteView.screen` and two `PaletteMode` properties are exhaustive switches. |
| `docs/features/palette.md` | `Tinycast/Features/PaletteRowIndex.swift` maps the selection to rows. | No shipped source uses it; only `Tests/PaletteSelectionTests.swift` does. |
| `docs/features/palette.md` | Pop to root also starts a new chat. | `PaletteWindowController.popToRoot` resets the screen only. |
| `docs/features/palette.md` | The summon chord is Option-Space. | No default chord is registered; onboarding records one. |
| `docs/features/launcher.md` | `CommandCatalog.contextual` names the query-driven commands. | No such symbol; the code uses `CommandID.isQueryDriven`. |
| `docs/features/launcher.md` | Quit All Apps confirms with an `NSAlert`. | It confirms through `AppCore.confirm`. |
| `docs/features/dictionary.md` | Three undocumented system calls are used. | Four are resolved at runtime. |
| `docs/architecture.md` | `AppCore` owns twenty-one coordinators; the tree has a `Migrations/` folder. | `AppCore` declares 35; `Tinycast/Migrations` does not exist. |
| `docs/testing.md`, `.swiftlint.yml` | `RootPaletteView` is 662 lines and `AppCore` 284. | 1,679 and 1,031. |
| `docs/standards.md` | There are four manager types. | There are ten. |
| `docs/release.md` | There is no CI workflow. | Six workflows exist; none runs tests or lint. |
| `docs/signing.md` | The entitlement table. | It omits the audio-input entitlement that `Tinycast/Tinycast.entitlements` declares. |
| `CONTRIBUTING.md` | Xcode 26. | `docs/development.md` and the release workflow require Xcode 27. |
| `SECURITY.md` | Update with `brew upgrade --cask tinycast` before reporting. | The casks declare automatic updates, so that command skips the app (DOC-ONLY on both sides). |
| `Tinycast/Resources/RaycastRuntime.generated.js` banner | Generated by `Tools/raycast-runtime`. | The generator is `Scripts/raycast-runtime/build.mjs`. |

## Appendix B. Not verified without a build or a run

Nothing below was run. Each row gives the command or step that would settle it.

| # | What is unverified | Command or step |
| --- | --- | --- |
| 1 | The harnesses and lint pass on the audited commit | `./Scripts/run-tests.sh`, then `./Scripts/lint.sh` |
| 2 | The Debug build compiles on this Mac | `xcodebuild build -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug CODE_SIGNING_ALLOWED=NO` |
| 3 | Memory and CPU for feature A | `footprint "Tinycast Dev"` before a summon, after it and after hiding; an Instruments signpost trace of subsystem `com.tinycast.perf` |
| 4 | R1: an unmodified Release build is offered upstream's release and accepts it | `./Scripts/build-dmg.sh`, install the result, choose Check for Updates |
| 5 | A renamed build runs with its own data folders and an inert updater | The command in row 2 with `-configuration Release TINYCAST_BUNDLE_IDENTIFIER=<new id> TINYCAST_URL_SCHEME=<new scheme>` |
| 6 | A self-signed build satisfies the previous build's designated requirement, so privacy grants and self-update survive | `codesign -d -r- <app>` on two successive builds |
| 7 | R2: typed text runs in a shell on a fresh profile | Type a harmless non-matching command such as `touch /tmp/probe`, press Return, then `ls /tmp/probe` |
| 8 | R3: an outside extension link runs with no prompt | `open 'tinycast-dev://extensions/<owner>/<extension>/<command>?fallbackText=test'` with a Debug build running |
| 9 | A fallback quicklink can pass the typed query to an extension command | Create a quicklink `tinycast://extensions/<owner>/<extension>/<command>?fallbackText={argument}` and choose its fallback row |
| 10 | The Store's Brew, Port Manager, Kill Process, Disk Usage and Image Modification extensions work in Tinycast | Install each from Settings and run its main command |
| 11 | The on-device model is available and can call tools or fill a typed structure on each Mac | A short Swift program that prints `SystemLanguageModel.default.availability`, then calls `LanguageModelSession(tools:)` and `respond(to:generating:)` |
| 12 | System frameworks can encode WebP | `swift -e 'import ImageIO; print((CGImageDestinationCopyTypeIdentifiers() as! [String]).contains("org.webmproject.webp"))'` |
| 13 | The installed `claude` accepts the flags Tinycast passes | Ask one question in Quick AI on the Claude route |
| 14 | What Gatekeeper does with a self-signed build on a friend's Mac, on macOS 26 and 27 | `spctl -a -vv <app>`, then the Open Anyway flow |
| 15 | Keychain items stay readable after a rebuild with the same certificate | Save an API key, rebuild, relaunch |
| 16 | How long a merge of upstream takes once the fork has changed the seams | A trial `git merge` on a scratch branch |
| 17 | The committed runtime bundle matches a fresh build of its source | In `Scripts/raycast-runtime`: `pnpm install`, `node build.mjs`, then `git diff --stat` |

Also not established, and not a matter of running the app: each search provider's terms for storing
and showing results; whether Homebrew still accepts any way to skip quarantine; which transfer methods
set the quarantine flag; and the legal reading of Installation Information in section 8.2.

## Appendix C. Method and limits

**How the audit was done**

- Seven readers each took one area, read its docs first and then checked them against source. Two
  researchers gathered outside facts from primary sources, each with the page it came from. Three
  analysts worked through the features clause by clause. Two verifiers re-checked the claims the
  verdict rests on, given the claim text only. Fifteen subagents in all, plus four exploratory ones
  before the plan was approved. Section 6 and the git measurements of section 7 were done directly.
- **Mechanical check.** The readers returned 361 claims. For 337, the quoted evidence was found
  verbatim in the cited file by script. The other 24 cite a count, a search, git history or a folder.
- **Independent verification.** 47 claims feeding the decisive questions and the risks were
  re-checked: 34 confirmed, 13 confirmed with a qualification that this document incorporates, none
  refuted.
- **Final review.** A critic read the draft against the brief and re-opened the code for its
  load-bearing statements. It confirmed 54 and raised 18 corrections, all applied.
- **Corrected after the planning pass.** Re-reading the source for the implementation plan changed
  six statements: the switch counts in section 6.1, the Files-section line count in 6.4, the unit of
  the on-device budget in 3.4, the harness count in 1.12, the backup file in 1.10, and three identity
  details in 9.4.
- Every command run was read-only: file reads, searches, `git log`, `git show` and `git blame`.

**Where the checking is weak**

- Readers and verifiers are the same model, so their mistakes can coincide. No human read the code.
- Nothing was built or run. Every behaviour described is what the source says, not what was observed.
- Features outside the audit's questions were not read (section 1.1), nor was the design system in
  depth.
- Outside facts are as of 2026-11-12 and will age: prices, quotas, Homebrew policy and Apple's
  documentation. Statements about macOS 27 rest on Apple's documentation and one third-party test
  series.
- The community fork's comparison was read in part.
- The local clone was not fetched during the audit. It matched `origin/main` at the audited commit.
- Section 7 measures how upstream changed its own code. It predicts the burden of a fork; it does not
  measure one.

## Verdict

**HARD FORK.** Take a snapshot of upstream, give the build its own identity, stop merging by default,
and take individual upstream fixes by cherry-pick. The cut takes effect at the first structural change
to a seam file; until then upstream's commits can still be merged at little cost.

This holds if the launcher is to get one query and action model, which the brief prefers to a second
architecture beside the first. If features A to F are only added beside the existing model, BUILD ON
THE FORK is the better choice.

### Why the other options fall away

- **EXTEND WITHOUT FORKING.** Extensions cannot add rows to the main list, reach Tinycast's AI, stream
  a response or keep a secret in the Keychain, and upstream has declined the hooks that would change
  this. All six features fit best in the app's own code.
- **HYBRID.** With every feature best placed in the app, the extension half reduces to stopgaps:
  existing Store extensions for Homebrew, ports, processes and image conversion, none yet run in
  Tinycast.
- **START FRESH** and **REUSE SELECTED COMPONENTS.** Tinycast already supplies the palette, hotkeys,
  ranked search, a file index, text capture and injection, a provider layer with a keyless Claude
  route, a tool loop and streamed shell execution. The integrated shell is the valuable part, and it
  is the part a new app would have to rebuild.

### Why a hard fork and not a fork that keeps merging

1. **One query and action model means restructuring the seam files, and upstream edits those most.**
   36% of upstream's commits touch one of the nine seam files, `RootPaletteView.swift` alone changed
   in 98 commits in 90 days, and six of the nine have no harness. Lines added beside existing code
   merge cheaply; nine in ten survived two months untouched. A restructured function loses that
   property: each later upstream insertion has to be carried across by hand.
2. **The two projects will not converge.** Upstream has declined AI smart search, acting on a
   selection or file, Quick Action results in the palette and AI for extensions. The fork's changes
   cannot go back, so the difference only grows.
3. **A hard fork can delete what it does not use.** The extension runtime, window management, notes,
   dictation and calendar are 34,954 lines of Swift, a quarter of the app, and features A to F do not
   depend on them. A fork that keeps merging cannot remove them without a conflict on every upstream
   change to them; the extension runtime alone saw 109 commits in 60 days.

Closing R2 and R3 is open to either kind of fork and is not an argument for this one.

### What it gives up

Of 409 upstream commits in 60 days:

- 35% touch the launcher and palette, the code feature A and the seams live in.
- 18% touch AI, MCP or Quick Actions, including upkeep of the keyless Claude route.
- 27% touch the extension runtime.
- 24% touch only other features, a group that includes clipboard and calculator.
- 6% touch no app code.

By subject line, 99 of the 409 read as fixes, and about 8 are security or trust changes. A hard fork
has to notice, choose and port each one it wants, and it becomes the only maintainer of 133,000
lines.

### The strongest argument against

Merging is measurably cheap while a fork only adds. Upstream's own features wire into the seams with
22 to 199 lines, the one community fork sits 9 commits behind, and features A to F as section 5
scopes them are mostly insertions into closed enums and switches. Upstream's AI upkeep is exactly
what a launcher on the keyless Claude route needs. A hard fork pays for that upkeep at once, while
its benefit arrives only when the seams are restructured. And the choice is one-way: stopping later
is always possible, resuming after diverging is not.

The argument is right about timing, and the recommendation takes it on: nothing is gained by cutting
before the first structural change to a seam file. It does not change the recommendation, because the
alternative is to shape the launcher around staying mergeable with a project that has declined its
direction.

### The facts this depends on

1. **Extensions cannot carry the unified experience.** Verified in code: static command entries only,
   an AI namespace that throws, buffered `fetch`, plaintext secrets. This rules out the two
   extension-led options whatever else is decided.
2. **Whether the launcher gets one query and action model.** The brief asks whether it can and
   prefers it; section 6.4 shows it restructures the seam files, which 36% of upstream's commits
   touch. If A to F are instead added beside the existing model, they are mostly insertions, and
   BUILD ON THE FORK is the lower-cost choice.
3. **The cost of merging was measured, not tried.** Section 7 rests on commit subjects, paths and
   line survival over 60 to 90 days. If trial merges after the first structural change prove cheap,
   the case for cutting weakens.
