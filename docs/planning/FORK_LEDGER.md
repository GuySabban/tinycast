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

`Tinycast.xcodeproj/project.pbxproj` is regenerated from `project.yml` by `xcodegen generate` and is
never edited by hand.

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
