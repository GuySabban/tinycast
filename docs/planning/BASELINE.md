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

## Trial merge

Not yet run. It is Phase 0 step 6 and is written up here when done.
