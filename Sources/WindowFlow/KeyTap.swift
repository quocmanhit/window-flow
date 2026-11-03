import CoreGraphics
import Foundation
import WindowFlowCore

protocol SwitcherKeyHandling: AnyObject {
    /// Returns true to swallow the event. Called on the tap thread: must be thread-safe and must not touch AX.
    func handle(type: CGEventType, keyCode: UInt16, flags: UInt64) -> Bool
    /// Called on the tap thread after the system disabled the tap and it was re-enabled; events may have been lost.
    func tapReenabled()
}

final class KeyTap {
    /// Assign `onAction` and `switcher` before `start()`; the tap thread reads them without a lock.
    var onAction: (WindowAction) -> Void = { _ in }
    var switcher: SwitcherKeyHandling?

    // Owned by the tap thread: it creates, re-enables, disables and invalidates `tap`; main never touches it.
    private final class TapBox {
        let owner: KeyTap
        var tap: CFMachPort?
        var loop: CFRunLoop?
        // Tap thread only. Key codes whose keyDown was swallowed, so the matching keyUp is swallowed too.
        var swallowed = Set<UInt16>()
        init(owner: KeyTap) { self.owner = owner }
    }

    private let settings: Settings
    private let lock = NSLock()
    private var table: [Shortcut: WindowAction] = [:]
    // Guarded by `lock`. Set while Settings records a shortcut so the keys reach the recorder only.
    private var paused = false
    // Main thread only; set once the tap thread has entered its run loop.
    private var loop: CFRunLoop?
    private var finished: DispatchSemaphore?

    init(settings: Settings) {
        self.settings = settings
        settings.onShortcutsChanged = { [weak self] in self?.rebuildTable() }
        settings.onRecordingChanged = { [weak self] in self?.setPaused($0) }
        rebuildTable()
    }

    // Enum order decides which action wins when two share a shortcut.
    func rebuildTable() {
        var next: [Shortcut: WindowAction] = [:]
        for action in WindowAction.allCases {
            if let shortcut = settings.shortcuts[action], next[shortcut.normalized] == nil { next[shortcut.normalized] = action }
        }
        lock.lock(); table = next; lock.unlock()
    }

    func setPaused(_ value: Bool) {
        lock.lock(); paused = value; lock.unlock()
        // Keys seen or missed around the pause must not leave a switcher session open.
        switcher?.tapReenabled()
    }

    // The tap lives on its own thread so a stalled main thread cannot stall the system keyboard.
    @discardableResult
    func start() -> Bool {
        guard loop == nil else { return true }
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let box = TapBox(owner: self)
        let thread = Thread {
            let refcon = Unmanaged.passRetained(box).toOpaque()
            defer { Unmanaged<TapBox>.fromOpaque(refcon).release(); done.signal() }
            guard let tap = Self.makeTap(refcon: refcon) else { ready.signal(); return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let loop = CFRunLoopGetCurrent()
            box.tap = tap
            box.loop = loop
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            // Signalled from inside the loop so a stop() right after start() cannot hit a loop that is not running yet.
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { ready.signal() }
            CFRunLoopRun()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(tap)
            box.tap = nil
        }
        thread.name = "WindowFlow.KeyTap"
        thread.start()
        ready.wait()
        guard let started = box.loop else { return false }
        loop = started
        finished = done
        return true
    }

    // Only signals the loop; the tap thread tears its own tap down, then stop() waits for it so start() can follow safely.
    func stop() {
        guard let loop else { return }
        CFRunLoopStop(loop)
        finished?.wait()
        self.loop = nil
        finished = nil
    }

    private static func makeTap(refcon: UnsafeMutableRawPointer) -> CFMachPort? {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let box = Unmanaged<TapBox>.fromOpaque(refcon!).takeUnretainedValue()
                return box.owner.handle(type: type, event: event, box: box)
            },
            userInfo: refcon)
    }

    private func handle(type: CGEventType, event: CGEvent, box: TapBox) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            box.swallowed.removeAll()
            switcher?.tapReenabled()
            return Unmanaged.passUnretained(event)
        }
        lock.lock(); let isPaused = paused; lock.unlock()
        if isPaused {
            box.swallowed.removeAll()
            return Unmanaged.passUnretained(event)
        }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        if let switcher, switcher.handle(type: type, keyCode: keyCode, flags: flags) { return nil }

        switch type {
        case .keyDown:
            lock.lock()
            let action = table[Shortcut(keyCode: keyCode, modifiers: flags).normalized]
            lock.unlock()
            guard let action else {
                box.swallowed.remove(keyCode)
                return Unmanaged.passUnretained(event)
            }
            box.swallowed.insert(keyCode)
            let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !repeating || action == .larger || action == .smaller {
                DispatchQueue.main.async { [weak self] in self?.onAction(action) }
            }
            return nil
        case .keyUp:
            if box.swallowed.remove(keyCode) != nil { return nil }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
