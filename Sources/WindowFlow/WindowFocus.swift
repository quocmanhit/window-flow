import AppKit
import ApplicationServices

enum WindowFocus {
    static let groupStep: TimeInterval = 0.06

    /// Main thread. AXRaise cannot lift a window of an inactive app above the active app's windows, so every group
    /// member gets the full focus chain in turn, oldest first, a step apart; the primary ends up active and key.
    /// A window that no longer exists makes every step fail silently.
    static func focus(_ item: SwitcherItem) {
        for (i, entry) in item.focusOrder.enumerated() {
            let run = { makeKey(entry, psn: bringToFront(entry)) }
            if i == 0 { run() } else { DispatchQueue.main.asyncAfter(deadline: .now() + groupStep * Double(i), execute: run) }
        }
    }

    // Activates the app and, with the SkyLight path, switches to the window's Space. Returns the process number
    // when that path was used, since makeKey needs it.
    private static func bringToFront(_ entry: WindowEntry) -> PrivateAPI.PSN? {
        if entry.isMinimized {
            if let own = ownWindow(entry) { own.deminiaturize(nil) }
            else { AXUIElementSetAttributeValue(entry.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        }
        let app = NSRunningApplication(processIdentifier: entry.pid)
        if app?.isHidden == true { app?.unhide() }

        // Without the real-id symbol the catalog ids are hashes, which the SkyLight calls would misread.
        if PrivateAPI.axGetWindow != nil, let getProcess = PrivateAPI.getProcessForPID, let setFront = PrivateAPI.setFrontProcessWithOptions,
           PrivateAPI.postEventRecordTo != nil {
            var psn = PrivateAPI.PSN()
            if getProcess(entry.pid, &psn) == 0 {
                // 0x200 is kCPSUserGenerated; with the window id it makes the window server follow that window's Space.
                _ = setFront(&psn, entry.id, 0x200)
                return psn
            }
        }
        app?.activate()
        return nil
    }

    private static func makeKey(_ entry: WindowEntry, psn: PrivateAPI.PSN?) {
        if var psn, let post = PrivateAPI.postEventRecordTo {
            // Two 0xf8-byte event records (down, up) tell the window server which window of the process becomes key.
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x3a] = 0x10
            withUnsafeBytes(of: entry.id) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
            for i in 0x20..<0x30 { bytes[i] = 0xff }
            for kind: UInt8 in [0x01, 0x02] {
                bytes[0x08] = kind
                _ = post(&psn, &bytes)
            }
            if let own = ownWindow(entry) { raiseOwn(own) } else { AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString) }
        } else if let own = ownWindow(entry) {
            raiseOwn(own)
        } else {
            AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(entry.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }

    // Our own windows are driven through AppKit; an AX call into this process from main would block on itself.
    private static func ownWindow(_ entry: WindowEntry) -> NSWindow? {
        guard entry.pid == getpid() else { return nil }
        return NSApp.windows.first { $0.windowNumber == Int(entry.id) }
    }

    private static func raiseOwn(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

}
