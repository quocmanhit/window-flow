public enum SwitcherOrdering {
    /// Windows with a recency record first; the rest follow in on-screen front-to-back order, then input order.
    public static func order(_ ids: [UInt32], mru: MRUList, zOrder: [UInt32]) -> [UInt32] {
        var rank: [UInt32: Int] = [:]
        for (position, id) in zOrder.enumerated() where rank[id] == nil { rank[id] = position }
        let byDepth = ids.enumerated().sorted { a, b in
            let ra = rank[a.element] ?? Int.max, rb = rank[b.element] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        return mru.order(byDepth)
    }
}
