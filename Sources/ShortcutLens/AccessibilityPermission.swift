import AppKit
import ApplicationServices

/// Wraps the two things the app needs Accessibility permission for:
/// observing the global Command key state and reading another app's menu
/// bar. Both are read-only introspection — this app never posts synthetic
/// events, never sends Apple Events, and never simulates keystrokes.
enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows a plain-language explanation *before* triggering the system's
    /// own permission prompt, so the request in System Settings doesn't come
    /// out of nowhere. Safe to call repeatedly; it only prompts once the
    /// user hasn't already granted or explicitly denied access.
    @MainActor
    static func requestIfNeeded() {
        guard !isGranted else { return }

        let alert = NSAlert()
        alert.messageText = "Accessibility Access Needed"
        alert.informativeText = """
        Shortcut Lens reads the menu bar of the app you're using so it can \
        show its keyboard shortcuts. To do that, macOS requires \
        Accessibility permission.

        Shortcut Lens only reads menu titles and key equivalents. It never \
        records keystrokes, controls other apps, or sends any data over \
        the network.

        Click OK, then enable Shortcut Lens in the System Settings window \
        that appears.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        // Using the documented string value directly rather than the
        // imported `kAXTrustedCheckOptionPrompt` global, which the Swift 6
        // concurrency checker flags as unsafe shared mutable state even
        // though it's an immutable CF constant in practice.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
