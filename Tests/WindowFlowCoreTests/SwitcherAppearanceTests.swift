import Testing
@testable import WindowFlowCore

@Test func defaultsAreLargeClearGlassWithTheSelectedTitle() {
    let a = SwitcherAppearance()
    #expect(a.size == .large && a.titles == .selected && a.background == .glass && a.highlight == .neutral && a.opacity == 0)
}

@Test func mediumWithAllTitlesKeepsTheOriginalTile() {
    let m = SwitcherAppearance(size: .medium, titles: .all).metrics
    #expect(m.tileWidth == 148 && m.tileHeight == 112 && m.icon == 64 && m.fontSize == 12)
}

@Test func sizesScaleTheIcon() {
    #expect(SwitcherAppearance(size: .small).metrics.icon == 48)
    #expect(SwitcherAppearance(size: .large).metrics.icon == 80)
    #expect(SwitcherAppearance(size: .large, titles: .all).metrics.tileWidth > SwitcherAppearance(size: .medium, titles: .all).metrics.tileWidth)
}

@Test func withoutTitlesTheTileHugsTheIcon() {
    let m = SwitcherAppearance(size: .medium, titles: .none).metrics
    #expect(m.tileWidth == 96 && m.tileHeight == 96)
    #expect(m.iconBottom == (m.tileHeight - m.icon) / 2)
    #expect(m.captionHeight == 0)
}

@Test func selectedTitleOnlyAddsACaptionStrip() {
    let m = SwitcherAppearance(size: .medium, titles: .selected).metrics
    #expect(m.tileWidth == 96 && m.tileHeight == 96)
    #expect(m.captionHeight > m.fontSize)
    #expect(SwitcherAppearance(titles: .all).metrics.captionHeight == 0)
}

@Test func opacityDrivesTheGlassWash() {
    #expect(abs(SwitcherAppearance(opacity: 0.5).washAlpha(dark: false) - 0.55) < 0.001)
    #expect(abs(SwitcherAppearance(opacity: 0.5).washAlpha(dark: true) - 0.3) < 0.001)
    #expect(SwitcherAppearance(opacity: 0).washAlpha(dark: false) < SwitcherAppearance(opacity: 1).washAlpha(dark: false))
    #expect(SwitcherAppearance(opacity: 2).opacity == 1)
    #expect(SwitcherAppearance(opacity: -1).opacity == 0)
}
