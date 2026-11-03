import CoreGraphics

public struct CycleTracker {
    private struct Entry { var action: WindowAction; var window: UInt32; var result: CGRect; var step: Int }
    private var last: Entry?
    private var pending: (action: WindowAction, window: UInt32, step: Int)?

    public init() {}

    public mutating func step(for action: WindowAction, window: UInt32, current: CGRect) -> Int {
        var n = 0
        if action.cycles, let l = last, l.action == action, l.window == window,
           approximatelyEqual(l.result, current) {
            n = (l.step + 1) % 3
        }
        pending = (action, window, n)
        return n
    }

    public mutating func record(_ action: WindowAction, window: UInt32, result: CGRect) {
        var n = 0
        if let p = pending, p.action == action, p.window == window { n = p.step }
        last = Entry(action: action, window: window, result: result, step: n)
        pending = nil
    }
}
