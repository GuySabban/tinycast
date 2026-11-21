import AppKit
import CoreGraphics

/// Screen & System Audio Recording, which Look needs to see other apps' windows.
enum ScreenRecordingPermission {
    /// Never prompts. Stays false in the process that was just granted, until a relaunch.
    static func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts only while undecided, and adds the app to the list in System Settings.
    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    @MainActor
    static func openSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
