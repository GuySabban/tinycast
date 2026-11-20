import AppKit

@main
@MainActor
struct StagedImageClipboardTests {
    static var failures = 0

    static func main() async throws {
        try await run()
        if failures > 0 { exit(1) }
        print("Staged image clipboard checks passed")
    }

    static func run() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let scratch = home.appendingPathComponent(".tinycast-clipboard-tests-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = "test.tinycast.staged-image.\(UUID())"
        let container = home.appendingPathComponent("Library/Containers/\(source)/Data/tmp")
        let durable = scratch.appendingPathComponent("photo.jpg")
        let store = ClipboardStore(directory: scratch)
        defer { store.close() }
        let manager = ClipboardManager(store: store, settings: AppSettings())

        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        let png = bitmap.representation(using: .png, properties: [:])!
        let tiff = bitmap.tiffRepresentation!
        try png.write(to: durable)

        for (type, bytes) in [(NSPasteboard.PasteboardType.png, png), (.tiff, tiff)] {
            let staged = container.appendingPathComponent("photo-\(type.rawValue).jpg")
            try await expectImage(in: store, source: source, "staged file URL, \(type.rawValue) and filename") {
                capture(manager, source: source, file: staged, text: staged.lastPathComponent, image: (type, bytes))
            }
        }

        let staged = container.appendingPathComponent(durable.lastPathComponent)
        let filename = staged.lastPathComponent
        try await expectImage(in: store, source: source, "staged filename with trailing whitespace") {
            capture(manager, source: source, file: staged, text: filename + " \t\n", image: (.png, png))
        }
        try await expectImage(in: store, source: source, "pixels with whitespace-only text") {
            capture(manager, source: source, text: " \t\n", image: (.png, png))
        }

        let caption = filename + " is the original"
        capture(manager, source: source, file: staged, text: caption, image: (.png, png))
        expect(store.items.first?.text == caption, "caption starting with the staged filename stays text")

        capture(manager, source: "test.tinycast.other-app", file: staged, text: filename, image: (.png, png))
        expect(store.items.first?.text == filename, "another app's container URL does not displace text")

        capture(manager, source: source, text: "Another caption", image: (.png, png))
        expect(store.items.first?.text == "Another caption", "text beside pixels without a staged file stays text")

        let finder = "com.apple.finder"
        capture(manager, source: finder, file: durable, text: filename, image: (.png, png))
        expect(
            store.items.first?.kind == .file && store.items.first?.text == durable.path
                && store.items.first?.sourceBundleID == finder,
            "a Finder file URL still wins over both pixels and its filename")
    }

    static func expectImage(
        in store: ClipboardStore, source: String, _ message: String, after capture: () -> Void
    ) async throws {
        let id = store.items.first?.id
        let before = store.items.count
        capture()
        for _ in 0..<200 {
            if store.items.first?.id != id { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let item = store.items.first
        let saved = item?.imagePath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        let image = saved.flatMap(NSBitmapImageRep.init(data:))
        let outcome = item.map { String(describing: $0.kind) } ?? "no row"
        expect(
            store.items.count == before + 1 && item?.kind == .image && item?.sourceBundleID == source
                && image?.pixelsWide == 2 && image?.pixelsHigh == 2,
            "\(message) must record one image, got \(outcome)")
    }

    static func capture(
        _ manager: ClipboardManager, source: String, file: URL? = nil, text: String,
        image: (NSPasteboard.PasteboardType, Data)
    ) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        if let file { item.setData(file.dataRepresentation, forType: .fileURL) }
        item.setString(text, forType: .string)
        item.setData(image.1, forType: image.0)
        precondition(board.writeObjects([item]))
        manager.capture(on: board, sourceBundleID: source)
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}

@MainActor
final class AppSettings {
    var clipboardDisabledApps: Set<String> = []
}
