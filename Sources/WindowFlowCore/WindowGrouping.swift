import CoreGraphics

public struct GroupCandidate: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let space: Int
    /// Switcher position, 0 = most recent.
    public let order: Int

    public init(id: UInt32, frame: CGRect, space: Int, order: Int) {
        self.id = id
        self.frame = frame
        self.space = space
        self.order = order
    }
}

public enum WindowGrouping {
    static let maxMembers = 4
    static let maxCandidates = 12
    static let minCoverage: CGFloat = 0.9

    /// Windows that together tile one display on one Space. `screens` are visible frames in CG coordinates and
    /// `tolerance` absorbs gaps and rounding. Each group lists its ids in reading order (top to bottom, then left to right).
    public static func groups(_ windows: [GroupCandidate], screens: [CGRect], tolerance: CGFloat) -> [[UInt32]] {
        var buckets: [[Int]: [GroupCandidate]] = [:]
        for window in windows {
            guard let screen = screenIndex(of: window.frame, in: screens) else { continue }
            buckets[[screen, window.space], default: []].append(window)
        }
        var result: [(first: Int, ids: [UInt32])] = []
        for (key, candidates) in buckets {
            let screen = screens[key[0]]
            let fitting = candidates.sorted { $0.order < $1.order }
                .filter { touchesEdge($0.frame, of: screen, tolerance: tolerance) }
            guard let chosen = best(Array(fitting.prefix(maxCandidates)), screen: screen, tolerance: tolerance) else { continue }
            result.append((chosen[0].order, readingOrder(chosen, tolerance: tolerance).map(\.id)))
        }
        return result.sorted { $0.first < $1.first }.map(\.ids)
    }

    // Every subset of 2-4 candidates is tried, so a window that does not belong cannot hide a pair. The valid
    // subset whose most recent member ranks highest wins; ties go to more members, then to more coverage.
    private static func best(_ candidates: [GroupCandidate], screen: CGRect, tolerance: CGFloat) -> [GroupCandidate]? {
        var best: (members: [GroupCandidate], coverage: CGFloat)?
        func better(_ members: [GroupCandidate], _ coverage: CGFloat) -> Bool {
            guard let current = best else { return true }
            if members[0].order != current.members[0].order { return members[0].order < current.members[0].order }
            if members.count != current.members.count { return members.count > current.members.count }
            return coverage > current.coverage
        }
        func extend(_ chosen: [GroupCandidate], from start: Int) {
            if chosen.count >= 2 {
                let covered = coverage(chosen.map(\.frame), of: screen, tolerance: tolerance)
                if covered >= minCoverage, better(chosen, covered) { best = (chosen, covered) }
            }
            guard chosen.count < maxMembers else { return }
            for index in start..<candidates.count
            where chosen.allSatisfy({ !overlaps($0.frame, candidates[index].frame, tolerance: tolerance) }) {
                extend(chosen + [candidates[index]], from: index + 1)
            }
        }
        extend([], from: 0)
        return best?.members
    }

    // Rows first (minY within tolerance of the row's first window), then left to right inside each row.
    private static func readingOrder(_ members: [GroupCandidate], tolerance: CGFloat) -> [GroupCandidate] {
        var rows: [[GroupCandidate]] = []
        for window in members.sorted(by: { $0.frame.minY < $1.frame.minY }) {
            if let top = rows.last?.first, window.frame.minY - top.frame.minY <= tolerance {
                rows[rows.count - 1].append(window)
            } else {
                rows.append([window])
            }
        }
        return rows.flatMap { $0.sorted { $0.frame.minX < $1.frame.minX } }
    }

    private static func screenIndex(of frame: CGRect, in screens: [CGRect]) -> Int? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let hit = screens.firstIndex(where: { $0.contains(center) }) { return hit }
        let overlaps = screens.map { area($0.intersection(frame)) }
        guard let best = overlaps.max(), best > 0 else { return nil }
        return overlaps.firstIndex(of: best)
    }

    private static func touchesEdge(_ frame: CGRect, of screen: CGRect, tolerance: CGFloat) -> Bool {
        abs(frame.minX - screen.minX) <= tolerance || abs(frame.maxX - screen.maxX) <= tolerance
            || abs(frame.minY - screen.minY) <= tolerance || abs(frame.maxY - screen.maxY) <= tolerance
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        let shared = a.intersection(b)
        return !shared.isNull && min(shared.width, shared.height) > tolerance
    }

    // Frames grow by half the tolerance so the gap between tiles does not count as uncovered.
    private static func coverage(_ frames: [CGRect], of screen: CGRect, tolerance: CGFloat) -> CGFloat {
        let covered = frames.reduce(CGFloat(0)) { $0 + area(screen.intersection($1.insetBy(dx: -tolerance / 2, dy: -tolerance / 2))) }
        return covered / area(screen)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}

public enum GroupTitle {
    /// App names in reading order, deduped; when every member is the same app, their window titles instead.
    public static func make(_ members: [(app: String, title: String)]) -> String {
        let apps = members.reduce(into: [String]()) { if !$1.app.isEmpty, !$0.contains($1.app) { $0.append($1.app) } }
        guard apps.count <= 1 else { return apps.joined(separator: " + ") }
        let titles = members.map { $0.title.isEmpty ? $0.app : $0.title }
        return titles.joined(separator: " + ")
    }
}
