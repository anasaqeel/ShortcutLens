import AppKit

/// Catches the one installation mistake that silently breaks the app:
/// opening it straight from the downloaded disk image instead of dragging it
/// into Applications first.
///
/// A copy run from a disk image lives on a read-only volume, and a quarantined
/// one is additionally *translocated* — run from a randomised read-only path
/// that changes on every launch. Either way, the Accessibility permission the
/// user grants can't stick, so they'd be asked for it again and again with no
/// explanation. Saying so plainly up front is far kinder.
enum InstallLocation {
    static func isTemporary(_ bundleURL: URL) -> Bool {
        if bundleURL.path.contains("/AppTranslocation/") {
            return true
        }
        let readOnly = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly
        return readOnly == true
    }

    /// Explains the problem and returns true when the app should quit rather
    /// than run from where it is.
    @MainActor
    static func refuseToRunFromTemporaryLocation() -> Bool {
        guard isTemporary(Bundle.main.bundleURL) else { return false }

        let alert = NSAlert()
        alert.messageText = "Move Shortcut Lens to Applications"
        alert.informativeText = """
        Shortcut Lens is running from the downloaded disk image, so macOS \
        can't remember the permission it needs.

        Drag Shortcut Lens into your Applications folder, then open it from \
        there.
        """
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        return true
    }
}
