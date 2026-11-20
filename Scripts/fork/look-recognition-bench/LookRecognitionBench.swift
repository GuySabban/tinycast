import CoreText
import Foundation
import ImageIO
import Vision

/// Times `ClipboardTextWorker.extract(imageData:)`, helper start to text, on a 5K page or a given PNG.
@main
struct LookRecognitionBench {
    static let markers = [
        ("9 pt", "MARKER 90901", "90901", 18.0), ("11 pt", "MARKER 11011", "11011", 22.0),
        ("13 pt", "MARKER 13031", "13031", 26.0), ("11 pt Hebrew", "בדיקה עברית 22022", "עברית", 22.0)
    ]

    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let helper = arguments.first.map(URL.init(fileURLWithPath:)) else {
            print("usage: LookRecognitionBench <helper> [--runs N] [--png file]")
            exit(2)
        }
        arguments.removeFirst()
        var runs = 10
        var png: Data?
        while let flag = arguments.first {
            arguments.removeFirst()
            switch flag {
            case "--runs": runs = Int(arguments.removeFirst()) ?? runs
            case "--png": png = try Data(contentsOf: URL(fileURLWithPath: arguments.removeFirst()))
            default: print("unknown flag \(flag)"); exit(2)
            }
        }
        for level in [RecognizeTextRequest.RecognitionLevel.accurate, .fast] {
            var request = RecognizeTextRequest()
            request.recognitionLevel = level
            let languages = request.supportedRecognitionLanguages.map { $0.languageCode?.identifier ?? "?" }
            print("\(level == .accurate ? "accurate" : "fast") languages: \(languages.joined(separator: " "))")
        }
        let page = png ?? testPage()
        print("helper \(helper.lastPathComponent), \(page.count) PNG bytes, \(png == nil ? "5K test page" : "given PNG")")
        var times: [Double] = []
        var text = ""
        for _ in 0..<runs {
            let start = ContinuousClock.now
            text = try await ClipboardTextWorker.extract(imageData: page, executable: helper, timeout: .seconds(60))
            let elapsed = ContinuousClock.now - start
            times.append(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
        times.sort()
        let median = times[times.count / 2]
        let p95 = times[min(times.count - 1, Int((Double(times.count) * 0.95).rounded(.up)) - 1)]
        print(String(format: "runs %d  median %.3f s  p95 %.3f s  min %.3f s  max %.3f s  (target: 1 s median)",
                     runs, median, p95, times.first!, times.last!))
        print("text \(text.utf8.count) bytes, \(text.split(separator: "\n").count) lines")
        if png == nil {
            for (label, marker, key, _) in markers {
                let line = text.split(separator: "\n").first { $0.contains(key) }.map { "\"\($0)\"" }
                print("  \(label): \(line == nil ? "MISSED" : "read") (drawn \"\(marker)\", read \(line ?? "nothing"))")
            }
        }
    }

    /// A busy 5120 × 2880 screen at scale 2: two columns of 11 pt body text and one marker per size.
    static func testPage() -> Data {
        let width = 5120, height = 2880
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for column in 0..<2 {
            for row in 0..<70 {
                draw(bodyLine(column * 70 + row), in: context, size: 22,
                     at: CGPoint(x: 120 + column * 2520, y: 2600 - row * 34))
            }
        }
        for (index, marker) in markers.enumerated() {
            draw(marker.1, in: context, size: marker.3, at: CGPoint(x: 120 + index * 1250, y: 2760))
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// Varied lines, as a real screen has: Vision's `.accurate` drops lines that repeat one another.
    static func bodyLine(_ index: Int) -> String {
        let words = [
            "meeting", "design", "review", "invoice", "shipping", "Thursday", "account", "budget", "launch",
            "calendar", "address", "server", "deadline", "contract", "update", "travel", "report", "welcome",
            "library", "window", "garden", "station", "window", "number", "message", "summary", "planning"
        ]
        let picked = (0..<11).map { words[(index * 7 + $0 * 5 + $0 * $0) % words.count] }
        return "\(index + 1). " + picked.joined(separator: " ") + " at \(index % 12 + 1):\(index % 6)0 pm, room \(index)B"
    }

    static func draw(_ text: String, in context: CGContext, size: Double, at origin: CGPoint) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        context.textPosition = origin
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
}
