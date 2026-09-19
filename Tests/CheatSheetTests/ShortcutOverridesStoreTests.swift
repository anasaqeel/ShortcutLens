import Testing
@testable import CheatSheet

struct ShortcutOverridesStoreTests {
    @Test func mergeAppendsNonMatchingOverrideAsAddition() {
        let live = [ShortcutEntry(menuPath: "File", title: "New", keys: "\u{2318}N")]
        let overrides = [ShortcutEntry(menuPath: "Global", title: "Quick Look", keys: "Space")]

        let merged = ShortcutOverridesStore.merge(liveEntries: live, overrides: overrides)

        #expect(merged.count == 2)
        #expect(merged.contains { $0.title == "New" })
        #expect(merged.contains { $0.title == "Quick Look" })
    }

    @Test func mergeReplacesMatchingLiveEntry() {
        let live = [ShortcutEntry(menuPath: "File", title: "New", keys: "\u{2318}N")]
        let overrides = [ShortcutEntry(menuPath: "File", title: "New", keys: "\u{21E7}\u{2318}N")]

        let merged = ShortcutOverridesStore.merge(liveEntries: live, overrides: overrides)

        #expect(merged.count == 1)
        #expect(merged.first?.keys == "\u{21E7}\u{2318}N")
    }

    @Test func mergePreservesLiveOrderingForUnaffectedEntries() {
        let live = [
            ShortcutEntry(menuPath: "File", title: "New", keys: "\u{2318}N"),
            ShortcutEntry(menuPath: "File", title: "Open", keys: "\u{2318}O"),
            ShortcutEntry(menuPath: "File", title: "Close", keys: "\u{2318}W")
        ]
        let overrides = [ShortcutEntry(menuPath: "File", title: "Open", keys: "\u{21E7}\u{2318}O")]

        let merged = ShortcutOverridesStore.merge(liveEntries: live, overrides: overrides)

        #expect(merged.map(\.title) == ["New", "Open", "Close"])
        #expect(merged[1].keys == "\u{21E7}\u{2318}O")
    }

    @Test func mergeWithNoOverridesReturnsLiveEntriesUnchanged() {
        let live = [ShortcutEntry(menuPath: "File", title: "New", keys: "\u{2318}N")]
        #expect(ShortcutOverridesStore.merge(liveEntries: live, overrides: []) == live)
    }

    @Test func unknownBundleIdentifierHasNoOverrides() {
        #expect(ShortcutOverridesStore.overrides(forBundleIdentifier: "com.example.doesnotexist") == [])
    }

    @Test func nilBundleIdentifierHasNoOverrides() {
        #expect(ShortcutOverridesStore.overrides(forBundleIdentifier: nil) == [])
    }

    @Test func bundledTerminalOverridesLoadSuccessfully() {
        // Sanity check that the bundled overrides.json ships correctly and
        // decodes into the expected shape.
        let terminalOverrides = ShortcutOverridesStore.overrides(forBundleIdentifier: "com.apple.Terminal")
        #expect(!terminalOverrides.isEmpty)
    }
}
