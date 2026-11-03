import CoreGraphics

public enum Layout {
    private static let sizeStep: CGFloat = 30
    private static let minSize = CGSize(width: 320, height: 200)

    public static func frame(for action: WindowAction, window: CGRect, screen: CGRect, gap: CGFloat, step: Int) -> CGRect? {
        let f = CGFloat([1.0 / 2, 2.0 / 3, 1.0 / 3][((step % 3) + 3) % 3])
        let t = CGFloat(1) / 3

        switch action {
        case .leftHalf: return fraction(0, 0, f, 1, screen, gap)
        case .rightHalf: return fraction(1 - f, 0, 1, 1, screen, gap)
        case .topHalf: return fraction(0, 0, 1, f, screen, gap)
        case .bottomHalf: return fraction(0, 1 - f, 1, 1, screen, gap)
        case .topLeft: return fraction(0, 0, 0.5, 0.5, screen, gap)
        case .topRight: return fraction(0.5, 0, 1, 0.5, screen, gap)
        case .bottomLeft: return fraction(0, 0.5, 0.5, 1, screen, gap)
        case .bottomRight: return fraction(0.5, 0.5, 1, 1, screen, gap)
        case .firstThird: return fraction(0, 0, t, 1, screen, gap)
        case .centerThird: return fraction(t, 0, 2 * t, 1, screen, gap)
        case .lastThird: return fraction(2 * t, 0, 1, 1, screen, gap)
        case .firstTwoThirds: return fraction(0, 0, 2 * t, 1, screen, gap)
        case .lastTwoThirds: return fraction(t, 0, 1, 1, screen, gap)
        case .maximize: return fraction(0, 0, 1, 1, screen, gap)
        case .almostMaximize: return fraction(0.05, 0.05, 0.95, 0.95, screen, 0)
        case .maximizeHeight:
            let v = fraction(0, 0, 1, 1, screen, gap)
            return CGRect(x: window.minX, y: v.minY, width: window.width, height: v.height)
        case .larger:
            return resized(window, by: sizeStep, screen: screen)
        case .smaller:
            return resized(window, by: -sizeStep, screen: screen)
        case .center:
            let size = CGSize(width: min(window.width, screen.width), height: min(window.height, screen.height))
            return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                          width: size.width, height: size.height)
        case .restore, .nextDisplay, .previousDisplay:
            return nil
        }
    }

    /// Origin for a window that ignored the requested size: keeps the edge the action hugs, then clamps into the screen.
    public static func realign(actual: CGSize, target: CGRect, screen: CGRect, action: WindowAction) -> CGPoint {
        var x = target.minX, y = target.minY
        switch action {
        case .rightHalf, .lastThird, .lastTwoThirds, .topRight, .bottomRight: x = target.maxX - actual.width
        case .center, .almostMaximize, .maximize, .centerThird: x = target.midX - actual.width / 2
        default: break
        }
        switch action {
        case .bottomHalf, .bottomLeft, .bottomRight: y = target.maxY - actual.height
        case .center, .almostMaximize, .maximize: y = target.midY - actual.height / 2
        default: break
        }
        // max last: a window larger than the screen starts at the screen's origin.
        return CGPoint(x: max(min(x, screen.maxX - actual.width), screen.minX),
                       y: max(min(y, screen.maxY - actual.height), screen.minY))
    }

    // An edge on the screen border gets the full gap; an inner edge is shared, so half each side.
    private static func fraction(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat,
                                 _ s: CGRect, _ gap: CGFloat) -> CGRect {
        func inset(_ v: CGFloat, outerAt0: Bool) -> CGFloat {
            if outerAt0 { return v <= 0 ? gap : gap / 2 }
            return v >= 1 ? gap : gap / 2
        }
        let left = s.minX + s.width * x0 + inset(x0, outerAt0: true)
        let right = s.minX + s.width * x1 - inset(x1, outerAt0: false)
        let top = s.minY + s.height * y0 + inset(y0, outerAt0: true)
        let bottom = s.minY + s.height * y1 - inset(y1, outerAt0: false)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func resized(_ w: CGRect, by delta: CGFloat, screen: CGRect) -> CGRect {
        // Never shrink below the minimum, but never grow a window that is already smaller.
        let nw = delta < 0 ? max(w.width + 2 * delta, min(w.width, minSize.width)) : min(w.width + 2 * delta, screen.width)
        let nh = delta < 0 ? max(w.height + 2 * delta, min(w.height, minSize.height)) : min(w.height + 2 * delta, screen.height)
        var x = w.midX - nw / 2
        var y = w.midY - nh / 2
        x = min(max(x, screen.minX), screen.maxX - nw)
        y = min(max(y, screen.minY), screen.maxY - nh)
        return CGRect(x: x, y: y, width: nw, height: nh)
    }
}
