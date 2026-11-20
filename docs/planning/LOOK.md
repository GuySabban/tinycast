# Look

Spotcast reads what is on screen and turns it into actions: a date becomes a calendar event, a link
opens, a phone number is called or copied, an address gets directions, any text can be copied,
translated or asked about.

- **Status:** step 1's Codex checks are recorded in `BASELINE.md` (Phase L step 1); check 7 is not
  settled and check 8 is still owed (section 6.2). No source file has changed. The phase, its steps and hours are in `IMPLEMENTATION_ROADMAP.md` (Phase L, after
  Phase 2).
- **Basis:** the fork at `5b6461e6` on `universal-launcher`, read on 2026-11-19. Facts about
  Spotcast's code below were read in the source, not run. Facts about macOS behaviour that this
  plan could not check are marked as needing a run and listed in section 12.
- **Related documents:** threats T22 to T27 and decisions D32 to D42 continue the numbering of
  `UNIVERSAL_INSTALL.md` and are in `RISKS_AND_DECISIONS.md`, moved there in step 1. The AI routes
  are described in `ARCHITECTURE_AUDIT.md` section 3.3; the Claude hook finding is `UNIVERSAL_INSTALL.md`
  section 10, row 24.

## 1. The plan in brief

1. **Trigger.** Look is a new built-in command, `CommandID.look`. Every bindable command already
   gets its own global hotkey through `HotKeyAction.command(_:)`, so Look gets one with no new
   `HotKeyAction` case (section 4). Inside the open launcher, ⌘L starts it.
2. **Capture.** One still image of the display under the pointer, taken with ScreenCaptureKit,
   with every Spotcast window excluded. The image lives only in memory and is dropped as soon as
   its text is read (section 3).
3. **Read.** Vision's `RecognizeTextRequest` reads the text in the existing `ClipboardTextHelper`
   process, which gains a mode that takes image bytes on standard input instead of a file path.
   `NSDataDetector` then finds dates, links, phone numbers and addresses in that text.
4. **Act.** The launcher opens on a Look screen: one row per detected item with its actions, then
   rows for the whole text (Copy, Translate, Ask AI). Nothing leaves the Mac until the person picks
   Ask AI.
5. **Ask.** Ask AI runs one text-only turn on the route chosen for Look, by default the Codex CLI
   route. The screen text is passed as quoted, untrusted data, with no tools, no web search and no
   MCP server in that turn (section 6).

One rule holds it together: **everything up to the action list is on-device and needs no AI.** A
model only ever sees screen text after an explicit Ask AI, and it can only answer in text.

### What a Look does, case by case

| On screen | Rows shown | Action on Return | Other actions (⌘K) |
| --- | --- | --- | --- |
| A date or date and time ("Thu 26 Nov, 14:00") | "Create Event · Thu 26 Nov 14:00" | The existing event editor, prefilled with that start and the line around it as title | Copy |
| A link, or a bare domain the detector accepts | The address, host first | Open in the default browser | Copy |
| A phone number | The number as written | Call (`tel:`, handed to FaceTime or a paired iPhone) | Copy, Message (`sms:`) |
| A street address | The address | Directions in Maps | Copy, Open in Maps |
| Any text | "Copy All Text", "Translate", "Ask AI" | Copy all recognised text | – |
| No text found | One row: "No text found on this display" | Close | – |
| Screen Recording not granted | One row explaining it | Open the Screen Recording pane in System Settings | – |

## 2. The Screen Recording permission

### 2.1 What is needed

A still image of other apps' windows needs the Screen & System Audio Recording grant (TCC service
`kTCCServiceScreenCapture`). Spotcast has no code for it today: `Platform/Permissions.swift` covers
Accessibility, Full Disk Access, calendar and camera only. Look adds:

- a check before capture with `CGPreflightScreenCaptureAccess()`, which never prompts;
- on the first Look only, `CGRequestScreenCaptureAccess()`, which shows macOS's prompt and adds
  Spotcast to the list in System Settings;
- when refused, the Look screen's explanation row, which opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.

The helper lives in `Features/Look/Service/`, not in `Platform/Permissions.swift`, so it adds no
lines to an upstream file. A grant usually takes effect only after the app is relaunched; the
explanation row says so, and offers Quit and Reopen.

### 2.2 Does macOS ask again?

Yes, on recent macOS, unless the app uses Apple's picker. macOS 15 added a recurring alert for
apps that capture the screen directly rather than through the system's content-sharing picker
(`SCContentSharingPicker`): the alert asks whether to keep allowing the app, and appeared weekly in
the betas and monthly at release. The exemption for remote-desktop apps is the
`com.apple.developer.persistent-content-capture` entitlement, which Apple grants on request to
members of its paid developer programme. A self-signed build cannot carry it.

So the plan assumes **a re-ask about once a month**, answered with "Allow". Whether macOS 26 and 27
keep the same interval is not verified (section 12, row 1). The picker avoids the re-ask but shows
a system window on every capture, which defeats a one-key action, so it is dropped (D35).

### 2.3 Keeping the grant across builds

TCC records the app's designated requirement. For a build signed with the kept self-signed
certificate (R10), the requirement names the identifier and the certificate, so a rebuild should
keep the grant. This differs from the login keychain, which R14 found tied to each build's code
hash, so it needs a run (row 2). The Dev build, `com.abueammar.tinycast.dev`, has its own grant,
as AGENTS.md intends.

### 2.4 What the grant also allows

Screen Recording lets every line of code in the process see every window. Two things follow:

- Raycast extensions run in the same process, in JavaScriptCore. The runtime exposes no capture
  API today, so an extension cannot use the grant. An upstream merge that adds one would change
  that; the merge checklist gains a search for `ScreenCaptureKit` and `SCScreenshot` (T13).
- The grant stays after Look is switched off. The Look settings section says so and links to
  System Settings, where only the person can remove it.

## 3. Capture

### 3.1 API

`SCShareableContent.current` lists displays, windows and running apps.
`SCScreenshotManager.captureImage(contentFilter:configuration:)` returns one `CGImage` in memory.
`CGWindowListCreateImage` is obsoleted and is not used (AGENTS.md: a deprecated API is a defect).

### 3.2 Never Spotcast's own windows

The filter is `SCContentFilter(display:excludingApplications:exceptingWindows:)` with Spotcast's
own `SCRunningApplication`. That excludes every Spotcast window at once: the palette
(`PalettePanel`), the floating actions menu (`MenuPanel`), HUDs, dialogs, the note and Settings.
Excluding only the palette's window number would leave the others, and the palette exposes no such
number today.

- **From the global hotkey:** capture first, then show the launcher on the Look screen.
- **From ⌘L in the launcher:** the panel stays open. The filter leaves it out of the image, so it is
  never hidden and shown again.

### 3.3 Several displays

**Settled (D32, by the owner on 2026-11-20): the display under the pointer**, using `NSScreen.underCursor` from
`Platform/ScreenTarget.swift` and its `CGDirectDisplayID`. That is where the person is looking, and
it matches how the launcher already chooses a screen with `openOnCursorScreen`. From ⌘L it is the
display the panel is on.

| Option | For | Against |
| --- | --- | --- |
| Display under the pointer | One image, one recognition, predictable | Text on another display needs the pointer moved first |
| Every display | Nothing is missed | Recognition time and memory scale with displays; more unrelated text in an AI ask |
| The frontmost window's display | Follows focus | A small focused window on one display while reading another is common |

A later version can add "Look at All Displays" as a second command, which costs one more
`CommandID` and nothing else.

### 3.4 Size

The image is taken at the display's pixel size, capped at 4096 px on the long side so recognition
matches the clipboard extractor's limits (`ClipboardTextExtractor`: 4096 px, 2048-high strips).
A 5K display becomes 4096 × 2304; text smaller than about 9 points may then be missed (row 5).

### 3.5 Never on disk

- The `CGImage` is encoded to PNG in memory and written to the helper's standard input. No file,
  no cache, no pasteboard.
- The helper writes text, never the image, to standard output, and exits.
- The image and the PNG data are released as soon as the write finishes; the Look state keeps only
  the text and the detected items, and drops them when the launcher closes.
- Nothing about a Look is logged, and the text is never added to clipboard history unless the
  person picks a Copy action (D40).
- Swap is outside the app's control. The image is a few tens of megabytes held for under a second,
  so it is noted, not mitigated.

## 4. The trigger and its seam cost

### 4.1 A new `HotKeyAction` case costs eight switches

`HotKeyAction` (`Features/HotKeys/Model/HotKeyAction.swift`) has eight exhaustive switches:

| File | What the switch does |
| --- | --- |
| `HotKeyAction.swift` | The stable defaults and registration key |
| `HotKeyAction+EntryID.swift` | The launcher entry an action belongs to |
| `HotKeyManager.swift`, three switches | Indexes of bound items; display name and conflict owner; dispatch |
| `App/AppCore.swift` | Display names of dynamic items |
| `DeepLinks/Model/DeepLinkConsentPolicy.swift` | Which actions need deep-link consent |
| `Launcher/Service/VisibilityStore.swift` | Hiding a hotkey with its category |

A `.look` case would add about 10 lines across six upstream files, three of which upstream edits
often, and a Settings row of its own in `GeneralSettingsView`.

### 4.2 A new command costs four

`HotKeyAction.builtInActions` already contains `.command(id)` for every bindable `CommandID`, and
`HotKeyTests` requires every command except Open in Browser, Run Shell Command and Quit to be
bindable, with its own recorder row in Settings › Commands. So `CommandID.look` gets a recordable
global hotkey with **no change to any `HotKeyAction` switch**. Its own cost:

| File | Lines | Why |
| --- | ---: | --- |
| `Launcher/Model/CommandID.swift` | 4 | The case, its English name, its SF Symbol (`text.viewfinder`), its keywords |
| `Launcher/UI/LauncherCoordinator.swift` | 2 | One arm in `runCommand` |
| `DeepLinks/Model/DeepLinkConsentPolicy.swift` | 1 changed | `.look` in the consent list: a link from another app must not start a capture unasked |

`HotKeyTests` needs no change: the new command is bindable, so its assertions hold. That makes it
**recommended (D33)**. It also makes Look a launcher row ("Look at Screen"), searchable by name.

### 4.3 The key inside the launcher

`PaletteShortcut` is "a chord aimed at the selected row", and Look is not about a row, so it is
matched in `RootPaletteView`'s key handling before the row shortcuts, as about 3 lines. ⌘L is free
in `PaletteShortcut.resolve` and in the palette's own handling (D34). Typing "look" and Return also
works, because Look is a command.

## 5. Recognition and detection

### 5.1 Text recognition: reused, with a new input

`ClipboardTextExtractor` already runs `RecognizeTextRequest` at `.accurate` with automatic
language detection, strips tall images, and caps the output at 32 KB. It runs inside
`ClipboardTextHelper`, a bundled helper started once per item, so Vision's memory leaves with the
process; `docs/features/clipboard.md` gives that as the reason the helper exists.

The helper takes a file path. Look must not write one, so the helper gains one mode, `image-stdin`,
that reads PNG bytes from standard input, and `ClipboardTextWorker` gains an entry that writes
`Data` to the pipe. About 15 lines in two upstream files (D36). The 60-second deadline, the 32 KB
cap and cancellation stay as they are; Look sets a 5-second deadline of its own.

Recognition levels: `.accurate` is the default. `.fast` is several times quicker but weaker on
small and non-Latin text; it is measured in step 3 and kept as a setting only if `.accurate` misses
the 1.2 s target (D39).

### 5.2 Detection: new

Nothing in Spotcast uses `NSDataDetector` today; `MeetingLink.swift` avoids it on purpose for the
calendar's hot path. Look runs it once per Look, on at most 32 KB, off the main actor:

- types `.date`, `.link`, `.phoneNumber`, `.address`;
- a detector is created inside the function that uses it, because it is not `Sendable`;
- results become plain `Sendable` values (`LookItem`: kind, matched text, range, and the parsed date,
  URL, number or address components), de-duplicated by kind and normalised text;
- links are kept only for `http`, `https` and `mailto`; anything else is dropped (T24);
- at most 20 items, in reading order.

`Features/Look/Model/` may import Foundation, which holds `NSDataDetector`, so the detector and its
mapping live in `Model/` and are covered by a harness, as AGENTS.md requires.

## 6. Ask AI

### 6.1 The route

Look has its own route setting, **defaulting to the Codex CLI route** (`AIModelSelection` `.codex`),
as the owner asked. The owner's general default stays Claude (D13). The setting lists only routes
that are enabled in Settings › AI, as `AIProviderFactory` already validates. If Codex is not
enabled, Ask AI's row says so and opens Settings › AI.

### 6.2 Checking the Codex route on this Mac

Phase 0 verified only Claude (`BASELINE.md` row 13); `ARCHITECTURE_AUDIT.md` marks Codex as read in
code, not run. Step 1 of the phase settles it with these checks, recorded in `BASELINE.md` as a
new row:

1. `codex --version` and `codex login status` from the owner's login shell; record the version.
2. Settings › AI › Manage: enable Codex; Codex models appear only after enabling.
3. One Quick AI question with a Codex model selected: it streams an answer.
4. `ps` during the turn shows one long-lived `codex app-server` child of the Dev build.
5. The turn ran read-only with network off: ask it to create `/tmp/look-codex-probe`; the file must
   not appear.
6. No session file for that turn appears under `~/.codex/sessions` (the runner starts threads with
   `"ephemeral": true`; this checks that the CLI honours it).
7. With MCP off, the turn lists no tools. Then check whether servers in the owner's
   `~/.codex/config.toml`, if any, are loaded by the app's `app-server`. If they are, Look's turn is
   not tool-free and step 8 must exclude them before Ask AI ships (row 8).
8. Time to first token over ten asks, for section 9.

If any of 3 to 6 fails, Look's default falls back to the on-device route until fixed, and the
owner is told.

**Result (2026-11-20, `BASELINE.md`):** checks 3 to 6 passed, so Codex stays Look's default. Check 7
did not settle row 8 of section 12: the owner's `~/.codex/config.toml` defines MCP servers, and only
the model's own answer says the turn could not reach them, so step 8 excludes those servers
explicitly. Check 8 gave one informal figure, about 2 s; the ten timed asks are still owed.

### 6.3 No tools in that turn

Screen text is untrusted: any web page, message or document on screen can contain instructions.
The turn is built so that following them can do nothing:

- **No tool servers and no tool session.** An empty `AIRequest.tools` is not enough: Claude and
  Codex get MCP access when their provider is built, not per request. Look builds its own provider
  through `AIProviderFactory` with no tool servers, so Claude runs with `--disallowedTools '*'
  --max-turns 1` and Codex with no servers and approval `never`.
- **No web search:** `AIRequest.webSearch` stays false.
- **A boundary.** The prompt is `QuickActionPrompt.boundary`'s wording, then the person's question,
  then the screen text fenced as data and labelled as text read from a screenshot. Quick Actions
  already use this shape for selected text (T2).
- **A text answer only.** It is drawn as plain text. Links in it are not opened without a click,
  and a click shows the host first.
- **Claude hooks.** If the owner picks the Claude route for Look, his `~/.claude` hooks run and see
  the screen text (`UNIVERSAL_INSTALL.md` row 24). Until the proposed `--setting-sources ""` fix
  lands, the route picker says so under Claude (D38).

### 6.4 Where the answer shows

On the Look screen itself, under a question field: the person types a question (default "Explain
this"), Return sends, Escape or ⌘. cancels within 100 ms. ⌘J hands the exchange to the AI Chat
window, which then follows chat's own tool settings for later turns, not Look's.

## 7. Privacy with a cloud route

A whole-screen capture holds far more than the thing the person meant: other windows, message
previews, notifications, a password manager left open, a colleague's document in a shared screen.
On-device recognition and detection keep all of that on the Mac. Ask AI on a cloud route sends
**all recognised text from that display**, up to 32 KB, to OpenAI through Codex (or Anthropic
through Claude), under that provider's retention terms.

What the plan does about it:

- Nothing is sent without Ask AI and Return. No automatic ask, no prefetch, no summary on open.
- **The first Ask AI in each Look shows what will be sent** (D37): the character count, the route
  and provider by name, and an editable copy of the text. The person can delete lines before
  sending. Later questions in the same Look reuse what was approved.
- The detected items are not sent unless they are in the text, and no image is ever sent.
- The Look settings section says, in one sentence, that Ask AI sends the screen's text to the chosen
  provider, and offers the on-device route.
- With the on-device route, nothing leaves the Mac at all, at the cost of a small context window:
  the text is trimmed to the model's reported window and the trim is shown.

What it does not do: detect and redact secrets. A pattern list would miss most of them and suggest a
safety it cannot deliver; the editable preview is the honest control.

## 8. What is reused and what is new

| Part | Reused | New |
| --- | --- | --- |
| Trigger | `HotKeyAction.command(_:)`, `ShortcutRecorder`, Settings › Commands, launcher rows | `CommandID.look`; ⌘L in `RootPaletteView` |
| Permission | – | `ScreenRecordingPermission` in `Look/Service/` |
| Capture | `NSScreen.underCursor`, display ids from `ScreenTarget` | `ScreenCapturer` over ScreenCaptureKit |
| Text recognition | `ClipboardTextHelper`, `ClipboardTextExtractor`, `ClipboardTextWorker` | The `image-stdin` mode and a `Data` entry (about 15 lines) |
| Detection | – | `LookDetector` over `NSDataDetector`, `LookItem` |
| Calendar event | `EventEditorSession`, `EventEditorView`, `CalendarStore.save` | An absolute start date and title prefill for `EventDraft` and `createEvent` (below) |
| Links, phone, maps | `NSWorkspace.open` as `QuicklinkLauncher` uses it | `tel:`, `sms:` and `maps://?daddr=` URL builders in `Look/Model/` |
| Copy | `Paster.copyPlainText` | – |
| Translate | `TextTranslator.translate(_:to:)`, the Quick Actions target language | – |
| Ask AI | `AIProviderFactory`, `AIRequest`, `QuickActionPrompt.boundary`'s wording | `LookPrompt`; the question field and answer on the Look screen |
| Screen | The palette, `PaletteMode`, row and actions-menu views | `PaletteMode.look`, `LookScreen`, `LookCoordinator` |
| Settings | – | `LookSettingsStore` under its own keys, not in backups or `settings.json` (D6); `LookSettingsSection` in the AI pane |

**The event editor needs a change.** `createEvent()` takes no arguments and keeps an existing draft;
`EventDraft` stores the start as an offset of 0, 15, 30 or 60 minutes from now, so it cannot hold
"26 November, 14:00". The change: `EventDraft` gains an optional absolute `start` that wins over the
offset, and `CalendarCoordinator.createEvent(title:start:duration:)` opens a fresh draft with them;
the editor shows the absolute start in the existing date row. About 15 lines in three calendar
files, plus a case in the calendar's harness. A detected date with no time becomes a 09:00 start with a one-hour duration, which the person can
change before saving.

## 9. Performance targets

Measured on the owner's Mac, Release build, one 5K display, with new signposts under
`com.tinycast.perf`. None is measured yet.

| Metric | Target | How to measure |
| --- | --- | --- |
| Hotkey to Look screen with actions | 1.2 s median, 2 s at the 95th percentile | `Look.total` signpost; a 120 fps screen recording for the whole path |
| Capture | 150 ms at the 95th percentile | `Look.capture` |
| Recognition, helper start to text | 1 s median | `Look.recognize` |
| Detection on 32 KB | 20 ms at the 95th percentile | `Look.detect` |
| Escape during recognition | Helper gone within 1 s | `ps` and the signpost's end |
| Resident memory | Under 100 MB at upstream's four points, with Look open as the "feature in use" point; back to baseline after close | `footprint` on the Dev build |
| Image lifetime | No `CGImage` or PNG buffer alive after recognition returns | Instruments Allocations, one Look |
| Helper memory | Under 300 MB at peak, gone after | `footprint` on the helper |
| Idle CPU, panel hidden | Unchanged: under 0.5% over 60 s | `top -pid` |
| Time to first AI token | 4 s through the Codex CLI, 1.5 s on device | Ten asks timed from a screen recording, as for Claude |
| AI cancel | Streaming stops within 100 ms | Screen recording |

## 10. Threats added

T22 to T27 are in `RISKS_AND_DECISIONS.md` section 1, moved there in step 1.

## 11. Decisions

D32 to D42 are in `RISKS_AND_DECISIONS.md` section 3, moved there in step 1.

## 12. Assumptions that need a run

| # | Assumption | How it is settled | Step |
| --- | --- | --- | --- |
| 1 | macOS 27 re-asks for direct screen capture about monthly, as macOS 15 did | Keep a dated note of each alert on the owner's Mac for six weeks after the first grant | 2, then ongoing |
| 2 | A rebuild with the same certificate keeps the Screen Recording grant | Grant, rebuild the Release app, Look again | 2 |
| 3 | `SCScreenshotManager` excluding the own app leaves out the palette, `MenuPanel` and HUDs | Look from ⌘L with the actions menu open and a HUD showing | 2 |
| 4 | A grant takes effect only after relaunch | First grant on the Dev build | 2 |
| 5 | 4096 px recognition of a 5K display reads 11-point text | A test page at 9, 11 and 13 points | 3 |
| 6 | The capture shows the menu-bar recording indicator, or not, for a single still | Watch the menu bar during a Look | 2 |
| 7 | `NSDataDetector` finds addresses in the owner's locales and Hebrew text | Fixtures from real screens in English and Hebrew | 4 |
| 8 | The app's `codex app-server` loads no MCP server from `~/.codex/config.toml` | Section 6.2, check 7. Not settled on 2026-11-20: the owner's config defines servers and only the model said it had none, so step 8 excludes them explicitly | 1, then 8 |
| 9 | `tel:` from a menu-bar app hands to FaceTime and asks before calling | One call to a test number | 7 |

Step 2 ran the spike in `Scripts/fork/look-capture-spike/` on a macOS 26.6.2 VM; results are in
`BASELINE.md`, "Phase L step 2". None of rows 1 to 4 or 6 is settled for the owner's Mac yet:

- **Row 1:** the log is open in `SCREEN_RECORDING_LOG.md`. On the VM the direct-capture alert
  ("bypass the system private window picker") came on the first capture after the grant.
The spike stood in for the Dev build, which cannot capture until step 5.

- **Row 2:** held on the VM: a rebuild with a new code hash and the same certificate captured with
  no prompt.
- **Row 3:** partly held on the VM: the palette, the actions menu and a dialog were left out,
  excluded by bundle from another process. No real HUD was shown on the VM.
- **Row 4:** half true on the VM: without a relaunch, capture worked but
  `CGPreflightScreenCaptureAccess()` stayed false until a new process. Step 5's permission check
  must not trust preflight alone in the process that was just granted.
- **Row 6:** not settled: the VM's remote-desktop app shows the same purple indicator.

## 13. Seam budget

Lines in files the fork does not own. `Localizable.xcstrings` and `Scripts/run-tests.sh` are listed
for size only.

| File | Added | Changed | Why |
| --- | ---: | ---: | --- |
| `Launcher/Model/CommandID.swift` | 4 | 0 | The command |
| `Launcher/UI/LauncherCoordinator.swift` | 2 | 0 | `runCommand` |
| `DeepLinks/Model/DeepLinkConsentPolicy.swift` | 0 | 1 | Consent for links |
| `Palette/PaletteMode.swift` | about 4 | 0 | The `.look` mode, its symbol and title |
| `Palette/RootPaletteView.swift` | about 5 | 0 | The mode's screen; ⌘L |
| `Clipboard/Service/ClipboardTextHelper.swift`, `ClipboardTextWorker.swift` | about 15 | 0 | The `image-stdin` mode |
| `Calendar/Model/EventDraft.swift`, `Calendar/UI/CalendarCoordinator.swift`, `EventEditorView.swift` | about 15 | 2 | Absolute start prefill |
| `App/AppCore.swift` | 2 | 0 | Look's settings store and coordinator |
| AI pane's settings view | 1 | 0 | `LookSettingsSection` |
| `Scripts/run-tests.sh` | about 4 | 0 | `LookTests` |
| `Resources/Localizable.xcstrings` | about 1,600 | 0 | About 30 strings in eight languages |

About 50 lines in thirteen upstream files outside strings. No `HotKeyAction` switch, no
`project.yml` change, nothing in `Features/Extensions`. Each line goes in `FORK_LEDGER.md` as it
lands.

## 14. Risks

- **The monthly re-ask is the main cost of the feature,** and nothing short of a paid Developer ID
  with Apple's entitlement removes it.
- **Recognition time on large displays.** If 1.2 s is missed, `.fast` or recognising only the
  pointer's half of the display are the fallbacks; both lose text.
- **Detector quality.** `NSDataDetector` misses informal dates and many non-US addresses, and finds
  false phone numbers in order numbers. Every row shows what was matched, so a wrong row is visible
  and harmless until Return.
- **The Codex route rests on an undocumented app-server protocol** (R5). A Codex update can break
  Ask AI; the other actions do not depend on it.
- **Upstream merges.** `RootPaletteView`, `CommandID` and the clipboard helper are busy upstream
  files. The seam is kept to a few lines each so a conflict resolves by keeping both sides.
- **Swift and macOS permissions are new to the owner,** as for every phase; ScreenCaptureKit's
  async API under Swift 6 is the least familiar part.
