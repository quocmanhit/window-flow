import AppKit
import WindowFlowCore

/// AppKit-only HUD listing the windows. Created lazily on first show, then reused: the panel, its tiles and cached icons.
final class SwitcherPanel {
    var onHover: (Int) -> Void = { _ in }
    var onClick: (Int) -> Void = { _ in }

    private static let spacing: CGFloat = 6
    static let padding: CGFloat = 16

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
        return panel
    }()

    // The selection's radius is this minus the padding, so a corner tile's highlight is concentric with the panel.
    static let cornerRadius: CGFloat = 36
    private let container = NSView()
    private var appearance: SwitcherAppearance?

    static var glassAvailable: Bool { NSClassFromString("NSGlassEffectView") != nil }

    // Liquid Glass (macOS 26+). The SDK this builds with predates NSGlassEffectView, so it is looked up at runtime.
    private static func glass(around content: NSView) -> NSView? {
        guard let type = NSClassFromString("NSGlassEffectView") as? NSView.Type else { return nil }
        let glass = type.init(frame: .zero)
        guard glass.responds(to: NSSelectorFromString("setContentView:")),
              glass.responds(to: NSSelectorFromString("setCornerRadius:")) else { return nil }
        glass.setValue(content, forKey: "contentView")
        glass.setValue(cornerRadius, forKey: "cornerRadius")
        // Variant 6 is the lightly frosted glass closest to the macOS app switcher (compared side by side on screen);
        // the default variant frosts the backdrop away. Set after `style`, which resets it. Private: skipped if absent.
        if glass.responds(to: NSSelectorFromString("setStyle:")) { glass.setValue(0, forKey: "style") }
        if glass.responds(to: NSSelectorFromString("set_variant:")) { glass.setValue(6, forKey: "_variant") }
        return glass
    }

    private static func blur(around content: NSView) -> NSView {
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        // A layer corner radius does not clip a behind-window blur, which leaves square corners; a mask image does.
        blur.maskImage = roundedMask(radius: cornerRadius)
        content.autoresizingMask = [.width, .height]
        blur.addSubview(content)
        // Like the macOS app switcher: a hairline edge keeps the rounded outline crisp on any background.
        let edge = HairlineBorder(radius: cornerRadius)
        edge.autoresizingMask = [.width, .height]
        blur.addSubview(edge)
        return blur
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = 2 * radius + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // Variant 6 alone is dark; this wash brings it to the switcher's light tone. Its strength is the opacity setting.
    private func washGlass() {
        container.wantsLayer = true
        // The blur fallback (no Liquid Glass on this macOS) keeps its own tint.
        guard appearance?.background == .glass, !(container.superview is NSVisualEffectView) else {
            container.layer?.backgroundColor = nil
            return
        }
        let dark = panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let alpha = appearance?.washAlpha(dark: dark) ?? 0.55
        container.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).withAlphaComponent(alpha).cgColor
        container.layer?.cornerRadius = Self.cornerRadius
    }

    // A changed appearance drops the tiles (their geometry is fixed at creation) and rewraps the background if needed.
    private func apply(_ new: SwitcherAppearance) {
        guard new != appearance else { return }
        if new.background != appearance?.background {
            container.removeFromSuperview()
            panel.contentView = (new.background == .glass ? Self.glass(around: container) : nil) ?? Self.blur(around: container)
        }
        tiles.forEach { $0.removeFromSuperview() }
        tiles.removeAll()
        appearance = new
    }
    private var tiles: [TileView] = []
    private var titles: [String] = []
    private lazy var caption: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.alignment = .center
        field.lineBreakMode = .byTruncatingMiddle
        field.maximumNumberOfLines = 1
        field.textColor = .labelColor
        container.addSubview(field)
        return field
    }()
    private var icons: [pid_t: NSImage] = [:]
    private var count = 0
    private var columns = 1
    private var visibleRows = 1
    private var firstRow = 0
    private var selected = 0

    var isVisible: Bool { panel.isVisible }

    func show(_ entries: [SwitcherItem], selected: Int, onMainDisplay: Bool, appearance: SwitcherAppearance) {
        guard !entries.isEmpty, let screen = onMainDisplay ? NSScreen.screens.first : pointerScreen() else { return }
        apply(appearance)
        washGlass()
        let pad = Self.padding, spacing = Self.spacing, tile = tileSize
        let metrics = appearance.metrics, captionHeight = CGFloat(metrics.captionHeight)
        let fitColumns = SwitcherGrid.fit(extent: screen.frame.width * 0.8, item: tile.width, spacing: spacing, padding: pad)
        let fitRows = SwitcherGrid.fit(extent: screen.frame.height * 0.8 - captionHeight, item: tile.height, spacing: spacing, padding: pad)
        count = entries.count
        columns = SwitcherGrid.columns(count: count, fit: fitColumns)
        let rows = (count + columns - 1) / columns
        visibleRows = min(rows, fitRows)
        firstRow = 0
        self.selected = min(max(selected, 0), count - 1)

        icons = icons.filter { pid, _ in entries.contains { $0.members.contains { $0.pid == pid } } }
        while tiles.count < count {
            let view = TileView(frame: NSRect(origin: .zero, size: tile), appearance: appearance)
            view.onHover = { [weak self] in self?.onHover($0) }
            view.onClick = { [weak self] in self?.onClick($0) }
            tiles.append(view)
            container.addSubview(view)
        }
        titles = entries.map(\.title)
        for (index, view) in tiles.enumerated() {
            guard index < count else { view.isHidden = true; continue }
            let entry = entries[index]
            view.configure(index: index, title: entry.title, icon: icon(for: entry),
                           dimmed: !entry.isGroup && entry.primary.isMinimized)
        }

        let size = NSSize(width: 2 * pad + CGFloat(columns) * tile.width + CGFloat(columns - 1) * spacing,
                          height: 2 * pad + CGFloat(visibleRows) * tile.height + CGFloat(visibleRows - 1) * spacing + captionHeight)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        scrollToSelection()
        layoutTiles()
        caption.isHidden = captionHeight == 0
        if captionHeight > 0 {
            caption.font = .systemFont(ofSize: CGFloat(metrics.fontSize) + 1, weight: .medium)
            // The strip sits between the last row and the bottom padding, text centered in it.
            let textHeight = CGFloat(metrics.fontSize) + 6
            caption.frame = NSRect(x: pad + 8, y: pad + (captionHeight - textHeight) / 2 - 4,
                                   width: size.width - 2 * pad - 16, height: textHeight)
            updateCaption()
        }
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
        updateCaption()
    }

    private func updateCaption() {
        guard !caption.isHidden, titles.indices.contains(selected) else { return }
        caption.stringValue = titles[selected]
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

    private var tileSize: NSSize {
        let m = (appearance ?? SwitcherAppearance()).metrics
        return NSSize(width: m.tileWidth, height: m.tileHeight)
    }

    private func layoutTiles() {
        let tile = tileSize, pad = Self.padding, spacing = Self.spacing
        let height = panel.frame.height
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

    // Two icons overlap diagonally, three or four fill a 2x2 grid.
    private func icon(for item: SwitcherItem) -> NSImage {
        guard item.isGroup else { return icon(for: item.primary.pid) }
        let icons = item.members.map { icon(for: $0.pid) }
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
            if icons.count == 2 {
                icons[0].draw(in: NSRect(x: 0, y: 20, width: 44, height: 44))
                icons[1].draw(in: NSRect(x: 20, y: 0, width: 44, height: 44))
            } else {
                for (index, icon) in icons.enumerated() {
                    icon.draw(in: NSRect(x: CGFloat(index % 2) * 32, y: CGFloat(1 - index / 2) * 32, width: 32, height: 32))
                }
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

private final class HairlineBorder: NSView {
    private let radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        layer?.cornerRadius = radius
        layer?.borderWidth = 1 / (window?.backingScaleFactor ?? 2)
        layer?.borderColor = NSColor.switcherHairline.cgColor
    }

    override func viewDidChangeBackingProperties() { needsDisplay = true }
}

extension NSColor {
    private static func light(_ light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }

    static let switcherHairline = light(.black.withAlphaComponent(0.12), dark: .white.withAlphaComponent(0.2))
    // Measured from the macOS app switcher: its selection darkens the panel by about 22%.
    static let switcherSelection = light(.black.withAlphaComponent(0.2), dark: .white.withAlphaComponent(0.2))
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
    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let highlight: SwitcherHighlight
    private var dimmed = false

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            updateLabelColor()
        }
    }

    init(frame: NSRect, appearance: SwitcherAppearance) {
        let m = appearance.metrics
        highlight = appearance.highlight
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = SwitcherPanel.cornerRadius - SwitcherPanel.padding
        iconView.frame = NSRect(x: (frame.width - m.icon) / 2, y: m.iconBottom, width: m.icon, height: m.icon)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        if appearance.titles == .all {
            label.frame = NSRect(x: 8, y: 10, width: frame.width - 16, height: m.fontSize + 6)
            label.font = .systemFont(ofSize: m.fontSize, weight: .medium)
            label.alignment = .center
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.isSelectable = false
            addSubview(label)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    // Resolved here so the highlight follows light and dark mode and the system accent color.
    override func updateLayer() {
        switch highlight {
        case .neutral:
            layer?.backgroundColor = isSelected ? NSColor.switcherSelection.cgColor : nil
            layer?.borderWidth = 0
        case .accent:
            layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : nil
            layer?.borderWidth = isSelected ? 1 : 0
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
        }
    }

    func configure(index: Int, title: String, icon: NSImage, dimmed: Bool) {
        self.index = index
        self.dimmed = dimmed
        label.stringValue = title
        // Without titles the name is still one hover away.
        toolTip = label.superview == nil ? title : nil
        iconView.image = icon
        iconView.alphaValue = dimmed ? 0.45 : 1
        isSelected = false
        needsDisplay = true
        updateLabelColor()
    }

    private func updateLabelColor() {
        label.textColor = dimmed ? .tertiaryLabelColor : .labelColor
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
