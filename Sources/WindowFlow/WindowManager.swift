import AppKit
import ApplicationServices
import WindowFlowCore

final class WindowManager {
    private let settings: Settings
    private var cycles = CycleTracker()
    private var restores = RestoreStore()
    private var requests: [UInt32: (target: CGRect, readBack: CGRect)] = [:]

    static let axTimeout: Float = 1.0

    init(settings: Settings) { self.settings = settings }

    func perform(_ action: WindowAction) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let window = focusedWindow(pid: app.processIdentifier),
              !isFullScreen(window),
              let id = windowID(window), let current = frame(of: window) else { return }
        let screens = Screens.visibleFrames()
        guard let index = screenIndex(for: current, in: screens.map(\.full)) else { return }
        let tracked = trackedFrame(current, id: id)

        switch action {
        case .restore:
            guard let saved = restores.takeRestore(window: id) else { return }
            requests[id] = nil
            setFrame(saved, of: window)
        case .nextDisplay, .previousDisplay:
            let order = DisplayMove.order(screens.map(\.visible))
            guard let position = order.firstIndex(of: index), order.count > 1 else { return }
            let to = screens[order[DisplayMove.target(from: position, count: order.count, forward: action == .nextDisplay)]].visible
            apply(DisplayMove.frame(window: current, from: screens[index].visible, to: to),
                  action: action, screen: to, to: window, id: id, tracked: tracked)
        default:
            let step = cycles.step(for: action, window: id, current: tracked)
            let visible = screens[index].visible
            guard let target = Layout.frame(for: action, window: current, screen: visible,
                                            gap: CGFloat(settings.gap), step: step) else { return }
            let result = apply(target, action: action, screen: visible, to: window, id: id, tracked: tracked)
            cycles.record(action, window: id, result: result)
        }
    }

    func forget(window: UInt32) {
        restores.forget(window: window)
        requests[window] = nil
    }

    func frame(of window: AXUIElement) -> CGRect? {
        var point = CGPoint.zero, size = CGSize.zero
        guard let p = attribute(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              AXValueGetValue(p as! AXValue, .cgPoint, &point),
              let s = attribute(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID(),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    // Size first shrinks the window before it crosses displays; the second size lets apps that clamp against the old display grow.
    func setFrame(_ frame: CGRect, of window: AXUIElement) {
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let positionValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    func windowID(_ window: AXUIElement) -> UInt32? {
        if let getWindow = PrivateAPI.axGetWindow {
            var id: CGWindowID = 0
            if getWindow(window, &id) == .success, id != 0 { return id }
        }
        return UInt32(truncatingIfNeeded: CFHash(window))
    }

    // Some apps move asynchronously and report the old frame right after a set. Core compares against that
    // read-back, so a window still at the requested target is presented to it as the read-back.
    private func trackedFrame(_ current: CGRect, id: UInt32) -> CGRect {
        guard let request = requests[id], near(request.target, current) else { return current }
        return request.readBack
    }

    @discardableResult
    private func apply(_ target: CGRect, action: WindowAction, screen: CGRect, to window: AXUIElement,
                       id: UInt32, tracked: CGRect) -> CGRect {
        restores.willApply(window: id, current: tracked)
        let before = frame(of: window)
        setFrame(target, of: window)
        let actual = frame(of: window) ?? target
        restores.lastApplied(window: id, frame: actual)
        requests[id] = (target, actual)
        guard sizeDiffers(actual, target) else { return actual }
        if let before, near(before, actual) {
            // Unchanged read-back suggests an asynchronous app; look again before deciding it refused the size.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, let request = self.requests[id], request.target == target,
                      let now = self.frame(of: window), self.sizeDiffers(now, target) else { return }
                let final = self.realign(now, target: target, action: action, screen: screen, window: window)
                // Core keeps the provisional read-back; the final frame is mapped onto it by trackedFrame.
                self.requests[id] = (final, request.readBack)
            }
            return actual
        }
        let final = realign(actual, target: target, action: action, screen: screen, window: window)
        requests[id] = (target, final)
        restores.lastApplied(window: id, frame: final)
        return final
    }

    // An app that kept its own size would overflow the screen at the requested origin.
    private func realign(_ actual: CGRect, target: CGRect, action: WindowAction, screen: CGRect, window: AXUIElement) -> CGRect {
        var origin = Layout.realign(actual: actual.size, target: target, screen: screen, action: action)
        guard let value = AXValueCreate(.cgPoint, &origin) else { return actual }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        return frame(of: window) ?? CGRect(origin: origin, size: actual.size)
    }

    private func sizeDiffers(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) > 2 || abs(a.height - b.height) > 2
    }

    private func near(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    private func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.axTimeout)
        guard let value = attribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        AXUIElementSetMessagingTimeout(window, Self.axTimeout)
        return window
    }

    func isFullScreen(_ window: AXUIElement) -> Bool {
        (attribute(window, "AXFullScreen") as? Bool) == true
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private func screenIndex(for window: CGRect, in screens: [CGRect]) -> Int? {
        let center = CGPoint(x: window.midX, y: window.midY)
        if let hit = screens.firstIndex(where: { $0.contains(center) }) { return hit }
        return screens.indices.max { screens[$0].intersection(window).area < screens[$1].intersection(window).area }
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
