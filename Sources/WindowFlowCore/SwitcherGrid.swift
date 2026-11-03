public enum SwitcherGrid {
    /// How many items of `item` points, `spacing` apart, fit in `extent` with `padding` on both ends (at least 1).
    public static func fit(extent: Double, item: Double, spacing: Double, padding: Double) -> Int {
        max(1, Int((extent - 2 * padding + spacing) / (item + spacing)))
    }
}
