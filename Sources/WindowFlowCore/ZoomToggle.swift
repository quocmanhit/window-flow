import CoreGraphics

public enum ZoomStep: Equatable, Sendable {
    case maximize
    case restore(CGRect)
    /// Already maximized by something else: fall back to the frame before the first WindowFlow action.
    case restoreOriginal
}

/// Maximize / restore size, like double-clicking a title bar: each window remembers its frame from before the zoom.
public struct ZoomToggle {
    private var before: [UInt32: CGRect] = [:]
    private var zoomed: [UInt32: CGRect] = [:]

    public init() {}

    /// `maximized` is the maximize target on the window's display. A window still at the frame its last zoom left it
    /// in counts as maximized too, so an app that refused the full size can still be zoomed back.
    public mutating func step(window: UInt32, current: CGRect, maximized: CGRect) -> ZoomStep {
        let isZoomed = approximatelyEqual(current, maximized) || zoomed[window].map { approximatelyEqual($0, current) } == true
        guard isZoomed else {
            before[window] = current
            zoomed[window] = nil
            return .maximize
        }
        zoomed[window] = nil
        return before.removeValue(forKey: window).map(ZoomStep.restore) ?? .restoreOriginal
    }

    public mutating func didZoom(window: UInt32, to frame: CGRect) { zoomed[window] = frame }

    public mutating func forget(window: UInt32) {
        before[window] = nil
        zoomed[window] = nil
    }
}
