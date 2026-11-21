import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// One still of a display, in memory only, with every window of this app left out.
enum ScreenCapturer {
    enum Failure: Error { case noDisplay, encoding }

    @MainActor
    static func displayUnderPointer() -> CGDirectDisplayID? {
        NSScreen.underCursor?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    static func capture(display displayID: CGDirectDisplayID) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Failure.noDisplay
        }
        // By application, not by window: the palette, its menu, HUDs and dialogs all leave at once.
        let own = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let size = LookCaptureSize.pixels(
            width: display.width, height: display.height, scale: Double(filter.pointPixelScale))
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// The helper's input; never written anywhere but its standard input.
    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.encoding }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encoding }
        return data as Data
    }
}
