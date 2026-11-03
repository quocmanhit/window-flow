import CoreGraphics

public struct RestoreStore {
    private var saved: [UInt32: CGRect] = [:]
    private var applied: [UInt32: CGRect] = [:]

    public init() {}

    public mutating func willApply(window: UInt32, current: CGRect) {
        if saved[window] != nil, let a = applied[window], approximatelyEqual(a, current) { return }
        saved[window] = current
    }

    public mutating func lastApplied(window: UInt32, frame: CGRect) {
        applied[window] = frame
    }

    public mutating func takeRestore(window: UInt32) -> CGRect? {
        applied[window] = nil
        return saved.removeValue(forKey: window)
    }

    public mutating func forget(window: UInt32) {
        saved[window] = nil
        applied[window] = nil
    }
}
