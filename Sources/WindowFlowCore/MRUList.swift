public struct MRUList {
    private var recent: [UInt32] = []

    public init() {}

    public mutating func touch(_ id: UInt32) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
    }

    public mutating func remove(_ id: UInt32) {
        recent.removeAll { $0 == id }
    }

    public func order(_ ids: [UInt32]) -> [UInt32] {
        let present = Set(ids)
        let known = recent.filter { present.contains($0) }
        let knownSet = Set(known)
        return known + ids.filter { !knownSet.contains($0) }
    }
}
