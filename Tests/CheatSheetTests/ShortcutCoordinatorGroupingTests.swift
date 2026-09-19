import Testing
@testable import CheatSheet

struct ShortcutCoordinatorGroupingTests {
    @Test func groupsEntriesByMenuPathPreservingFirstSeenOrder() {
        let entries = [
            ShortcutEntry(menuPath: "Edit", title: "Copy", keys: "\u{2318}C"),
            ShortcutEntry(menuPath: "File", title: "New", keys: "\u{2318}N"),
            ShortcutEntry(menuPath: "Edit", title: "Paste", keys: "\u{2318}V"),
            ShortcutEntry(menuPath: "File", title: "Open", keys: "\u{2318}O")
        ]

        let groups = ShortcutCoordinator.grouped(entries)

        #expect(groups.map(\.menuPath) == ["Edit", "File"])
        #expect(groups[0].entries.map(\.title) == ["Copy", "Paste"])
        #expect(groups[1].entries.map(\.title) == ["New", "Open"])
    }

    @Test func emptyInputProducesEmptyGroups() {
        #expect(ShortcutCoordinator.grouped([]).isEmpty)
    }
}
