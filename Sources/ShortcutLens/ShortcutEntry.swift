import Foundation

/// A single keyboard shortcut, ready for display.
///
/// Instances are immutable value types so entries read from the Accessibility
/// API (untrusted, foreign-process data) can be freely copied, merged with
/// overrides and rendered without any shared mutable state.
struct ShortcutEntry: Identifiable, Hashable, Codable {
    /// Top-level menu this shortcut lives under, e.g. "File" or "Format".
    let menuPath: String
    /// The menu item's title, e.g. "New Window".
    let title: String
    /// Pre-formatted key combination, e.g. "⇧⌘N".
    let keys: KeyCombination

    var id: String { menuPath + "\u{0}" + title }
}
