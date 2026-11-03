public struct SwitcherSelection {
    public private(set) var index: Int?
    private let count: Int

    /// `start` is the first pick: 1 skips the current window, 0 keeps it (when the focused window is not in the list).
    public init(count: Int, start: Int = 1) {
        self.count = count
        index = count == 0 ? nil : min(start, count - 1)
    }

    public mutating func next() {
        guard let i = index else { return }
        index = (i + 1) % count
    }

    public mutating func previous() {
        guard let i = index else { return }
        index = (i - 1 + count) % count
    }
}
