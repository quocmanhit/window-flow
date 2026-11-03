import AppKit
import ApplicationServices
import WindowFlowCore

struct WindowEntry {
    let id: UInt32
    let pid: pid_t
    let element: AXUIElement
    let appName: String
    var title: String
    var isMinimized: Bool
}

/// One tile of the switcher: a single window, or windows that tile a display together.
struct SwitcherItem {
    /// Reading order: top to bottom, then left to right.
    let members: [WindowEntry]
    /// Least recent first; the last one is focused last so it ends up with the keyboard.
    let focusOrder: [WindowEntry]
    let title: String

    var primary: WindowEntry { focusOrder[focusOrder.count - 1] }
    var isGroup: Bool { members.count > 1 }

    init(_ entry: WindowEntry) {
        members = [entry]
        focusOrder = [entry]
        title = entry.title.isEmpty ? entry.appName : entry.title
    }

    init(members: [WindowEntry], focusOrder: [WindowEntry]) {
        self.members = members
        self.focusOrder = focusOrder
        title = GroupTitle.make(members.map { ($0.appName, $0.title) })
    }
}

/// Event-driven cache of switchable windows. Mutable state is main-thread only; the background queue only
/// reads AX and hands results back to main.
final class WindowCatalog {
    private struct App {
        let name: String
        let element: AXUIElement
        let observer: AXObserver
        var windows: [UInt32: AXUIElement] = [:]
        var titles: [UInt32: String] = [:]
        var minimized: [UInt32: Bool] = [:]
        var scan = ScanState.pending
        var scanAttempts = 0
        // Where a capped scan resumes, and element ids whose probe timed out and must be probed again.
        var scanNext = 0
        var scanRetry: [Int] = []
    }

    // pending: not scanned, or the last attempt could not finish; running: a job is in flight; done: scan completed.
    private enum ScanState { case pending, running, done }
    private enum ScanOutcome { case complete, unreachable, capped }
    private struct ScanResult {
        var found: [Found] = []
        var outcome = ScanOutcome.complete
        var next = 0
        var retry: [Int] = []
    }
    private enum Refresh { case ok, dead, timedOut }

    // Snapshot reads run on main on every switcher open, so a hung app may cost this much per window, not axTimeout.
    private static let snapshotTimeout: Float = 0.15
    private static let scanElementTimeout: Float = 0.05
    private static let scanBudget: TimeInterval = 2

    private struct Found {
        let id: UInt32
        let element: AXUIElement
    }

    private enum Inspection {
        case window(Found)
        case notWindow
        case unreachable
    }

    private let settings: Settings
    private let windowManager: WindowManager
    private var apps: [pid_t: App] = [:]
    private var mru = MRUList()
    private var held: (ids: Set<UInt32>, until: Date)?
    private var started = false
    // Apps whose AX reads timed out; they keep cached titles until an AX notification or activation shows life.
    private var unresponsive = Set<pid_t>()
    // Serial so only one app is scanned at a time; AX calls to a slow app never run on main or the tap thread.
    private let scanQueue = DispatchQueue(label: "WindowFlow.RemoteScan", qos: .utility)

    init(settings: Settings, windowManager: WindowManager) {
        self.settings = settings
        self.windowManager = windowManager
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        func app(_ note: Notification) -> NSRunningApplication? {
            note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        }
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] in
            if let running = app($0) { self?.track(running) }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] in
            if let running = app($0) { self?.activated(running) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] in
            if let running = app($0) { self?.untrack(pid: running.processIdentifier) }
        }
        for running in NSWorkspace.shared.runningApplications { track(running) }
        if let front = NSWorkspace.shared.frontmostApplication { touchFocused(pid: front.processIdentifier) }
    }

    /// Call when a setting changed: turning "all Spaces" on scans the apps that were not scanned yet.
    func settingsChanged() {
        guard started else { return }
        for pid in apps.keys { discover(pid: pid, ax: false) }
    }

    /// What the frontmost app says has focus. An app that does not answer is treated as focused on its first window;
    /// one that answered with no focused window, or an untracked one, as focused on none.
    private enum Focus {
        case window(UInt32)
        case unreachable(pid_t)
        case none

        func includes(_ members: [WindowEntry]) -> Bool {
            switch self {
            case .window(let id): members.contains { $0.id == id }
            case .unreachable(let pid): members.contains { $0.pid == pid }
            case .none: false
            }
        }
    }

    /// WindowFlow's own titled windows (Settings). They are read through AppKit: Accessibility calls into our own
    /// process from the main thread would block on the main thread itself.
    static func ownWindows() -> [NSWindow] {
        NSApp.windows.filter { !($0 is NSPanel) && $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized) }
    }

    // windowNumber is -1 for a window that has never been on screen, so every conversion must be checked.
    func ownWindowBecameKey(_ window: NSWindow) {
        if let id = UInt32(exactly: window.windowNumber), id != 0 { mru.touch(id) }
    }

    private func currentFocus() -> Focus {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
            return NSApp.keyWindow.flatMap { UInt32(exactly: $0.windowNumber) }.map { .window($0) } ?? .none
        }
        guard let front = NSWorkspace.shared.frontmostApplication, apps[front.processIdentifier] != nil else { return .none }
        let pid = front.processIdentifier
        if unresponsive.contains(pid) { return .unreachable(pid) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.snapshotTimeout)
        switch read(app, kAXFocusedWindowAttribute) {
        case .value(let value):
            guard CFGetTypeID(value) == AXUIElementGetTypeID(), let id = realWindowID(value as! AXUIElement) else { return .none }
            return .window(id)
        case .error(.noValue): return .none
        case .error: return .unreachable(pid)
        }
    }

    /// Only the primary window counts as used; the other members keep their place, so a quick tap returns to the previous
    /// window. Their brief activation while the group comes forward is ignored for that reason.
    func touch(_ item: SwitcherItem) {
        mru.touch(item.primary.id)
        let others = Set(item.focusOrder.dropLast().map(\.id))
        held = others.isEmpty ? nil : (others, Date().addingTimeInterval(WindowFocus.groupStep * Double(others.count) + 0.5))
    }

    private func isHeld(_ id: UInt32) -> Bool {
        guard let held, Date() < held.until else { return false }
        return held.ids.contains(id)
    }

    /// `focusedFirst`: the first item contains the window that has focus now, so a quick tap should skip it.
    func snapshot() -> (items: [SwitcherItem], focusedFirst: Bool) {
        let includeMinimized = settings.includeMinimized, allSpaces = settings.allSpaces
        let list = windowList()
        let visible = Set(list.zOrder)
        var dead: [(pid_t, UInt32)] = []
        var entries: [UInt32: WindowEntry] = [:]

        for pid in apps.keys.sorted() {
            guard let app = apps[pid] else { continue }
            let hidden = NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
            for id in app.windows.keys.sorted() {
                let element = app.windows[id]!
                var title = app.titles[id] ?? "", minimized = app.minimized[id] ?? false
                if !unresponsive.contains(pid) {
                    switch refresh(element, title: &title, minimized: &minimized) {
                    case .ok:
                        apps[pid]?.titles[id] = title
                        apps[pid]?.minimized[id] = minimized
                    case .dead:
                        dead.append((pid, id))
                        continue
                    case .timedOut:
                        unresponsive.insert(pid)
                    }
                }
                if minimized && !includeMinimized { continue }
                // The scan also finds closed-but-retained windows; a live one has a window-server entry unless minimized.
                if !minimized, let existing = list.existing, !existing.contains(id) { continue }
                if !allSpaces && !minimized && !hidden && list.existing != nil && !visible.contains(id) { continue }
                entries[id] = WindowEntry(id: id, pid: pid, element: element, appName: app.name, title: title, isMinimized: minimized)
            }
        }
        for (pid, id) in dead { remove(id: id, pid: pid) }
        for window in Self.ownWindows() {
            guard let id = UInt32(exactly: window.windowNumber), id != 0 else { continue }
            let minimized = window.isMiniaturized
            if minimized && !includeMinimized { continue }
            if !allSpaces && !minimized && !window.isOnActiveSpace { continue }
            entries[id] = WindowEntry(id: id, pid: getpid(), element: AXUIElementCreateApplication(getpid()),
                                      appName: "WindowFlow", title: window.title, isMinimized: minimized)
        }
        let ordered = SwitcherOrdering.order(Array(entries.keys.sorted()), mru: mru, zOrder: list.zOrder).compactMap { entries[$0] }
        let focus = currentFocus()
        let items = items(from: ordered, list: list, focus: focus)
        return (items, items.first.map { focus.includes($0.members) } ?? false)
    }

    // Groups are recomputed on every open from the window server's frames; nothing about them is stored.
    // The group holding the focused window is left expanded, so Alt-Tab can move between its members.
    private func items(from ordered: [WindowEntry], list: WindowList, focus: Focus) -> [SwitcherItem] {
        guard list.existing != nil else { return ordered.map(SwitcherItem.init) }
        let connection = PrivateAPI.mainConnectionID?()
        let onScreen = Set(list.zOrder)
        let candidates = ordered.enumerated().compactMap { position, entry -> GroupCandidate? in
            guard !entry.isMinimized, let frame = list.bounds[entry.id],
                  let space = space(of: entry.id, connection: connection, onScreen: onScreen) else { return nil }
            return GroupCandidate(id: entry.id, frame: frame, space: space, order: position)
        }
        let groups = WindowGrouping.groups(candidates, screens: Screens.visibleFrames().map(\.visible),
                                           tolerance: 8 + CGFloat(settings.gap))
        let position = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        var byLeader: [UInt32: SwitcherItem] = [:]
        var grouped = Set<UInt32>()
        for ids in groups {
            let members = ids.compactMap { id in position[id].map { ordered[$0] } }
            guard members.count == ids.count, !focus.includes(members), let leader = members.min(by: { position[$0.id]! < position[$1.id]! }) else { continue }
            byLeader[leader.id] = SwitcherItem(members: members, focusOrder: members.sorted { position[$0.id]! > position[$1.id]! })
            grouped.formUnion(ids)
        }
        return ordered.compactMap { byLeader[$0.id] ?? (grouped.contains($0.id) ? nil : SwitcherItem($0)) }
    }

    // A window on exactly one Space has that Space; without the private call only windows on screen now qualify.
    private func space(of id: UInt32, connection: Int32?, onScreen: Set<UInt32>) -> Int? {
        guard let copy = PrivateAPI.copySpacesForWindows, let connection else { return onScreen.contains(id) ? 0 : nil }
        guard let spaces = copy(connection, 0x7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber],
              spaces.count == 1 else { return nil }
        return spaces[0].intValue
    }

    // Title and minimized state are read independently; only a dead element or a timeout stops the refresh.
    private func refresh(_ element: AXUIElement, title: inout String, minimized: inout Bool) -> Refresh {
        AXUIElementSetMessagingTimeout(element, Self.snapshotTimeout)
        defer { AXUIElementSetMessagingTimeout(element, WindowManager.axTimeout) }
        switch read(element, kAXTitleAttribute) {
        case .value(let value): title = value as? String ?? ""
        case .error(.invalidUIElement): return .dead
        case .error(.cannotComplete): return .timedOut
        case .error: break
        }
        switch read(element, kAXMinimizedAttribute) {
        case .value(let value): minimized = (value as? Bool) == true
        case .error(.invalidUIElement): return .dead
        case .error(.cannotComplete): return .timedOut
        case .error: minimized = false
        }
        return .ok
    }

    // MARK: Tracking apps

    private func track(_ running: NSRunningApplication, attempt: Int = 0) {
        let pid = running.processIdentifier
        guard started, running.activationPolicy == .regular, pid != getpid(), !running.isTerminated, apps[pid] == nil else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, WindowManager.axTimeout)
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let ready = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon) == .success
        // A freshly launched app may not answer AX yet; retry a few times, then settle for scanning only.
        if !ready, attempt < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.track(running, attempt: attempt + 1) }
            return
        }
        AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        apps[pid] = App(name: running.localizedName ?? "", element: element, observer: observer)
        discover(pid: pid, ax: true)
    }

    private func untrack(pid: pid_t) {
        unresponsive.remove(pid)
        guard let app = apps.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(app.observer), .commonModes)
        for id in app.windows.keys {
            mru.remove(id)
            windowManager.forget(window: id)
        }
    }

    private func activated(_ running: NSRunningApplication) {
        track(running)
        unresponsive.remove(running.processIdentifier)
        discover(pid: running.processIdentifier, ax: false)
        touchFocused(pid: running.processIdentifier)
    }

    private func touchFocused(pid: pid_t) {
        guard let app = apps[pid], case .value(let value) = read(app.element, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return }
        focused(value as! AXUIElement, pid: pid)
    }

    private func focused(_ element: AXUIElement, pid: pid_t, touch: Bool = true) {
        guard apps[pid] != nil else { return }
        if case .window(let found) = inspect(element) {
            register(found, pid: pid)
            if touch && !isHeld(found.id) { mru.touch(found.id) }
        }
    }

    // MARK: Discovery

    // `ax` also reads kAXWindowsAttribute (current Space). The remote-token scan covers every Space and runs
    // until it completes once; an app that is not answering yet stays pending and is retried on activation or any AX event.
    private func discover(pid: pid_t, ax: Bool) {
        guard let app = apps[pid] else { return }
        let canScan = settings.allSpaces && PrivateAPI.axCreateWithRemoteToken != nil && PrivateAPI.axGetWindow != nil
        let scan = canScan && app.scan == .pending && app.scanAttempts < 3
        guard ax || scan else { return }
        if scan { apps[pid]?.scan = .running }
        let element = app.element, resume = (app.scanNext, app.scanRetry)
        scanQueue.async { [weak self] in
            guard let self else { return }
            var found: [Found] = []
            var result = ScanResult()
            if ax { found += self.axWindows(of: element) }
            if scan {
                result = self.remoteWindows(pid: pid, app: element, from: resume.0, retry: resume.1)
                found += result.found
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.apps[pid] != nil else { return }
                for window in found { self.register(window, pid: pid) }
                guard scan else { return }
                self.apps[pid]?.scan = result.outcome == .complete ? .done : .pending
                if result.outcome != .unreachable { self.apps[pid]?.scanNext = result.next; self.apps[pid]?.scanRetry = result.retry }
                if result.outcome == .capped { self.apps[pid]?.scanAttempts += 1 }
            }
        }
    }

    private func axWindows(of app: AXUIElement) -> [Found] {
        guard case .value(let value) = read(app, kAXWindowsAttribute), let list = value as? [AXUIElement] else { return [] }
        return list.compactMap { if case .window(let found) = inspect($0) { found } else { nil } }
    }

    // Element ids are small per-process integers, so probing 0..<1000 reaches windows on other Spaces.
    // A probe that times out is remembered and redone, and a scan that ran out of budget resumes where it stopped.
    private func remoteWindows(pid: pid_t, app: AXUIElement, from start: Int, retry: [Int]) -> ScanResult {
        guard let create = PrivateAPI.axCreateWithRemoteToken else { return ScanResult(outcome: .unreachable) }
        if case .error(.cannotComplete) = read(app, kAXRoleAttribute) { return ScanResult(outcome: .unreachable) }
        var result = ScanResult()
        let deadline = Date().addingTimeInterval(Self.scanBudget)
        let ids = retry + Array(start..<1000)
        for (position, elementID) in ids.enumerated() {
            if Date() > deadline {
                // Retry ids not reached yet stay queued; the range part resumes at the first id not reached.
                let rest = ids[position...]
                result.retry += rest.filter { $0 < start || retry.contains($0) }
                result.next = max(start, rest.first { !retry.contains($0) } ?? 1000)
                result.outcome = .capped
                return result
            }
            let token = Data(RemoteToken.bytes(pid: pid, elementID: UInt64(elementID)))
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            switch inspect(element, timeout: Self.scanElementTimeout) {
            case .window(let window): result.found.append(window)
            case .unreachable: result.retry.append(elementID)
            case .notWindow: break
            }
        }
        result.next = 1000
        if !result.retry.isEmpty { result.outcome = .capped }
        return result
    }

    // Safe on any thread: reads AX only. Every element gets a timeout before its first read, and a kept one is
    // back at axTimeout.
    private func inspect(_ element: AXUIElement, timeout: Float = WindowManager.axTimeout) -> Inspection {
        AXUIElementSetMessagingTimeout(element, timeout)
        switch read(element, kAXSubroleAttribute) {
        case .error(.cannotComplete): return .unreachable
        case .error: return .notWindow
        case .value(let value):
            guard let subrole = value as? String, subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
                  case .value(let sizeValue) = read(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return .notWindow }
            var size = CGSize.zero
            guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width >= 50, size.height >= 50,
                  let id = realWindowID(element) else { return .notWindow }
            AXUIElementSetMessagingTimeout(element, WindowManager.axTimeout)
            return .window(Found(id: id, element: element))
        }
    }

    private func register(_ found: Found, pid: pid_t) {
        guard let app = apps[pid], app.windows[found.id] == nil else { return }
        apps[pid]?.windows[found.id] = found.element
        AXObserverAddNotification(app.observer, found.element, kAXUIElementDestroyedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }

    private func remove(id: UInt32, pid: pid_t) {
        apps[pid]?.windows[id] = nil
        apps[pid]?.titles[id] = nil
        apps[pid]?.minimized[id] = nil
        mru.remove(id)
        windowManager.forget(window: id)
    }

    // MARK: Observer

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        Unmanaged<WindowCatalog>.fromOpaque(refcon).takeUnretainedValue().notified(element, notification as String)
    }

    private func notified(_ element: AXUIElement, _ name: String) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return }
        unresponsive.remove(pid)
        discover(pid: pid, ax: false)
        switch name {
        case kAXWindowCreatedNotification:
            added(element, pid: pid, retry: true)
        case kAXFocusedWindowChangedNotification:
            // A focus change inside a background app (for example a raised group member) is not user focus.
            focused(element, pid: pid, touch: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid)
        case kAXUIElementDestroyedNotification:
            guard let id = apps[pid]?.windows.first(where: { CFEqual($0.value, element) })?.key else { return }
            remove(id: id, pid: pid)
        default:
            break
        }
    }

    // A window announced at creation often has no subrole or size yet; look once more shortly after.
    private func added(_ element: AXUIElement, pid: pid_t, retry: Bool) {
        guard apps[pid] != nil else { return }
        if case .window(let found) = inspect(element) {
            register(found, pid: pid)
        } else if retry {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.added(element, pid: pid, retry: false) }
        }
    }

    // MARK: Helpers

    private func read(_ element: AXUIElement, _ name: String) -> AXRead {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if error == .success, let value { return .value(value) }
        return .error(error == .success ? .noValue : error)
    }

    // With the private symbol, an element without a real window id is not a window. The CFHash fallback
    // only exists so the catalog still works without the symbol.
    private func realWindowID(_ element: AXUIElement) -> UInt32? {
        guard let getWindow = PrivateAPI.axGetWindow else { return windowManager.windowID(element) }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success && id != 0 ? id : nil
    }

    // One window-server query: layer-0 on-screen windows front to back, every id that exists on any layer, and
    // layer-0 frames. `existing` is nil when ids are not real window ids or the query came back empty.
    private struct WindowList {
        var zOrder: [UInt32] = []
        var existing: Set<UInt32>?
        var bounds: [UInt32: CGRect] = [:]
    }

    private func windowList() -> WindowList {
        guard PrivateAPI.axGetWindow != nil,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]], !list.isEmpty else { return WindowList() }
        var result = WindowList(existing: [])
        for info in list {
            guard let number = info[kCGWindowNumber as String] as? Int else { continue }
            let id = UInt32(truncatingIfNeeded: number)
            result.existing?.insert(id)
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }
            if (info[kCGWindowIsOnscreen as String] as? Bool) == true { result.zOrder.append(id) }
            if let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }) {
                result.bounds[id] = bounds
            }
        }
        return result
    }
}

private enum AXRead {
    case value(CFTypeRef)
    case error(AXError)

    var value: CFTypeRef? { if case .value(let value) = self { value } else { nil } }
}
