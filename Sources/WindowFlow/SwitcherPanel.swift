import AppKit
import WindowFlowCore

/// AppKit-only HUD listing the windows. Created lazily on first show, then reused: the panel, its tiles and cached icons.
final class SwitcherPanel {
    var onHover: (Int) -> Void = { _ in }
    var onClick: (Int) -> Void = { _ in }

    private static let tile = NSSize(width: 128, height: 120)
    private static let spacing: CGFloat = 8
    private static let padding: CGFloat = 16

    private lazy var panel: NSPanel = {
        let panel = HUDPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        panel.contentView = background
        return panel
    }()

    private let background = NSVisualEffectView()
    private var tiles: [TileView] = []
    private var icons: [pid_t: NSImage] = [:]
    private var count = 0
    private var columns = 1
    private var visibleRows = 1
    private var firstRow = 0
    private var selected = 0

    var isVisible: Bool { panel.isVisible }

    func show(_ entries: [SwitcherItem], selected: Int) {
        guard !entries.isEmpty, let screen = pointerScreen() else { return }
        let pad = Self.padding, spacing = Self.spacing, tile = Self.tile
        let fitColumns = SwitcherGrid.fit(extent: screen.frame.width * 0.8, item: tile.width, spacing: spacing, padding: pad)
        let fitRows = SwitcherGrid.fit(extent: screen.frame.height * 0.8, item: tile.height, spacing: spacing, padding: pad)
        count = entries.count
        columns = min(count, fitColumns)
        let rows = (count + columns - 1) / columns
        visibleRows = min(rows, fitRows)
        firstRow = 0
        self.selected = min(max(selected, 0), count - 1)

        icons = icons.filter { pid, _ in entries.contains { $0.members.contains { $0.pid == pid } } }
        while tiles.count < count {
            let view = TileView(frame: NSRect(origin: .zero, size: tile))
            view.onHover = { [weak self] in self?.onHover($0) }
            view.onClick = { [weak self] in self?.onClick($0) }
            tiles.append(view)
            background.addSubview(view)
        }
        for (index, view) in tiles.enumerated() {
            guard index < count else { view.isHidden = true; continue }
            let entry = entries[index]
            view.configure(index: index, title: entry.title, icon: icon(for: entry),
                           dimmed: !entry.isGroup && entry.primary.isMinimized)
        }

        let size = NSSize(width: 2 * pad + CGFloat(columns) * tile.width + CGFloat(columns - 1) * spacing,
                          height: 2 * pad + CGFloat(visibleRows) * tile.height + CGFloat(visibleRows - 1) * spacing)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: false)
        scrollToSelection()
        layoutTiles()
        panel.orderFrontRegardless()
        panel.invalidateShadow()
    }

    func select(_ index: Int) {
        guard panel.isVisible, index >= 0, index < count else { return }
        tiles[selected].isSelected = false
        selected = index
        let previousFirstRow = firstRow
        scrollToSelection()
        if firstRow != previousFirstRow { layoutTiles() }
        tiles[selected].isSelected = true
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func scrollToSelection() {
        let row = selected / columns
        if row < firstRow { firstRow = row }
        if row >= firstRow + visibleRows { firstRow = row - visibleRows + 1 }
    }

    private func layoutTiles() {
        let tile = Self.tile, pad = Self.padding, spacing = Self.spacing
        let height = background.bounds.height
        for index in 0..<count {
            let view = tiles[index]
            let row = index / columns - firstRow
            guard row >= 0, row < visibleRows else { view.isHidden = true; continue }
            view.isHidden = false
            view.isSelected = index == selected
            view.frame.origin = NSPoint(x: pad + CGFloat(index % columns) * (tile.width + spacing),
                                        y: height - pad - tile.height - CGFloat(row) * (tile.height + spacing))
        }
    }

    // Two icons sit side by side, three or four fill a 2x2 grid.
    private func icon(for item: SwitcherItem) -> NSImage {
        guard item.isGroup else { return icon(for: item.primary.pid) }
        let icons = item.members.map { icon(for: $0.pid) }
        let cell: CGFloat = 32
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
            for (index, icon) in icons.enumerated() {
                let origin = icons.count == 2 ? NSPoint(x: CGFloat(index) * cell, y: 16)
                    : NSPoint(x: CGFloat(index % 2) * cell, y: CGFloat(1 - index / 2) * cell)
                icon.draw(in: NSRect(origin: origin, size: NSSize(width: cell, height: cell)))
            }
            return true
        }
    }

    private func icon(for pid: pid_t) -> NSImage {
        if let cached = icons[pid] { return cached }
        let source = NSRunningApplication(processIdentifier: pid)?.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
        let sized = (source.copy() as? NSImage) ?? source
        sized.size = NSSize(width: 64, height: 64)
        icons[pid] = sized
        return sized
    }

    private func pointerScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

// Never key or main: the app that was frontmost keeps keyboard focus while the panel is up.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TileView: NSView {
    var onHover: (Int) -> Void = { _ in }
    var onClick: (Int) -> Void = { _ in }
    private(set) var index = 0
    private let iconView = NSImageView(frame: NSRect(x: 32, y: 46, width: 64, height: 64))
    private let label = NSTextField(wrappingLabelWithString: "")

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.22).cgColor : nil
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.frame = NSRect(x: 6, y: 6, width: 116, height: 36)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.isSelectable = false
        addSubview(iconView)
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(index: Int, title: String, icon: NSImage, dimmed: Bool) {
        self.index = index
        label.stringValue = title
        iconView.image = icon
        iconView.alphaValue = dimmed ? 0.5 : 1
        isSelected = false
    }

    // Moves only, not enters: a tile that appears under a resting pointer must not steal the selection.
    override func mouseMoved(with event: NSEvent) {
        if event.deltaX != 0 || event.deltaY != 0 { onHover(index) }
    }

    // The icon and label must not swallow the click.
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) { onClick(index) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
