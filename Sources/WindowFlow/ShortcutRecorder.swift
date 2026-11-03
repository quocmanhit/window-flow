import AppKit
import SwiftUI
import WindowFlowCore

// Records one shortcut from a HID-level tap, which sees keys before macOS turns them into system
// shortcuts, so combinations like ⌃← or F-keys bound to Mission Control can still be captured.
// The tap runs on its own thread so a stalled main thread cannot stall the keyboard.
final class KeyRecorder {
    private final class Box {
        let owner: KeyRecorder
        let generation: Int
        var tap: CFMachPort?
        var loop: CFRunLoop?
        var finished = false  // tap thread only: swallow everything after the first key
        init(owner: KeyRecorder, generation: Int) { self.owner = owner; self.generation = generation }
    }

    // Main thread only. A session's completion runs only while its generation is still current.
    private var generation = 0
    private var completion: ((Shortcut?) -> Void)?
    private var loop: CFRunLoop?
    private var finished: DispatchSemaphore?

    // Calls back with nil when the user cancels with Esc.
    func start(_ completion: @escaping (Shortcut?) -> Void) -> Bool {
        stop()
        let box = Box(owner: self, generation: generation)
        let ready = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            let refcon = Unmanaged.passRetained(box).toOpaque()
            defer { Unmanaged<Box>.fromOpaque(refcon).release(); done.signal() }
            guard let tap = Self.makeTap(refcon: refcon) else { ready.signal(); return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let loop = CFRunLoopGetCurrent()
            box.tap = tap
            box.loop = loop
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { ready.signal() }
            CFRunLoopRun()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFMachPortInvalidate(tap)
            box.tap = nil
        }
        thread.name = "WindowFlow.KeyRecorder"
        thread.start()
        ready.wait()
        guard let started = box.loop else { return false }
        loop = started
        finished = done
        self.completion = completion
        return true
    }

    func stop() {
        completion = nil
        generation += 1
        guard let loop else { return }
        CFRunLoopStop(loop)
        finished?.wait()
        self.loop = nil
        finished = nil
    }

    private static func makeTap(refcon: UnsafeMutableRawPointer) -> CFMachPort? {
        let types: [CGEventType] = [.keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let box = Unmanaged<Box>.fromOpaque(refcon!).takeUnretainedValue()
                return box.owner.handle(type: type, event: event, box: box)
            },
            userInfo: refcon)
    }

    private func handle(type: CGEventType, event: CGEvent, box: Box) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            if box.finished { return nil }
            box.finished = true
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
            let shortcut = keyCode == 53 && modifiers.isEmpty ? nil : Shortcut(keyCode: keyCode, modifiers: modifiers.rawValue)
            // Tearing the tap down from inside its own callback is unsafe, so finish on main, for this session only.
            DispatchQueue.main.async {
                guard self.generation == box.generation else { return }
                let completion = self.completion
                self.stop()
                completion?(shortcut)
            }
            return nil
        case .keyUp:
            return nil
        default:
            if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
    }
}

/// One recorder shared by every row, so at most one recording is live and the window can cancel it on close.
/// While active, the main key tap ignores shortcuts (Settings.setRecording).
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var activeID: String?
    @Published private(set) var noticeID: String?
    private var noticeText = ""
    private let recorder = KeyRecorder()
    private let settings: Settings


    init(settings: Settings) { self.settings = settings }

    func begin(id: String, forSwitcher: Bool = false, onPick: @escaping (Shortcut) -> Void) {
        cancel()
        noticeID = nil
        let started = recorder.start { [weak self] shortcut in
            guard let self, activeID == id else { return }
            end()
            guard let shortcut else { return }
            // A bare letter would be swallowed system-wide while typing.
            if forSwitcher ? shortcut.isAllowedForSwitcher : shortcut.isAllowed { onPick(shortcut) } else {
                show(forSwitcher ? tr("Use ⌃, ⌥ or ⌘ with the key.", "Cần dùng ⌃, ⌥ hoặc ⌘ cùng với phím.")
                                 : tr("Use ⌃, ⌥ or ⌘ with the key (F1–F20 can be used alone).",
                                      "Cần dùng ⌃, ⌥ hoặc ⌘ cùng với phím (F1–F20 dùng riêng được)."), for: id)
            }
        }
        guard started else {
            show(tr("Grant Accessibility permission first.", "Cần cấp quyền Accessibility trước."), for: id)
            return
        }
        activeID = id
        settings.setRecording(true)
    }

    func notice(for id: String) -> String? { noticeID == id ? noticeText : nil }

    private func show(_ text: String, for id: String) {
        noticeText = text
        noticeID = id
    }

    func cancel() {
        recorder.stop()
        end()
    }

    private func end() {
        guard activeID != nil else { return }
        activeID = nil
        settings.setRecording(false)
    }
}

struct ShortcutField: View {
    let id: String
    let shortcut: Shortcut?
    var conflict = false
    var forSwitcher = false
    @ObservedObject var recorder: ShortcutRecorder
    let onPick: (Shortcut) -> Void

    private var recording: Bool { recorder.activeID == id }

    var body: some View {
        Button {
            if recording { recorder.cancel() } else { recorder.begin(id: id, forSwitcher: forSwitcher, onPick: onPick) }
        } label: {
            Text(label)
                .frame(width: 150)
                .foregroundStyle(conflict ? Color.red : Color.primary)
        }
        .help(conflict ? tr("This shortcut is used more than once.", "Phím tắt này bị trùng.") : "")
    }

    private var label: String {
        if recording { return tr("Press a shortcut…", "Nhấn phím tắt…") }
        return shortcut?.localizedDisplay ?? tr("Not set", "Chưa gán")
    }
}


extension Shortcut {
    // Core labels keys it has no name for as "Key N"; the app localizes that word.
    var localizedDisplay: String {
        let fallback = "Key \(keyCode)"
        guard display.hasSuffix(fallback) else { return display }
        return display.dropLast(fallback.count) + tr("Key", "Phím") + " \(keyCode)"
    }
}
