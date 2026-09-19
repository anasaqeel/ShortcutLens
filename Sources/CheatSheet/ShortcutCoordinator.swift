import AppKit

/// Glues the hold-gesture monitor, the (potentially slow) Accessibility
/// read, and the overlay window together.
///
/// The Accessibility read always happens on a background queue so a slow
/// target app can never freeze the main thread or the overlay's own
/// animations. `readGeneration` guards against a slow read finishing *after*
/// the user has already released Command (or re-triggered the gesture for a
/// different app) — its result is simply discarded rather than popping the
/// overlay back up unexpectedly.
@MainActor
final class ShortcutCoordinator {
    private let overlay = CheatSheetWindowController()
    private var readGeneration = UUID()

    func present(for app: NSRunningApplication) {
        let generation = UUID()
        readGeneration = generation

        overlay.showLoading(appName: app.localizedName ?? "This App", appIcon: app.icon)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = MenuBarShortcutReader.read(app: app)
            let overrides = ShortcutOverridesStore.overrides(forBundleIdentifier: app.bundleIdentifier)
            let merged = ShortcutOverridesStore.merge(liveEntries: result.entries, overrides: overrides)
            let groups = Self.grouped(merged)

            DispatchQueue.main.async {
                guard let self, self.readGeneration == generation else { return }
                self.overlay.update(
                    appName: result.appName,
                    appIcon: app.icon,
                    groups: groups,
                    state: result.hasAccessibilityPermission ? .loaded : .needsPermission
                )
            }
        }
    }

    func dismiss() {
        readGeneration = UUID()
        overlay.hide()
    }

    nonisolated static func grouped(_ entries: [ShortcutEntry]) -> [ShortcutGroup] {
        var order: [String] = []
        var buckets: [String: [ShortcutEntry]] = [:]
        for entry in entries {
            if buckets[entry.menuPath] == nil { order.append(entry.menuPath) }
            buckets[entry.menuPath, default: []].append(entry)
        }
        return order.map { ShortcutGroup(menuPath: $0, entries: buckets[$0] ?? []) }
    }
}
