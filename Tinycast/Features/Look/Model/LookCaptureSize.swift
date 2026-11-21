import Foundation

/// The capture's pixel size: the display's own, long side capped (`LOOK.md` 3.4).
enum LookCaptureSize {
    static let maximumLongSide = 4096

    static func pixels(width: Int, height: Int, scale: Double) -> (width: Int, height: Int) {
        var w = Double(width) * scale
        var h = Double(height) * scale
        let longSide = max(w, h)
        if longSide > Double(maximumLongSide) {
            w *= Double(maximumLongSide) / longSide
            h *= Double(maximumLongSide) / longSide
        }
        return (max(1, Int(w.rounded())), max(1, Int(h.rounded())))
    }
}
