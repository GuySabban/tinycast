# Risks and decisions

Threats and their safeguards, the audit's risks carried forward, the decisions still open, how the
fork keeps merging upstream, and what the licence requires before a friend gets a build.

The design these refer to is in `PROPOSED_ARCHITECTURE.md`, the phases in
`IMPLEMENTATION_ROADMAP.md`, the scope in `MVP_SCOPE.md`, and the evidence in
`ARCHITECTURE_AUDIT.md`.

## 1. Threat model

Sized for a personal app used by its author and a few friends. The realistic sources of harm are:

- text from the web, a file or a selection that tries to steer a model;
- a package that is not what its name suggests;
- typed or generated text reaching a shell;
- another app or a web page sending the launcher a link;
- a provider seeing more than the user meant to send;
- a change that arrives with an upstream merge.

"MVP-essential" means it must hold before the phase that introduces the feature ships. "Later
hardening" is worth doing when the named later feature arrives.

| # | Threat | How it could happen here | MVP-essential safeguard | Later hardening |
| --- | --- | --- | --- | --- |
| T1 | Prompt injection through web results | A result's title or snippet contains instructions, and the text is later given to a model | Web results never reach a model or a shell, and are drawn as cleaned plain text (`PROPOSED_ARCHITECTURE.md` section 5.3). | If results are ever summarised by a model: pass them as quoted data behind an instruction boundary, arm no tools in that turn, and never open a link a model produced without a click. |
| T2 | Prompt injection through files and selected text | A document or selection handed to a model carries instructions | Unchanged upstream behaviour: Quick Actions prepend `QuickActionPrompt.boundary` and get no tools; chat attachments pass an extension allowlist. No new path sends content to a model. | When context actions arrive: the same boundary, and no tools in any turn that carries untrusted content unless each call is approved with its arguments shown. |
| T3 | Untrusted packages | A cask installs something other than the app the user meant, or a tampered build. A cask can also run its own install steps as the user, which the dialog cannot list. | Only tokens present in Homebrew's own data are offered. The approval dialog shows the app's homepage and download host before anything runs. Casks Homebrew has disabled are refused. Homebrew checks the download's checksum and keeps the quarantine flag; the app never clears it. After install the bundle's seal is checked against Apple's signature or a Developer ID; an ad-hoc seal fails. For a cask's own steps the safeguards are Homebrew's review of its official casks and those same checks. | Show install counts and deprecation reasons in the dialog; warn on a cask with very few installs; add a notarization assessment to verification. |
| T4 | Shell execution | Typed text, a package name or model output is interpreted by a shell | Phase 0 gates Run Shell Command behind the Custom Commands switch and a confirmation. The install command is a fixed script with two positional values; the token must match a strict pattern and exist in the index. No model output reaches a shell anywhere in the plan. The Terminal hand-off shows the exact command before it opens Terminal. | Review imported custom commands; keep every future executor on fixed scripts with positional values. |
| T5 | File and Accessibility permissions | A feature asks for broad access, or a rebuild silently loses or widens a grant | The MVP's new features need no new permission: install and web search use neither Accessibility nor Full Disk Access. One signing certificate is kept for every build, so existing grants persist. | macOS may ask for App Management when Homebrew replaces an existing app; explain that in the dialog when upgrades are added. An AppleScript-based Terminal hand-off would add an Automation prompt, which is one reason it is not the first choice. |
| T6 | API key storage | A key leaks through preferences, a backup, `settings.json` or a log | Keys live only in the Keychain (`PROPOSED_ARCHITECTURE.md` section 5.4). Each person uses their own key. | Decide the bundle identifier once, because items are keyed by it. Items survive a rebuild with the same certificate, but each new build prompts once for the login-keychain password before reading them (R14). |
| T7 | Sensitive context sent to cloud models or services | Text leaves the Mac without the user realising | Nothing is sent on a keystroke. AI is off by default and the default route for friends is on-device. Web search sends only the typed query, only on Return, and its settings section says the provider may retain it. An install sends the cask token to Homebrew's site and downloads from the vendor's server; Homebrew's own analytics are switched off for installs the launcher starts. | A visible marker on rows that will contact a network service; a single "local only" switch. |
| T8 | Unsafe tool arguments | A model calls a tool with harmful parameters | The MVP adds no tools. MCP stays off by default; with it on, keep each server on Ask, since the trust dialog names the tool but not its arguments. | Typed OS actions validate every parameter against a fixed schema, bound ranges and paths, and show the parameters in the approval dialog. |
| T9 | Privilege escalation | The app obtains or relays an administrator password | In-app installs cannot prompt for a password, and anything that needs one runs in Terminal where the prompt is visible (`PROPOSED_ARCHITECTURE.md` sections 4.3 and 4.7). No askpass helper and no privileged helper. | None planned. Do not add `SUDO_ASKPASS`. |
| T10 | Update integrity | The app is replaced by a build the owner did not make | The fork's own bundle identifier makes the built-in updater inert (Phase 0). Friends get builds directly from the owner. | If in-app updates are wanted (D12), the trust rule in `BundleSignature` needs a deliberate change and its own key. |
| T11 | Destructive file operations | A feature deletes or overwrites user files | The MVP only adds files. Stop ends the process and deletes nothing. Upstream's uninstall, which only moves to the Trash, is unchanged. | Context actions write a new file beside the original, ask before any overwrite, and use the Trash. |
| T12 | Links from outside and extensions | A web page or app sends an extension-command link, which runs without consent (audit R3, confirmed by Appendix B row 8); extension code is unconfined (R4) | Extensions stay off, which is the default. With extensions off the link path does nothing. | A consent prompt on that path, as a small local patch or an upstream report (D10). |
| T13 | Changes arriving by merge | An upstream commit adds a network host, a permission or a behaviour the owner would not accept | Merge at upstream's stable tags, read the diff of the seam files, and list new outbound hosts after each merge with one search. | A small script that reports new hosts, entitlements and usage strings between two commits. |

T14 to T21, for installs beyond Homebrew, are still in `UNIVERSAL_INSTALL.md` section 7 until U1
step 1 moves them. Look (Phase L) adds T22 to T27, moved here from `LOOK.md` section 10 in Phase L
step 1:

| # | Threat | Safeguard |
| --- | --- | --- |
| T22 | Screen text reaches a cloud provider the person did not think about | On-device by default up to the action list; Ask AI only on Return; the first ask in each Look previews and allows editing the exact text, naming the provider (`LOOK.md` section 7) |
| T23 | Instructions on screen steer the model | No tools, no MCP, no web search in Look's turn; the boundary; the answer drawn as text; links in it need a click (`LOOK.md` section 6.3) |
| T24 | A detected link, number or address is hostile | Only `http`, `https` and `mailto` links; the row shows the host first; nothing opens without Return; `tel:` and `sms:` hand to the system, which asks before calling |
| T25 | A capture outlives its use | In memory only, released after recognition; passed to the helper by pipe; text dropped on close; nothing logged (`LOOK.md` section 3.5) |
| T26 | The Screen Recording grant is used by other code | No capture API in the extension runtime; merge checklist searches for capture APIs; the grant's breadth stated in Settings (`LOOK.md` section 2.4) |
| T27 | A link from another app starts a capture | `.look` requires deep-link consent |

## 2. The audit's risks, carried forward

| # | Risk | What the plan does | When |
| --- | --- | --- | --- |
| R1 | A build with upstream's identity offers to replace itself with upstream's app | Own bundle identifier, which makes the updater inert | Phase 0 |
| R2 | Typed text can run in a shell with no confirmation | Gate on the Custom Commands switch, and confirm | Phase 0 |
| R3 | Extension-command links run without consent. **Confirmed** by Appendix B row 8 (`BASELINE.md`): `open 'tinycast-dev://extensions/nhojb/brew/search?fallbackText=test'` opened Brew's Search with the text and asked nothing. | Keep extensions off; decide on a patch or a report (D10). Row 8 shows the gap is live whenever extensions are on, so D10 needs an answer before extensions are used day to day. | Open |
| R4 | Extension code is unconfined and stores secrets in plaintext | Keep extensions off unless one is needed; never put a key in an extension preference | Standing rule |
| R5 | The keyless Claude and Codex routes depend on undocumented CLI behaviour | Check the route after each CLI update; upstream's fixes arrive by merge; the on-device route is the fallback | Standing rule |
| R6 | Private and unofficial interfaces can break on a macOS update | Accepted. The affected features are Dictionary, lock screen, Bluetooth and the extension store. | Accepted |
| R7 | Currency rates come from a service upstream runs | Accepted. If it goes away, cached rates are served. | Accepted |
| R8 | Six of the nine seam files have no harness | A hands-on checklist after every seam edit and every merge (section 4) | Standing rule |
| R9 | Data and Keychain items are keyed by bundle identifier | Choose the identifier once (D1), before anyone stores data | Done in Phase 0 |
| R10 | Builds must share one signing certificate | Back up the certificate when it is created | Phase 0 |
| R11 | React's notices are missing from the bundle | Add them before the first friend build (section 5) | Before a friend build |
| R12 | The on-device model has a small context and no tools in Tinycast | Nothing in the first two phases depends on it; audit Appendix B row 11 settles it for Phase 6 | Phase 0 check |
| R13 | This Mac cannot build yet | Task 1 | Done in Phase 0 |
| R14 | Every new build asks once for the login-keychain password before it can read a stored secret (Appendix B row 15). The item survives a rebuild with the same certificate; without a Team ID the login keychain ties access to each build's code hash, not to the certificate. | Accepted for the owner's builds: "Always Allow" clears it per build. Applies to every `KeychainSecretStore` scope, upstream's AI keys included. For the Phase 2 web search key, the settings section must not treat a refused prompt as "no key stored", and the friend install note must mention the prompt after each new DMG. A paid Developer ID would remove it. | Phase 2 and the friend-build gate |
| R15 | System frameworks cannot write WebP (Appendix B row 12): ImageIO reads WebP but writes only JPEG, PNG, JPEG 2000, HEIC and AVIF | Phase 5's "Convert to WebP" needs the app's first third-party code (libwebp, BSD-licensed) or is dropped; see D15 | Phase 5 |

## 3. Open decisions

Each has a recommendation. D1 is the only one that blocks Phase 0.

| # | Decision | Alternatives | Recommendation | What settles it |
| --- | --- | --- | --- | --- |
| D1 | App name, bundle identifier and URL scheme, and how far the rename goes | Any name that is not Tinycast, with an identifier the owner controls. The rename can stop at the app's name and icon, or also cover the command names and About text that say Tinycast. | The owner chooses the three values before Task 2. The wider rename belongs to the friend-build gate. | The owner |
| D2 | How the identity is applied | (a) Release overrides in `project.yml`. (b) Command-line overrides only. (c) Keep upstream's identifier and disable the updater in code. | (a). It holds for every Release build, however it is started. (b) fails the first time someone runs upstream's script. (c) shares preferences, Keychain and scheme with any upstream install. | Already settled by the source, unless the owner prefers (b) |
| D3 | Web search provider | Exa; Tavily | Exa, because only its result source could be confirmed. Results stay in memory because its terms bar storing them. | Tavily stating where its results come from, or Exa permitting a local cache in writing |
| D4 | What the install card matches against | Homebrew's 64 KB install-count file (tokens); the 19 MB full catalogue (names and descriptions) | The small file for the MVP | The 50-name harness case, and a memory measurement of decoding the full catalogue |
| D5 | How a command is handed to Terminal | A `.command` file opened with `NSWorkspace`; AppleScript; copy the command and open Terminal | **Settled 2026-11-13:** the `.command` file, opened with Terminal.app by path. It ran with no prompt on macOS 27.2 (`PROPOSED_ARCHITECTURE.md` section 4.7). Copy-and-open is kept only for Homebrew's setup command. | Done |
| D6 | Where fork preferences are stored | Each feature's own store under raw keys, as `FallbackStore` does; upstream's `AppSettings` and its registries | Own stores. They add no lines to five busy files. The cost is that these switches are not in backups or `settings.json`, which suits switches that grant a capability. | The owner, if backup of these switches matters |
| D7 | Where fork settings are shown | Sections inside upstream's panes; one new pane | Sections: install in the Applications pane, web search in the Fallbacks pane, one line each. A new pane costs about twelve lines, five of them in `SettingsSearchCatalog.swift`, which a harness requires and upstream edits weekly. | Settled by the source, unless the owner wants a single pane |
| D8 | Fork strings and upstream's eight-language rule | Translate every string; ship English only and relax lint | Translate. An agent can do it, and lint stays untouched. | The owner |
| D9 | Upstream's documents that fork changes make wrong | Leave them and record each in the fork ledger; edit them | Leave them. `docs/` changed in 320 of the last 409 upstream commits, so every edit there is a future conflict. | Settled by the churn figures |
| D10 | Risks R2 and R3 upstream | Report them privately as `SECURITY.md` asks; keep local patches only | The owner's call. A report costs nothing, and an upstream fix would let the fork drop its own patch. | The owner |
| D11 | How often to merge | At each upstream stable tag; weekly; when needed | At each stable tag, and never in the middle of a phase's seam edits | Revisit after three merges, using the recorded times |
| D12 | Updates for friends | A new DMG by hand; the built-in updater pointed at the fork | By hand until there are enough builds to justify the work | The number of friend builds |
| D13 | The owner's default AI route | Claude through the CLI; the on-device model | Claude for quality, on-device as the fallback | Audit Appendix B rows 11 and 13 |
| D14 | Where install progress is shown | The existing output window; a progress pill only | The output window. It shows Homebrew's own log and has Stop. | Use it for a week |
| D15 | WebP output in Phase 5 (R15) | Vendor libwebp's encoder as source, the app's first third-party code, with its licence added to `NOTICE.md`; call an installed `cwebp` from Homebrew when present; leave WebP out and offer HEIC or AVIF, which ImageIO writes | Leave WebP out of Phase 5's first version. Upstream has zero third-party dependencies, and vendoring C code adds a build step and a licence duty for one format. Revisit if WebP is asked for by name. | The owner, when Phase 5 is re-planned |

D16 to D31 are still in `UNIVERSAL_INSTALL.md` section 8 until U1 step 1 moves them. Look's
decisions, D32 to D42, moved here from `LOOK.md` section 11 in Phase L step 1. D41 is set by the
brief, and the owner settled D32 and D35 on 2026-11-20; the others wait on the owner.

| # | Decision | Alternatives | Recommendation |
| --- | --- | --- | --- |
| D32 | Which display | Under the pointer; every display; the frontmost window's | **Settled by the owner, 2026-11-20:** the display under the pointer; "All Displays" as a later command |
| D33 | How the hotkey is added | A `HotKeyAction.look` case; a `CommandID.look` | `CommandID.look`: 7 lines in three files instead of about 10 in six, and no `HotKeyAction` switch changes |
| D34 | The key inside the launcher | ⌘L; Tab; none | ⌘L: free, and L for Look |
| D35 | Capture route | Direct capture with a monthly re-ask; the system picker every time | **Settled by the owner, 2026-11-20:** direct capture |
| D36 | Where recognition runs | A stdin mode in the existing helper; in the app; a new helper target | The existing helper: Vision's memory leaves with it, and a new target would edit `project.yml` |
| D37 | Consent before a cloud ask | Preview on the first ask of each Look; once ever; never | Each Look |
| D38 | Claude for Look before the hook fix | Allowed, with a note; hidden until the fix | Allowed with a note; it is the owner's own Mac and hooks |
| D39 | Recognition level | `.accurate`; `.fast`; a setting | `.accurate`, unless it misses the target |
| D40 | Copy and clipboard history | Into history like any copy; marked to skip history | Into history: it is the person's own copy, and only text |
| D41 | Look's AI route | Its own setting defaulting to Codex; the general default | **Set by the brief:** its own setting, Codex by default |
| D42 | An undated time ("at 3") | Today; the next such time; ignored | The next such time, shown on the row so a wrong guess is visible |

## 4. Upstream sync strategy

The fork keeps merging. The aim is a merge that takes an hour or two and never surprises.

### Shape of the repository

- `upstream` is `abue-ammar/tinycast` and `origin` is the owner's GitHub fork. Today the clone's only
  remote is `origin`, pointing at upstream, so it is renamed to `upstream` and the fork is added as
  `origin`.
- `main` mirrors `upstream/main` and takes no commits.
- `universal-launcher` is the fork. Every change to an existing file is small and listed in the fork
  ledger below.
- New code lives in new folders (`Tinycast/Features/PackageInstall/`, `Tinycast/Features/WebSearch/`),
  new harness files and new documents. Upstream cannot conflict with a file it does not have.
- GitHub Actions stay disabled on the fork. Three of upstream's workflows would otherwise act on the
  fork's own pull requests and issues: one closes pull requests with no linked issue after 24 hours,
  one posts triage comments, and one objects to commits credited to an AI tool.

### The fork ledger

`docs/planning/FORK_LEDGER.md`, started in Task 2, lists every line changed in an existing file: the
file, the symbol, what was added and why, and any sentence in upstream's docs it makes wrong. It
serves three purposes: re-applying an edit after a conflict, checking the seam budget in
`PROPOSED_ARCHITECTURE.md` section 7, and stating the modifications the licence asks to be marked.

### Routine

1. Fetch `upstream` with its tags and fast-forward `main`.
2. Cut a scratch branch from `universal-launcher` and merge the newest stable tag (`vX.Y.Z`) into it,
   not the tip of `main`. Merge, not rebase, with `git rerere` enabled so a resolution is remembered.
3. Resolve by file class:

   | File class | Resolution |
   | --- | --- |
   | `Tinycast.xcodeproj/project.pbxproj` | Take upstream's, then `xcodegen generate` |
   | `Tinycast/Resources/Localizable.xcstrings` | Keep both sides' keys. The file is sorted by key, so conflicts arise only where neighbouring keys changed. Then run `./Scripts/sync-strings.sh`. |
   | `Scripts/run-tests.sh` | Keep the fork's entries together at the end of the list |
   | Seam files | Take upstream's version of the surrounding code and re-apply the ledger's insertions |
   | Upstream's docs and `website/` | Take upstream's; the fork never edits them |
   | A renamed or split file the fork had edited | Follow the rename; re-apply from the ledger |

4. Build Debug, run the harnesses and lint, and compare with the recorded baseline.
5. Run the hands-on checklist, because six of the nine seam files have no harness: summon the panel;
   launch an app; a calculation; a file row; the install card through to its dialog; the web trigger;
   each fallback; Tab into AI; the fork's settings sections. Then the two Phase 0 guards: with Custom
   Commands off there is no Run Shell Command row, and the launcher lists no Check for Updates
   command.
6. Search the merged diff for new outbound hosts and new entitlements.
7. Merge the scratch branch into `universal-launcher` and record the time taken in the ledger.

### What to watch upstream

- Changes to `LauncherScreen.Row`, `LauncherList`, `Fallback` and `CommandID`: these are the types the
  fork extends.
- `Tinycast/Features/Updates/` (`ReleaseChannel`, `UpdateCheckStore`, `BundleSignature`) and the two
  Phase 0 patch sites in `FallbackCoordinator` and `CustomCommandCoordinator`. No harness compiles
  those two files, so a merge that drops the fork's line would silently reopen R2, and a change to
  how an unknown identifier is treated would reopen R1.
- A fix for R2 or R3: drop the fork's patch when upstream's lands.
- Anything in `docs/not-planned.md` that moves from declined to planned for web search, install or AI
  in the list.

### When to revisit a hard fork

Any one of these reopens the question the audit's verdict left open:

- Two merges in a row take more than four hours each.
- Upstream restructures the row model in `LauncherScreen` or `LauncherList`.
- A planned feature needs a seam restructured. `PROPOSED_ARCHITECTURE.md` section 8 names the first
  one: AI answers as rows in the main list.
- The owner wants to delete upstream features, not just switch them off.

## 5. Licence duties before a friend gets a build

The obligations are set out in `ARCHITECTURE_AUDIT.md` section 8.2 and are not repeated here. This is
what the fork does to meet them. None applies while the fork is only run by its author.

| Duty (audit 8.2) | What the fork does |
| --- | --- |
| Provide the source for each build | The public GitHub fork is the source. Tag the commit each build was made from as `fork-YYYY-MM-DD`, and give friends the repository link with the build. A tag shaped like upstream's `vX.Y.Z` would trip `Scripts/check-migrations.sh`. |
| Everything needed to rebuild | Already in the repository: `project.yml`, `Scripts/`, the generators and the runtime source. The fork's build script is committed too. |
| Ship the licence text | Put `LICENSE` in the disk image beside the app. |
| Mark the work as modified, with a date | A `FORK.md` at the repository root stating that this is a modified version, since when, and pointing to the ledger. One added line in the About window says the same. |
| Keep legal notices in the interface | Keep upstream's licence line in the About window and add a link to the fork's source. |
| Same licence for the fork's own code | New files carry no other licence. |
| Close the React notice gap | Append React's, react-reconciler's and scheduler's MIT notices to the end of `NOTICE.md`, which is already bundled into the app. |
| No trademark rights | Own name and icon, and the visible names listed in the friend-build gate of `IMPLEMENTATION_ROADMAP.md` (D1). |

Two edits here touch upstream files: one line in `Tinycast/Windows/About/AboutView.swift` and an
appended section in `NOTICE.md`. Both go in the fork ledger.
