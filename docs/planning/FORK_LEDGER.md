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

`Tinycast.xcodeproj/project.pbxproj` is regenerated from `project.yml` by `xcodegen generate` and is
never edited by hand.

## Upstream doc errata

Upstream docs the fork knows are wrong. They are left unedited to keep merges clean.

- **`docs/signing.md` section 1:** with OpenSSL 3 or later (Homebrew installs 4.x), `security import`
  rejects the `.p12` with "MAC verification failed during PKCS12 import". Add `-legacy` to the
  `openssl pkcs12 -export` line. The owner's key is backed up in `~/Signing/`: the legacy-format
  `launcher-signing-legacy.p12` is the one to import. See `BASELINE.md`.
