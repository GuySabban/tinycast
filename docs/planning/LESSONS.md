# Lessons

Technical lessons from the fork's Phase 0, Phase 1 and the universal install plan: gotchas, root causes
and procedures that cost time once and should not cost it again. Results and numbers live in
`BASELINE.md`, decisions in `RISKS_AND_DECISIONS.md`, and every changed upstream line in `FORK_LEDGER.md`.

Facts about outside tools were measured on 2026-11-13 and 2026-11-14 with macOS 27.2, Xcode 27.2,
Swift 6.4.2, Homebrew 7.0.13 and Claude Code CLI 2.1.325. Re-check them after an upgrade.

## Setting up a Mac

- **Accept the Xcode licence first.** After Xcode is installed, `git`, `brew` and `xcodebuild` all refuse
  to run until someone with admin rights runs `sudo xcodebuild -license accept`.
- **`security import` rejects a `.p12` made by OpenSSL 3 or later** with "MAC verification failed during
  PKCS12 import (wrong password?)", even with the right password. OpenSSL 3+ exports AES-256 with a
  PBKDF2/SHA-256 MAC; the keychain importer reads only the legacy 3DES/SHA-1 format and reports anything
  else as a wrong password.
  - Fix: `openssl pkcs12 -export -legacy ...`.
  - To convert an existing file: `openssl pkcs12 -in old.p12 -passin pass:X -nodes -out key.pem`, then
    `openssl pkcs12 -export -legacy -in key.pem -name "<name>" -out new.p12 -passout pass:X`, then delete
    `key.pem`.
  - `security find-identity -p codesigning` then lists the identity as `CSSMERR_TP_NOT_TRUSTED`. That is
    normal for a self-signed certificate, and `codesign` still signs with it.
  - Upstream's `docs/signing.md` lacks `-legacy` and stays unedited; the erratum is in `FORK_LEDGER.md`.
- **A self-signed build asks for the login keychain once per rebuild.** With no Team ID, keychain access is
  tied to the cdhash (risk R14). The data survives. TCC grants do survive rebuilds, because the designated
  requirement is pinned to the certificate leaf.

## Tests and harnesses

- **`FormInputTests` fails in Light mode** with eight failures, starting with "the placeholder rendering
  test captures visible text". Its windows follow the system appearance, and `inkBounds` counts only pixels
  with red above 0.2, so the theme's dark text in Light mode measures as empty. Run the suite with macOS in
  Dark mode. A `-AppleInterfaceStyle Dark` launch argument does not change the window's appearance. The
  harness is upstream's and is not patched.
- **Drive the real read path.** The prowlarr bug (below) shipped past harness cases that handed the token
  straight to `InstallPlan` and `PackageCandidate`. `PackageInstallCoordinatorTests` now calls
  `candidate(for:)` end to end with stub collaborators, in the style of `UninstallCoordinatorTests`.
- **Check that a regression test fails with the fix removed** before calling it a regression test.
- **`await` cannot sit inside an `@autoclosure` `expect`.** The fork's harnesses use
  `expectSettles(message) { condition }` instead.
- **Inject time, network and paths.** `CaskIndexStore` takes `Schedule` and `now`; the coordinator takes
  `session:`, `prefix` and `home`. Retry, refresh and lookup-delay cases then run in under a second through
  an in-process `URLProtocol`.
- **Never run real `brew` in a harness.** `PackageInstallServiceTests` puts a fake `brew` script in a
  scratch prefix and runs it through the real pseudo-terminal runner, checking arguments, environment, exit
  status, Stop and the sudo refusal.
- **A harness compiles only the files `Scripts/run-tests.sh` lists for it.** A constant a harness must
  assert on belongs in a file it already compiles, usually under `Model/`.
- **Judge latency on Release (`-O`) builds.** The install match's Debug (`-Onone`) p95 was 10.4 ms, nearly
  all in upstream's `LauncherMatch` for one- and two-letter names; Release p95 is under 1 ms.
- **"No space left on device" during a harness run is the disk, not the code.** A full harness run plus a
  second DerivedData (for example a trial-merge worktree) needs room; delete the trial build and Release
  intermediates.
- **Audit figures go stale.** The audit said 114 harnesses when upstream had already removed one (113).
  Count from `run-tests.sh` output, never from a document.

## Swift and concurrency

- **`Signposts.interval`'s async variant cannot take a main-actor closure** (a `sending` error). Put the
  timed work in a nonisolated `@concurrent` static, as `UninstallScanner` does.
- **Don't build `entries + extra` per keystroke.** Copying the 6k-entry cask array on each call raised the
  match median about 10x. `CaskIndex.matches(_:limit:including:)` walks the two lists separately and keeps
  the dictionary for exact hits.
- **Read caches off the main actor in `start()`, not `init`.** Decoding and folding the cask index takes
  tens of milliseconds.

## Localization

- **New strings stay out of `Localizable.xcstrings` until `sync-strings.sh` runs.** Building in the Xcode
  IDE syncs them, and lint then fails until all eight languages are translated.
- **`xcstringstool sync` rewrites three things in upstream's catalog:** `"" : {}`, one whitespace-only line
  and the missing final newline. Put all three back so the diff is additions only (ledger P1.7). Expect
  this after every sync.
- **Before syncing, check upstream's rule.** No localized phrase interpolated inside another literal, and
  no count interpolated as a preformatted string: use `%lld` keys with plural forms.

## AppKit and SwiftUI

- **An ordered-out window is not a stopped window.** `HUDPresenter.dismiss()` faded and ordered the panel
  out but kept its `NSHostingView`, so the progress pill's spinner (`progress.indicator` with a repeating
  `.symbolEffect(.variableColor.iterative…)`) kept animating while hidden: +53 MB that never came back and
  about 6.6% idle CPU. `fadeAway(_:)` now sets `panel.contentView = nil` in `fadeOut`'s completion (ledger
  P1.8, worth offering upstream). Any view with a repeating animation must lose its view when hidden.
- **That spinner costs about 53 MB while it is on screen**, mostly graphics memory. The fork avoids it for
  fast lookups: the pill appears only after `PackageInstallCoordinator.lookupPillDelay` (300 ms), and only
  a pill that appeared is hidden. About one lookup in twenty still runs past 300 ms.

## Homebrew

### Data

- **The 30-day install-count file is not the catalogue.** It lists only casks installed in its window, so a
  disabled cask nobody can install drops out (prowlarr did; wine-stable, disabled the same day, kept a row).
  For "is this cask known" use the Caskroom or the full catalogue. `PackageCandidate` adds Caskroom tokens
  the index lacks as zero-install entries.
- **The same file still lists 148 disabled casks.** Being in it says nothing about installability.
- **Install counts are strings with thousands separators** ("6,593").
- **Cask records have per-macOS `variations`.** The base is the newest macOS; `arm64_tahoe` overrides for
  macOS 26, and the install receipt on macOS 27 records `arm64_golden_gate`. Decode with a variation key.
- **Use an app artifact's resolved `target` name for presence.** Thorium.app installs as
  "Thorium Browser.app".
- **`disable_reason` is a symbol or free text**, never a display string.
- **`sudo` can be `"if_needed"`**, and sudo in `uninstall` or `zap` doesn't count for install.
- **45 casks have a manual installer step**; they go to Terminal.
- **Tap casks return 404 from the public API.**
- **Common-name misses exist.** "github desktop" is token `github`.

### Local state

- **`Casks/TOKEN.json` in the Caskroom is `{}` for casks loaded from the API.** App paths come from
  `.metadata/INSTALL_RECEIPT.json` (`uninstall_artifacts`) plus `config.json`'s `appdir`; `InstalledCask`
  reads them.
- **An interrupted install leaves a Caskroom folder.** Ctrl-C at Terminal's password prompt left the
  downloaded pkg and an empty `.metadata/<version>/<timestamp>/Casks/`. `brew list --cask` lists it, but
  Homebrew's `Cask#installed?` does not: it asks whether the newest `.metadata/*/*` holds
  `Casks/TOKEN.json` or `.rb`. `HomebrewEnvironment.hasInstallRecord` uses the same test. `brew uninstall
  --cask` removes the leftover without sudo.
- **The Caskroom can record a cask whose app was deleted.** The card says the app is missing and offers
  `brew reinstall --cask TOKEN` in Terminal, except for a disabled cask, which Homebrew won't reinstall.

### Running brew

- **`HOMEBREW_NO_SUDO` refuses in two places with two messages.**
  - Before the download, `cask/installer.rb` `check_requirements`: "TOKEN: The ARTIFACT artifact requires
    sudo, but HOMEBREW_NO_SUDO is set." This covers `pkg`, `keyboard_layout`, an `installer script` with
    `sudo: true`, and sudo pre- and postflight steps.
  - At run time, `system_command.rb` `sudo_prefix`: "sudo is disabled by HOMEBREW_NO_SUDO."

  `BrewInvocation.refusedSudo(in:)` matches both. `CaskRecord.needsPassword` routes such casks to Terminal
  beforehand, so the message is only the fallback.
- **Ask mode is skipped only without a TTY**, so `HOMEBREW_NO_ASK=1` is required under the pseudo-terminal.
  It prompts only when the plan adds dependencies (`install.rb` `ask_prompt_needed?`).
- **Clear `HOMEBREW_CASK_OPTS`.** The runner starts a login shell, so the user's `~/.zprofile` runs first;
  a custom install folder set there would make the dialog's "Installs to" line wrong.
- **App Management is checked only when the target app already exists** (reinstall or upgrade;
  `cask/artifact/moved.rb` writes a test file inside the bundle). Replacing an app from Tinycast gets a
  silent TCC denial, and Homebrew then deletes and copies the app. A fresh install never asks. The
  "Your terminal does not have App Management permissions" warning prints only when
  `HOMEBREW_NO_APP_MANAGEMENT_PERMISSIONS_PROMPT` is set.
- **`brew ruby` turns on developer mode** (`homebrew.devcmdrun`). Run `brew developer off` afterwards, or
  set `HOMEBREW_DEV_CMD_RUN=1` for the call.
- **Confirm Homebrew behaviour with a real run of the shipped code**, such as a scratch driver compiled from
  the real sources. Reading one source file missed the first sudo refusal.

### Terminal hand-off

- **A `.command` file opened with Terminal.app by path runs with no prompt** on macOS 27.2 (about 2 s), and
  can delete itself.
- **Terminal leaves the window open at "[Process completed]"**, so a failed hand-off's output survives until
  the window is closed. Capture it then: Homebrew writes no cask log, and a closed window loses it (the one
  Blender reinstall failure was lost this way).
- **To tell whether a brew run failed before the download**, watch its child processes. A run that never
  starts `curl` (or `hdiutil`) failed during cask loading or the requirement checks.

## Installing outside Homebrew

These shaped `UNIVERSAL_INSTALL.md`.

- **`hdiutil` is deprecated on macOS 27** and warns on every verb. `diskutil image attach` replaces it but
  does not verify an image's checksums: it mounted a corrupted image `hdiutil` refused.
- **Quarantine propagates.** A quarantined image mounts with the quarantine flag, and `FileManager.copyItem`,
  `ditto` and `cp` copies carry the attribute. The app has no `LSFileQuarantineEnabled`, so it must set the
  attribute itself on what it downloads.
- **`Security.framework` cannot read a `.pkg` signature**; it reports unsigned. Use
  `pkgutil --check-signature` and `spctl -a -t install`. `SecAssessmentCreate` has no public header in the
  Xcode 27.2 SDK.
- **A disk image with a licence agreement handed to Finder unmounted skips every check.** Refuse it unless
  its bytes match a cask checksum.
- **mas-cli 7.0.0 needs root** for `get` and `install`, can't buy paid apps, can't sign in, and relies on
  private frameworks.
- **Apple's search API:** use `entity=desktopSoftware`; `macSoftware` returns iPhone records. A search for
  "xcode" does not return Xcode.
- **No outside source proves a domain is official:**
  - The App Store's `sellerUrl` is typed by the developer and not verified by Apple.
  - Wikidata's official-website property is unprotected on small items.
  - 4,284 of 7,831 casks download from a different registrable domain than their homepage, so a
    same-domain rule rejects most real vendors.
  - Homebrew removed its `verified:` stanza in July 2026.
  - 2,781 casks have no checksum, so a cask's download address is not an anchor: a re-registered storage
    bucket at that address would install as trusted.
- **ImageIO cannot write WebP.** AVIF and HEIC work.
- **The on-device model** reported an 8,192-token context and returns a member of a run-time closed set
  through `DynamicGenerationSchema`. First call about 5 s, later calls about 0.6 s.

## The Claude CLI route

- **`claude -p` run as a subprocess loads the user's `~/.claude` settings, hooks, plugins, agents and
  `CLAUDE.md`** unless the command line excludes them. Every Quick AI turn, title request and the
  model-list probe at launch is such a process, so the user's own hooks see every prompt and their output
  enters the model's context (about 4,500 extra tokens per turn in the test). `--bare` is not an option: it
  refuses the OAuth sign-in.

  | Variant | Hooks | `CLAUDE.md` | Server from `--mcp-config` |
  | --- | --- | --- | --- |
  | As the app runs it | fire | loaded | connected |
  | `--setting-sources ""` | none | not loaded | connected |
  | `--setting-sources project,local` | none | not loaded | connected |
  | `--restricted` | none | not loaded | connected |
  | `--safe-mode` | none | not loaded | **dropped** |
  | `--settings '{"disableAllHooks":true}'` | none | **loaded** | not tested |

  Upstream keeps the user's settings on purpose (`docs/features/mcp.md`: environment, proxy and
  `apiKeyHelper` keep working), so `--setting-sources ""` reverses a documented upstream choice. It is
  proposed, not applied; the change would be one constant in `Model/InstalledAILaunch.swift`, used by
  `InstalledCLIProvider.swift` and `claudeControlArguments`. A clean exclusion needs CLI 2.1.314 or later.
  Without code changes, `CLAUDE_CODE_RESTRICTED=1` in the app's AI Environment field stops the hooks and
  keeps MCP.
- **`--json-schema` is delivered as a tool**, so the app's `--disallowedTools "*"` blocks typed output.

## Upstream merges and identity

- **Trial-merge on a scratch worktree first**, then delete it. The expected conflict is the generated
  `project.pbxproj`: regenerate it with `xcodegen generate` rather than resolving by hand. Then check every
  `FORK_LEDGER.md` line survived, and that the build has no warnings, the harnesses pass and lint is clean.
- **Upstream's next stable tag moves to bundle ID `com.abueammar.tinycast`.** Spotcast
  (`io.github.guysabban.spotcast`) is unaffected: the migration guard and `ReleaseChannel` both skip it. The
  Dev build moves to `com.abueammar.tinycast.dev`, and its TCC grants must be given again.
- **Never build `TinycastHandoff`.** It carries `com.tinycast.app`.
- **Spotcast and an installed upstream Tinycast both claim `raycast` and `com.raycast`** and share the
  default hotkey. Don't run both.

## Measuring and observing

- **In a zsh tool shell, `log` is a builtin.** Call `/usr/bin/log`.
- **`script -q /dev/null log stream` fails in a background task** ("tcgetattr/ioctl"). Poll
  `/usr/bin/log show --start … --signpost` instead.
- **A sampler looping on `while pgrep -f <script>` inside that script's own background job wrote nothing.**
  Give it a fixed iteration count.
- **A deep link from the shell can land in the wrong build.** The scheme can stay registered to an older
  DerivedData copy, and a plain `open` goes there. Name the app:
  `open -a "<build>" "tinycast-dev://search?fallbackText=x"`.
- **To isolate a memory cost, add a temporary launch probe** driven by an environment variable, measure
  each call alone, and never commit it. This is how `showProgress` (+53 MB) was told apart from
  `showMessage` (+1 MB); the footprint report's "Owned physical footprint (unmapped) (graphics)" line held
  most of the spinner's cost.

## Reviewing a plan

- **Review the finished document, not only the brief.** A red team of the trust design missed two unsafe
  paths (the checksum-less address anchor and the unmounted licence image) that a review of the written
  plan caught, because the document had added cases the brief never contained.
