import CoreGraphics
import Testing
@testable import ShortcutLens

struct ShortcutLensLayoutTests {
    /// Roughly a 16" laptop's usable area minus the window margin.
    private let laptopScreen = CGSize(width: 1630, height: 900)

    private func group(_ name: String, entries: Int) -> ShortcutGroup {
        ShortcutGroup(
            menuPath: name,
            entries: (0..<entries).map {
                ShortcutEntry(
                    menuPath: name,
                    title: "Item \($0)",
                    keys: KeyCombination(elements: [.text("\u{2318}\($0)")])
                )
            }
        )
    }

    private func totalEntries(_ plan: ShortcutLensLayout.Plan) -> Int {
        plan.columns.flatMap { $0 }.reduce(0) { $0 + $1.entries.count }
    }

    /// The sheet's own footprint is the thing that must never change — only
    /// its internal arrangement adapts.
    @Test func theSheetIsTheSameSizeRegardlessOfHowManyShortcutsAnAppHas() {
        let tiny = ShortcutLensLayout.plan(groups: [group("File", entries: 3)], available: laptopScreen)
        let huge = ShortcutLensLayout.plan(
            groups: (0..<12).map { group("Menu \($0)", entries: 20) },
            available: laptopScreen
        )

        #expect(tiny.contentSize == huge.contentSize)
    }

    @Test func ordinaryAppsAllGetTheStandardFourColumns() {
        for (menus, perMenu) in [(5, 8), (6, 10), (7, 12), (8, 14)] {
            let plan = ShortcutLensLayout.plan(
                groups: (0..<menus).map { group("Menu \($0)", entries: perMenu) },
                available: laptopScreen
            )
            #expect(plan.columns.count == ShortcutLensLayout.columnCount)
            #expect(!plan.needsScrolling)
        }
    }

    @Test func onlyAnOversizedMenuBarIsAllowedExtraColumns() {
        let plan = ShortcutLensLayout.plan(
            groups: (0..<20).map { group("Menu \($0)", entries: 15) },
            available: laptopScreen
        )
        // More than four is a deliberate last resort, but it stays bounded.
        #expect(plan.columns.count > ShortcutLensLayout.columnCount)
        #expect(plan.columns.count <= 6)
    }

    @Test func groupsAreLaidOutInMenuOrderTopToBottomThenLeftToRight() {
        let groups = (0..<6).map { group("Menu \($0)", entries: 12) }

        let plan = ShortcutLensLayout.plan(groups: groups, available: laptopScreen)

        // Reading down each column then across, and collapsing any
        // "(cont.)" continuations back onto their parent, should reproduce
        // the original menu-bar order.
        var readingOrder: [String] = []
        for group in plan.columns.flatMap({ $0 }) {
            let name = group.menuPath.replacingOccurrences(of: " (cont.)", with: "")
            if readingOrder.last != name { readingOrder.append(name) }
        }

        #expect(readingOrder == groups.map(\.menuPath))
    }

    @Test func aTypicalAppFitsWithoutScrolling() {
        // Safari-sized: 8 menus, ~14 shortcuts each.
        let groups = (0..<8).map { group("Menu \($0)", entries: 14) }

        let plan = ShortcutLensLayout.plan(groups: groups, available: laptopScreen)

        #expect(!plan.needsScrolling)
        #expect(plan.columns.count == ShortcutLensLayout.columnCount)
        #expect(totalEntries(plan) == 112)
    }

    @Test func aSmallAppStaysAtTheMostReadableDensity() {
        let groups = (0..<5).map { group("Menu \($0)", entries: 8) }

        let plan = ShortcutLensLayout.plan(groups: groups, available: laptopScreen)

        #expect(!plan.needsScrolling)
        #expect(plan.density.usesSmallText == false)
    }

    @Test func aMenuTallerThanOneColumnIsContinuedInTheNextInsteadOfOverflowing() {
        let plan = ShortcutLensLayout.plan(groups: [group("Edit", entries: 60)], available: laptopScreen)

        #expect(plan.columns.count > 1)
        #expect(totalEntries(plan) == 60) // nothing dropped
        #expect(plan.columns.flatMap { $0 }.contains { $0.menuPath.hasSuffix("(cont.)") })
    }

    @Test func aContinuationIsNeverLabelledTwice() {
        let plan = ShortcutLensLayout.plan(groups: [group("Edit", entries: 200)], available: laptopScreen)

        for group in plan.columns.flatMap({ $0 }) {
            let occurrences = group.menuPath.components(separatedBy: "(cont.)").count - 1
            #expect(occurrences <= 1)
        }
    }

    @Test func aBigMenuBarTradesTextSizeForFittingRatherThanScrollingStraightAway() {
        let roomy = ShortcutLensLayout.plan(
            groups: (0..<5).map { group("Menu \($0)", entries: 8) },
            available: laptopScreen
        )
        let crowded = ShortcutLensLayout.plan(
            groups: (0..<8).map { group("Menu \($0)", entries: 14) },
            available: laptopScreen
        )

        #expect(crowded.density.rowHeight < roomy.density.rowHeight)
        #expect(!crowded.needsScrolling)
    }

    @Test func columnsAreBalancedRatherThanPackedFullLeavingTheSheetLopsided() {
        // A small app should fill its columns evenly across the sheet, not
        // stuff the first columns full and leave the rest empty.
        let plan = ShortcutLensLayout.plan(
            groups: (0..<6).map { group("Menu \($0)", entries: 10) },
            available: laptopScreen
        )

        let heights = plan.columns.map { column in
            column.reduce(0.0) { $0 + ShortcutLensLayout.height(of: $1, density: plan.density) }
        }
        let shortest = heights.min() ?? 0
        let tallest = heights.max() ?? 1

        #expect(plan.columns.count == ShortcutLensLayout.columnCount)
        #expect(shortest > tallest * 0.5)
    }

    @Test func everyShortcutSurvivesLayoutEvenWhenItCannotAllFit() {
        // Far more than four columns can show: the planner must still account
        // for every entry rather than silently discarding the overflow.
        let groups = (0..<40).map { group("Menu \($0)", entries: 40) }

        let plan = ShortcutLensLayout.plan(groups: groups, available: laptopScreen)

        #expect(plan.needsScrolling)
        #expect(totalEntries(plan) == 1600)
        #expect(plan.columns.count <= 6)
    }

    @Test func theSheetShrinksToFitASmallDisplay() {
        let small = CGSize(width: 900, height: 600)
        let plan = ShortcutLensLayout.plan(groups: [group("File", entries: 6)], available: small)

        #expect(plan.contentSize.width <= small.width)
        #expect(plan.contentSize.height <= small.height)
        #expect(plan.columnWidth > 0)
    }

    @Test func noGroupsProducesNoColumnsButStillAStableSize() {
        let plan = ShortcutLensLayout.plan(groups: [], available: laptopScreen)

        #expect(plan.columns.isEmpty)
        #expect(plan.contentSize == ShortcutLensLayout.contentSize(available: laptopScreen))
    }
}
