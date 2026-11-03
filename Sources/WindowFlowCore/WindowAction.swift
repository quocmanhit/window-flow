public enum WindowAction: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case maximize, almostMaximize, maximizeHeight, toggleMaximize
    case larger, smaller, center
    case restore, nextDisplay, previousDisplay

    public var cycles: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return true
        default: return false
        }
    }
}
