import CoreGraphics

/// Arranges every shortcut into a fixed four-column sheet.
///
/// The sheet deliberately has the *same* shape every time it appears — same
/// width, same height, same four columns — so it reads as one consistent
/// surface rather than a window that jumps around depending on which app is
/// frontmost. Only the content flows.
///
/// Fitting everything into those four columns without scrolling relies on
/// two things:
///
/// - **Menus flow across columns.** Treating each menu as an indivisible
///   block wastes most of a column whenever the next menu is slightly too
///   tall to follow it. A menu that doesn't fit is continued in the next
///   column under a "(cont.)" heading instead.
/// - **A denser row style as a fallback.** Apps with enormous menu bars
///   (Xcode, VS Code) switch to tighter rows before scrolling is considered.
///
/// Heights are computed from the same metrics the SwiftUI view renders with,
/// so the two stay in step; `Density` is the single source of truth.
enum CheatSheetLayout {
    /// What the sheet uses for any app whose menu bar fits in it — which is
    /// most of them — so the layout reads the same from app to app.
    static let columnCount = 4
    /// Menu bars as large as VS Code's or Xcode's can't fit four columns on
    /// a laptop display without shrinking the text past readability. Adding
    /// columns is the lesser evil: the sheet stays exactly the same size,
    /// and it's still one glance rather than a scroll.
    private static let columnCountsToTry = [columnCount, 5, 6]

    struct Density {
        let rowHeight: CGFloat
        let rowVerticalPadding: CGFloat
        /// Menu title, its underline, and the space beneath it.
        let groupHeaderHeight: CGFloat
        let cardVerticalPadding: CGFloat
        let cardHorizontalPadding: CGFloat
        /// Width of the leading key-combination column.
        let keysColumnWidth: CGFloat
        let usesSmallText: Bool

        func cardHeight(rowCount: Int) -> CGFloat {
            cardChrome + (CGFloat(rowCount) * rowHeight)
        }

        /// Everything in a card that isn't a shortcut row.
        var cardChrome: CGFloat {
            (cardVerticalPadding * 2) + groupHeaderHeight
        }

        static let comfortable = Density(
            rowHeight: 26,
            rowVerticalPadding: 5,
            groupHeaderHeight: 30,
            cardVerticalPadding: 10,
            cardHorizontalPadding: 14,
            keysColumnWidth: 78,
            usesSmallText: false
        )

        static let compact = Density(
            rowHeight: 21,
            rowVerticalPadding: 2.5,
            groupHeaderHeight: 26,
            cardVerticalPadding: 8,
            cardHorizontalPadding: 11,
            keysColumnWidth: 70,
            usesSmallText: true
        )

        /// For menu bars as large as Xcode's or VS Code's, where the choice
        /// is between small text and scrolling — and a sheet you have to
        /// scroll isn't a glance.
        static let dense = Density(
            rowHeight: 17,
            rowVerticalPadding: 1,
            groupHeaderHeight: 22,
            cardVerticalPadding: 5,
            cardHorizontalPadding: 9,
            keysColumnWidth: 64,
            usesSmallText: true
        )
    }

    enum Chrome {
        static let outerPadding: CGFloat = 22
        static let headerHeight: CGFloat = 34
        static let headerBottomSpacing: CGFloat = 16
        static let columnSpacing: CGFloat = 18
        /// The bold, ruled menu heading already separates stacked menus, so
        /// this only needs to be enough to break the rhythm — spending more
        /// here costs rows that would otherwise avoid a scroll.
        static let cardSpacing: CGFloat = 12
    }

    /// Preferred sheet size, clamped to whatever the display allows. Large
    /// enough to hold a real app's menu bar at a glance, while still reading
    /// as a sheet floating over your work rather than a full-screen takeover.
    private static let preferredWidth: CGFloat = 1600
    private static let preferredWidthFraction: CGFloat = 0.96
    private static let preferredHeightFraction: CGFloat = 0.94
    private static let minimumHeight: CGFloat = 560

    /// Splitting a menu so only a row or two lands in a column looks like a
    /// mistake; below this, start the menu in the next column instead.
    private static let minRowsBeforeSplitting = 3

    struct Plan {
        let columns: [[ShortcutGroup]]
        let density: Density
        let columnWidth: CGFloat
        /// Size the window's content should be. Constant for a given display.
        let contentSize: CGSize
        /// True when even the densest layout overflowed, so the view keeps a
        /// scroll view as a last resort rather than hiding shortcuts.
        let needsScrolling: Bool
    }

    /// The sheet's size on a display with `available` usable space. Depends
    /// only on the screen — never on how many shortcuts an app has.
    static func contentSize(available: CGSize) -> CGSize {
        CGSize(
            width: min(min(preferredWidth, available.width * preferredWidthFraction), available.width),
            height: min(max(minimumHeight, available.height * preferredHeightFraction), available.height)
        )
    }

    static func columnWidth(forContentWidth width: CGFloat, columnCount: Int) -> CGFloat {
        let usable = width - (Chrome.outerPadding * 2)
            - (Chrome.columnSpacing * CGFloat(columnCount - 1))
        return max(120, usable / CGFloat(columnCount))
    }

    /// - Parameter available: the usable screen area minus the margin left
    ///   around the sheet.
    static func plan(groups: [ShortcutGroup], available: CGSize) -> Plan {
        let size = contentSize(available: available)
        let columnsHeight = size.height
            - Chrome.headerHeight - Chrome.headerBottomSpacing - (Chrome.outerPadding * 2)

        guard !groups.isEmpty else {
            return Plan(
                columns: [],
                density: .comfortable,
                columnWidth: columnWidth(forContentWidth: size.width, columnCount: columnCount),
                contentSize: size,
                needsScrolling: false
            )
        }

        // Preference order: exhaust the standard four columns — stepping the
        // text down a size if that's what it takes — before widening out to
        // five or six. Keeping the column count stable matters more than
        // keeping the text at its largest.
        for count in columnCountsToTry {
            let width = columnWidth(forContentWidth: size.width, columnCount: count)
            guard width >= Density.dense.keysColumnWidth + 80 else { continue } // room for a title
            for density in [Density.comfortable, Density.compact, Density.dense] {
                guard columnsHeight > density.cardChrome else { continue }
                if let columns = balanced(groups, into: count, maxHeight: columnsHeight, density: density) {
                    return Plan(
                        columns: columns,
                        density: density,
                        columnWidth: width,
                        contentSize: size,
                        needsScrolling: false
                    )
                }
            }
        }

        // More shortcuts than this display can show at once. Keep the same
        // sheet and scroll — but still spread the content evenly across the
        // columns rather than stacking it into one.
        let density = Density.dense
        let count = columnCountsToTry.last ?? columnCount
        return Plan(
            columns: balanced(groups, into: count, maxHeight: .greatestFiniteMagnitude, density: density)
                ?? [groups],
            density: density,
            columnWidth: columnWidth(forContentWidth: size.width, columnCount: count),
            contentSize: size,
            needsScrolling: true
        )
    }

    /// Flows groups into at most `count` columns of roughly equal height.
    ///
    /// Starting from an even split rather than from `maxHeight` is what
    /// makes a small app fill four balanced columns instead of packing into
    /// two full ones and leaving the rest of the sheet empty. The target is
    /// relaxed upward when rounding or the no-tiny-split rule spills into an
    /// extra column. Returns nil if it can't be done within `maxHeight`.
    private static func balanced(
        _ groups: [ShortcutGroup],
        into count: Int,
        maxHeight: CGFloat,
        density: Density
    ) -> [[ShortcutGroup]]? {
        let total = totalHeight(of: groups, density: density)
        let step = density.rowHeight * 2
        var target = max(density.cardHeight(rowCount: minRowsBeforeSplitting), total / CGFloat(count))

        // Bounded so an infinite `maxHeight` can't spin forever.
        for _ in 0..<512 {
            guard target <= maxHeight else { return nil }
            if let columns = flow(groups, into: count, columnHeight: target, density: density) {
                return columns
            }
            target += step
        }
        return nil
    }

    private static func totalHeight(of groups: [ShortcutGroup], density: Density) -> CGFloat {
        groups.reduce(CGFloat(0)) { $0 + height(of: $1, density: density) }
            + CGFloat(max(0, groups.count - 1)) * Chrome.cardSpacing
    }

    static func height(of group: ShortcutGroup, density: Density) -> CGFloat {
        density.cardHeight(rowCount: group.entries.count)
    }

    private static func continuationTitle(_ menuPath: String) -> String {
        menuPath.hasSuffix(" (cont.)") ? menuPath : menuPath + " (cont.)"
    }

    /// Packs groups into at most `count` columns of at most `columnHeight`,
    /// in menu order (down a column, then on to the next). A group that
    /// doesn't fit in the space left is split, with its remainder carried
    /// into the following column. Returns nil if it needs more columns.
    private static func flow(
        _ groups: [ShortcutGroup],
        into count: Int,
        columnHeight: CGFloat,
        density: Density
    ) -> [[ShortcutGroup]]? {
        var columns: [[ShortcutGroup]] = []
        var current: [ShortcutGroup] = []
        var used: CGFloat = 0
        var pending = groups
        var index = 0

        while index < pending.count {
            let group = pending[index]
            let spacing = current.isEmpty ? 0 : Chrome.cardSpacing
            let remaining = columnHeight - used - spacing
            let fullHeight = height(of: group, density: density)

            if fullHeight <= remaining {
                current.append(group)
                used += spacing + fullHeight
                index += 1
                continue
            }

            let rowsThatFit = Int((remaining - density.cardChrome) / density.rowHeight)
            if rowsThatFit >= minRowsBeforeSplitting && rowsThatFit < group.entries.count {
                current.append(ShortcutGroup(
                    menuPath: group.menuPath,
                    entries: Array(group.entries.prefix(rowsThatFit))
                ))
                pending[index] = ShortcutGroup(
                    menuPath: continuationTitle(group.menuPath),
                    entries: Array(group.entries.dropFirst(rowsThatFit))
                )
            } else if current.isEmpty {
                // Can't even place the minimum in a fresh column.
                return nil
            }

            columns.append(current)
            guard columns.count < count else { return nil }
            current = []
            used = 0
        }

        if !current.isEmpty { columns.append(current) }
        return columns.count <= count ? columns : nil
    }
}
