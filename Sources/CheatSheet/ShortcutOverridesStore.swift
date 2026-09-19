import Foundation

/// A small, bundled, read-only supplement to the live Accessibility-based
/// shortcut reader.
///
/// Some apps bind shortcuts that never appear as a menu key equivalent (they
/// handle the key press directly instead), so `MenuBarShortcutReader` alone
/// can miss them. `overrides.json` lets us hand-add or relabel a handful of
/// well-known entries per app, keyed by bundle identifier.
///
/// The file ships inside the app bundle; it is never fetched from the
/// network and never written to, so there is no path for it to be tampered
/// with at runtime. Parsing still fails closed: any malformed or unexpected
/// JSON simply yields no overrides rather than crashing the app.
enum ShortcutOverridesStore {
    private static let cache: [String: [ShortcutEntry]] = loadBundledOverrides()

    /// Overrides declared for `bundleIdentifier`, or an empty array if none exist.
    static func overrides(forBundleIdentifier bundleIdentifier: String?) -> [ShortcutEntry] {
        guard let bundleIdentifier else { return [] }
        return cache[bundleIdentifier] ?? []
    }

    /// Merges Accessibility-derived entries with any bundled overrides for
    /// the same app. An override whose (menuPath, title) matches a live
    /// entry replaces it (e.g. to relabel or correct it); an override with
    /// no matching live entry is appended as an addition.
    static func merge(liveEntries: [ShortcutEntry], overrides: [ShortcutEntry]) -> [ShortcutEntry] {
        guard !overrides.isEmpty else { return liveEntries }

        var byID: [String: ShortcutEntry] = [:]
        var order: [String] = []
        for entry in liveEntries {
            byID[entry.id] = entry
            order.append(entry.id)
        }
        for override in overrides {
            if byID[override.id] == nil {
                order.append(override.id)
            }
            byID[override.id] = override
        }
        return order.compactMap { byID[$0] }
    }

    private static func loadBundledOverrides() -> [String: [ShortcutEntry]] {
        guard let url = Bundle.module.url(forResource: "overrides", withExtension: "json") else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: [ShortcutEntry]].self, from: data)
        } catch {
            // A malformed bundled resource is a build-time bug, not a
            // runtime condition worth crashing over for the end user.
            FileHandle.standardError.write(Data("CheatSheet: failed to load overrides.json: \(error)\n".utf8))
            return [:]
        }
    }
}
