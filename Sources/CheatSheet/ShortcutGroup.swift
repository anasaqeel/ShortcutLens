import Foundation

/// Shortcuts belonging to one menu, e.g. everything under "File".
struct ShortcutGroup: Identifiable, Hashable {
    let menuPath: String
    let entries: [ShortcutEntry]

    var id: String { menuPath }
}
