import AppKit
import ApplicationServices
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var servicesStarted = false
    private var settingsWindow: NSWindow?
    private let nav = SettingsNav()
    private lazy var recorder = ShortcutRecorder(settings: settings)

    // The bundled icon only exists in the packaged app; `swift run` falls back to an SF Symbol.
    private static func menuBarIcon() -> NSImage? {
        let icon = NSImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "WindowFlow")
        icon?.isTemplate = true
        icon?.accessibilityDescription = "WindowFlow"
        if icon?.name() == "MenuBarIconTemplate" { icon?.size = NSSize(width: 18, height: 18) }
        return icon
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemSwitcherHotKey.restoreIfWeDisabledIt()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        if Language.saved == nil { askLanguage() }
        // `--settings [switcher|shortcuts|general]` opens Settings on launch, used for README screenshots.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--settings") {
            switch args.dropFirst(i + 1).first {
            case "shortcuts": nav.tab = .shortcuts
            case "general": nav.tab = .general
            default: break
            }
            openSettings()
        }
        // The recorder's tap is system-wide, so it must not outlive the app's focus.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { if self?.settingsWindow != nil { self?.recorder.cancel() } } }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.startWhenTrusted() } }
        // Granting Accessibility rarely activates an accessory app, so the system's own notification wakes the check.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            for delay in [0.5, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { self?.startWhenTrusted() } }
            }
        }
        startWhenTrusted()
    }

    // Re-checked on activation and menu open instead of a timer, so idle CPU stays at zero.
    private func startWhenTrusted() {
        guard !servicesStarted else { return }
        var trusted = AXIsProcessTrusted()
        if !trusted, !didPrompt {
            didPrompt = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        }
        guard trusted else { return }
        servicesStarted = startServices()
    }

    private var didPrompt = false

    private let settings = Settings()
    private lazy var windowManager = WindowManager(settings: settings)
    private lazy var keyTap = KeyTap(settings: settings)
    private lazy var catalog = WindowCatalog(settings: settings, windowManager: windowManager)
    private lazy var switcher = SwitcherController(settings: settings, catalog: catalog)
    private var settingsObserver: AnyCancellable?

    private func startServices() -> Bool {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), WindowManager.axTimeout)
        keyTap.onAction = { [weak self] in self?.windowManager.perform($0) }
        keyTap.switcher = switcher
        guard keyTap.start() else { return false }
        catalog.start()
        switcher.start()
        // objectWillChange fires before the value changes; the main-queue hop lets the setter finish first.
        settingsObserver = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.switcher.settingsChanged(); self?.catalog.settingsChanged() }
        }
        return true
    }

    // Releases the tap first, then undoes the Cmd-Tab fallback, so the system switcher is back after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        guard servicesStarted else { return }
        keyTap.stop()
        switcher.shutdown()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        startWhenTrusted()
        menu.removeAllItems()
        if !servicesStarted {
            menu.addItem(item(tr("Grant Accessibility permission…", "Cần cấp quyền Accessibility…"), #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }
        let preferences = item(tr("Settings…", "Cài đặt…"), #selector(openSettings))
        preferences.keyEquivalent = ","
        menu.addItem(preferences)
        menu.addItem(.separator())
        menu.addItem(languageMenu())
        menu.addItem(item(tr("Launch at login", "Mở cùng macOS"), #selector(toggleLaunchAtLogin), on: LaunchAtLogin.isEnabled))
        let quit = NSMenuItem(title: tr("Quit WindowFlow", "Thoát"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, on: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    // The title stays bilingual so the menu can be found whatever language is active.
    private func languageMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Language / Ngôn ngữ", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for language in Language.allCases {
            let child = item(language.title, #selector(setLanguage(_:)), on: language == Language.current)
            child.representedObject = language.rawValue
            menu.addItem(child)
        }
        parent.submenu = menu
        return parent
    }

    private func askLanguage() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Choose a language / Chọn ngôn ngữ"
        alert.informativeText = "You can change it later from the menu bar.\nCó thể đổi lại trong menu trên thanh menu."
        for language in Language.allCases { alert.addButton(withTitle: language.title) }
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        Language.saved = Language.allCases.indices.contains(index) ? Language.allCases[index] : .english
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = Language(rawValue: raw) else { return }
        changeLanguage(language)
    }

    private func changeLanguage(_ language: Language) {
        Language.saved = language
        nav.languageRevision += 1
        settingsWindow?.title = SettingsWindow.title
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow.make(settings: settings, recorder: recorder, nav: nav) { [weak self] in self?.changeLanguage($0) }
            settingsWindow?.delegate = self
        }
        // A menu bar-only app may be refused focus while another app is active, leaving the window behind it.
        NSApp.setActivationPolicy(.regular)
        // Wait for the status menu to finish closing, or the activation can be lost.
        DispatchQueue.main.async {
            NSApp.activate()
            self.settingsWindow?.makeKeyAndOrderFront(nil)
            self.settingsWindow?.orderFrontRegardless()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow { catalog.ownWindowBecameKey(window) }
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow { recorder.cancel() }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow { recorder.cancel() }
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        recorder.cancel()
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.set(!LaunchAtLogin.isEnabled) }
}
