import CoreGraphics

public struct SwitcherCommand: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case open(reverse: Bool), next, previous, commit, cancel }
    public let session: Int
    public let action: Action
}

/// Key-level state of the switcher, decided from in-memory state only so it can run inside the event-tap callback.
/// Everything that needs AX or UI is returned as commands for the main thread. Not thread-safe: the caller locks.
public struct SwitcherKeyMachine {
    public var shortcut: Shortcut
    public private(set) var isActive = false
    public private(set) var session = 0
    // Key codes whose keyDown was swallowed, so the matching keyUp is swallowed too.
    private var swallowed = Set<UInt16>()

    private static let escape: UInt16 = 53, returnKey: UInt16 = 36, left: UInt16 = 123, right: UInt16 = 124

    public init(shortcut: Shortcut) { self.shortcut = shortcut }

    private var required: UInt64 { shortcut.modifiers & Shortcut.modifierMask }

    public func holds(flags: UInt64) -> Bool { required != 0 && flags & required == required }

    public mutating func handle(type: CGEventType, keyCode: UInt16, flags: UInt64) -> (swallow: Bool, commands: [SwitcherCommand]) {
        var commands: [SwitcherCommand] = []
        // A modifier release the tap never saw (disabled tap, Secure Input) still ends the session.
        if isActive, !holds(flags: flags) { commands.append(end(.commit)) }

        switch type {
        case .keyUp:
            let wasSwallowed = swallowed.remove(keyCode) != nil
            return (isActive || wasSwallowed, commands)
        case .keyDown:
            if isActive {
                swallowed.insert(keyCode)
                let reverse = flags & Shortcut.shift != 0 && required & Shortcut.shift == 0
                switch keyCode {
                case shortcut.keyCode: commands.append(command(reverse ? .previous : .next))
                case Self.left: commands.append(command(.previous))
                case Self.right: commands.append(command(.next))
                case Self.escape: commands.append(end(.cancel))
                case Self.returnKey: commands.append(end(.commit))
                default: break
                }
                return (true, commands)
            }
            if let reverse = opens(keyCode: keyCode, flags: flags) {
                isActive = true
                session += 1
                swallowed.insert(keyCode)
                commands.append(command(.open(reverse: reverse)))
                return (true, commands)
            }
            swallowed.remove(keyCode)
            return (false, commands)
        default:
            return (false, commands)
        }
    }

    /// Ends the session if the modifiers are no longer held according to the system's own state.
    public mutating func reconcile(flags: UInt64) -> [SwitcherCommand] {
        isActive && !holds(flags: flags) ? [end(.commit)] : []
    }

    public mutating func tapReenabled(flags: UInt64) -> [SwitcherCommand] {
        swallowed.removeAll()
        return reconcile(flags: flags)
    }

    /// Called when the main thread closed the session itself (click, watchdog).
    public mutating func close(session: Int) {
        if isActive, self.session == session { isActive = false }
    }

    private func opens(keyCode: UInt16, flags: UInt64) -> Bool? {
        guard required != 0 else { return nil }
        if shortcut.matches(keyCode: keyCode, flags: flags) { return false }
        if required & Shortcut.shift == 0, flags & Shortcut.shift != 0,
           shortcut.matches(keyCode: keyCode, flags: flags & ~Shortcut.shift) { return true }
        return nil
    }

    private func command(_ action: SwitcherCommand.Action) -> SwitcherCommand { SwitcherCommand(session: session, action: action) }

    private mutating func end(_ action: SwitcherCommand.Action) -> SwitcherCommand {
        isActive = false
        return command(action)
    }
}
