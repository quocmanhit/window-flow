public enum SwitcherSize: String, CaseIterable, Sendable { case small, medium, large }
public enum SwitcherBackground: String, CaseIterable, Sendable { case glass, blur }
public enum SwitcherHighlight: String, CaseIterable, Sendable { case neutral, accent }
/// Window titles under every tile, only the selected one's (in a caption strip, like the macOS app switcher), or none.
public enum SwitcherTitles: String, CaseIterable, Sendable { case all, selected, none }

public struct SwitcherAppearance: Equatable, Sendable {
    public var size: SwitcherSize
    public var titles: SwitcherTitles
    public var background: SwitcherBackground
    public var highlight: SwitcherHighlight
    /// How frosted the glass looks, 0 (clearest) to 1 (nearly opaque). 0.5 matches the macOS app switcher.
    /// The defaults below are the author's chosen setup: large icons, the selected title only, clear glass.
    public var opacity: Double

    public init(size: SwitcherSize = .large, titles: SwitcherTitles = .selected, background: SwitcherBackground = .glass,
                highlight: SwitcherHighlight = .neutral, opacity: Double = 0) {
        self.size = size
        self.titles = titles
        self.background = background
        self.highlight = highlight
        self.opacity = min(max(opacity, 0), 1)
    }

    /// Alpha of the white (light mode) or black (dark mode) wash laid over the glass.
    public func washAlpha(dark: Bool) -> Double {
        dark ? 0.05 + 0.5 * opacity : 0.15 + 0.8 * opacity
    }

    /// Tile geometry in points. Medium with titles is the original 148 x 112 tile with a 64 pt icon.
    public var metrics: SwitcherMetrics {
        let icon: Double = switch size { case .small: 48; case .medium: 64; case .large: 80 }
        let font: Double = switch size { case .small: 11; case .medium: 12; case .large: 13 }
        let caption = titles == .selected ? font + 22 : 0
        guard titles == .all else {
            return SwitcherMetrics(tileWidth: icon + 32, tileHeight: icon + 32, icon: icon, iconBottom: 16, fontSize: font,
                                   captionHeight: caption)
        }
        return SwitcherMetrics(tileWidth: (icon * 2.3125).rounded(), tileHeight: icon + 48, icon: icon, iconBottom: 34,
                               fontSize: font, captionHeight: 0)
    }
}

public struct SwitcherMetrics: Equatable, Sendable {
    public let tileWidth: Double
    public let tileHeight: Double
    public let icon: Double
    /// Distance from the tile's bottom edge to the icon; the title sits in the space below it.
    public let iconBottom: Double
    public let fontSize: Double
    /// Height of the strip under the grid that shows the selected window's title; 0 when there is none.
    public let captionHeight: Double
}
