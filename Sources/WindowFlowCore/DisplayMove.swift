import CoreGraphics

public enum DisplayMove {
    public static func order(_ screens: [CGRect]) -> [Int] {
        screens.indices.sorted {
            let a = screens[$0], b = screens[$1]
            return a.minX != b.minX ? a.minX < b.minX : a.minY < b.minY
        }
    }

    public static func target(from: Int, count: Int, forward: Bool) -> Int {
        guard count > 0 else { return 0 }
        return ((from + (forward ? 1 : -1)) % count + count) % count
    }

    public static func frame(window: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return window }
        let w = min(window.width / from.width * to.width, to.width)
        let h = min(window.height / from.height * to.height, to.height)
        let x = to.minX + (window.minX - from.minX) / from.width * to.width
        let y = to.minY + (window.minY - from.minY) / from.height * to.height
        // Clamp so the whole window stays inside the target, even if it hung off the source.
        return CGRect(x: min(max(x, to.minX), to.maxX - w), y: min(max(y, to.minY), to.maxY - h),
                      width: w, height: h)
    }
}
