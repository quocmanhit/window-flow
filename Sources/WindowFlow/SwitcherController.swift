import AppKit
import WindowFlowCore

/// Key handling runs on the event-tap thread and only touches `machine` (under `lock`); everything that needs
/// AX, the panel or focus is posted to main, in order, as commands tagged with the session they belong to.
final class SwitcherController: SwitcherKeyHandling {
    private let settings: Settings
    private let catalog: WindowCatalog
    private let panel = SwitcherPanel()

    private let lock = NSLock()
    private var machine: SwitcherKeyMachine

    // Main thread only.
    private var session = 0
    private var entries: [SwitcherItem] = []
    private var selection = SwitcherSelection(count: 0)
    private var shown = false
    private var watchdog: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    init(settings: Settings, catalog: WindowCatalog) {
        self.settings = settings
        self.catalog = catalog
        machine = SwitcherKeyMachine(shortcut: settings.switcherShortcut)
        panel.onHover = { [weak self] in self?.hover($0) }
        panel.onClick = { [weak self] in self?.click($0) }
    }

    // MARK: Main thread lifecycle

    func start() {
        settingsChanged()
    }

    func settingsChanged() {
        let shortcut = settings.switcherShortcut
        lock.lock(); machine.shortcut = shortcut; lock.unlock()
        if SystemSwitcherHotKey.fallbackEnabled, signalSources.isEmpty { installSignalHandlers() }
        SystemSwitcherHotKey.apply(disabled: SystemSwitcherHotKey.fallbackEnabled && shortcut.normalized == ShortcutDefaults.commandTab)
    }

    func shutdown() {
        closeSession()
        SystemSwitcherHotKey.restoreIfWeDisabledIt()
    }

    // MARK: Tap thread

    func handle(type: CGEventType, keyCode: UInt16, flags: UInt64) -> Bool {
        lock.lock()
        let result = machine.handle(type: type, keyCode: keyCode, flags: flags)
        lock.unlock()
        post(result.commands)
        return result.swallow
    }

    func tapReenabled() {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        lock.lock()
        let commands = machine.tapReenabled(flags: flags)
        lock.unlock()
        post(commands)
    }

    private func post(_ commands: [SwitcherCommand]) {
        guard !commands.isEmpty else { return }
        DispatchQueue.main.async { [self] in commands.forEach(apply) }
        for command in commands {
            guard case .open = command.action else { continue }
            let session = command.session
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [self] in showIfHeld(session) }
        }
    }

    // MARK: Main thread

    private func apply(_ command: SwitcherCommand) {
        switch command.action {
        case .open(let reverse):
            closeSession()
            session = command.session
            let snapshot = catalog.snapshot()
            entries = snapshot.items
            // Start on the second tile only when the first one holds the window that has focus now.
            selection = SwitcherSelection(count: entries.count, start: snapshot.focusedFirst && !reverse ? 1 : 0)
            if reverse { selection.previous() }
            if entries.isEmpty { closeSession() }
        case .next, .previous:
            guard command.session == session else { return }
            if command.action == .next { selection.next() } else { selection.previous() }
            if shown, let index = selection.index { panel.select(index) }
        case .commit:
            guard command.session == session else { return }
            commit()
        case .cancel:
            guard command.session == session else { return }
            closeSession()
        }
    }

    // A quick tap never gets here with the modifier still down, so no panel flashes.
    private func showIfHeld(_ expected: Int) {
        guard session == expected, !shown, let index = selection.index else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        lock.lock()
        let held = machine.isActive && machine.session == expected && machine.holds(flags: flags)
        lock.unlock()
        guard held else { reconcile(); return }
        shown = true
        panel.show(entries, selected: index)
        startWatchdog()
    }

    private func commit() {
        let target = selection.index.flatMap { entries.indices.contains($0) ? entries[$0] : nil }
        closeSession()
        guard let target else { return }
        catalog.touch(target)
        WindowFocus.focus(target)
    }

    private func closeSession() {
        lock.lock(); machine.close(session: session); lock.unlock()
        session = 0
        shown = false
        entries = []
        watchdog?.invalidate()
        watchdog = nil
        panel.hide()
    }

    private func hover(_ index: Int) {
        guard shown, entries.indices.contains(index), selection.index != index else { return }
        select(index)
    }

    private func click(_ index: Int) {
        guard shown, entries.indices.contains(index) else { return }
        select(index)
        commit()
    }

    private func select(_ index: Int) {
        var guardCount = 0
        while selection.index != index, guardCount < entries.count { selection.next(); guardCount += 1 }
        panel.select(index)
    }

    // Safety net while the panel is up: if the modifier release was never delivered (Secure Input, a lost
    // tap), the system's own modifier state still ends the session. Runs only while the panel is visible.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.reconcile() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func reconcile() {
        let flags = CGEventSource.flagsState(.combinedSessionState).rawValue
        lock.lock()
        let commands = machine.reconcile(flags: flags)
        lock.unlock()
        commands.forEach(apply)
    }

    // The fallback leaves the system Cmd-Tab disabled while we run, so every normal exit path must undo it.
    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}

/// Fallback for when swallowing Cmd-Tab in the HID tap does not stop the system switcher: switch the system's
/// symbolic hotkeys off while Cmd-Tab is our shortcut. Off by default; Settings > Switcher toggles it live.
enum SystemSwitcherHotKey {
    private static let flagKey = "disableSystemCommandTab"
    // Survives a crash, so the next launch knows the system hotkeys were left disabled.
    private static let markerKey = "systemCommandTabDisabledByUs"
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2

    static var fallbackEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: flagKey) }
        set { UserDefaults.standard.set(newValue, forKey: flagKey) }
    }

    static func apply(disabled: Bool) {
        guard let set = PrivateAPI.setSymbolicHotKeyEnabled else { return }
        if disabled == UserDefaults.standard.bool(forKey: markerKey) { return }
        _ = set(commandTab, !disabled)
        _ = set(commandShiftTab, !disabled)
        UserDefaults.standard.set(disabled, forKey: markerKey)
    }

    static func restoreIfWeDisabledIt() { apply(disabled: false) }
}
