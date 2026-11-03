public enum SwitcherGrid {
    /// How many items of `item` points, `spacing` apart, fit in `extent` with `padding` on both ends (at least 1).
    public static func fit(extent: Double, item: Double, spacing: Double, padding: Double) -> Int {
        max(1, Int((extent - 2 * padding + spacing) / (item + spacing)))
    }

    /// Columns for `count` items when at most `fit` fit in a row: the fewest rows, filled as evenly as possible,
    /// so 10 items with room for 9 become two rows of 5 instead of 9 and 1.
    public static func columns(count: Int, fit: Int) -> Int {
        guard count > 0 else { return 1 }
        let fit = max(1, fit)
        let rows = (count + fit - 1) / fit
        return (count + rows - 1) / rows
    }
}
