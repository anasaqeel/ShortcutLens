import ApplicationServices
import AppKit

/// Reads the frontmost application's menu bar through the public
/// Accessibility API and turns it into a flat list of ``ShortcutEntry``.
///
/// This talks to a *foreign, untrusted process* over Mach IPC. Two defensive
/// measures matter here beyond correctness:
///
/// 1. **It must never hang the shortcut sheet.** If the target app is busy,
///    frozen, or intentionally slow-walking its AX tree, a synchronous
///    AXUIElement call can block indefinitely. We bound every round trip with
///    `AXUIElementSetMessagingTimeout` and additionally cap the whole read
///    with a wall-clock deadline enforced from the caller.
/// 2. **It must never trust the shape or size of the data it gets back.**
///    Menu depth and item counts are capped so a pathological or malicious
///    app cannot make us allocate unbounded memory or recurse without bound.
enum MenuBarShortcutReader {
    private static let maxDepth = 8
    private static let maxEntries = 2000
    /// Per-call AX messaging timeout, in seconds. Generous rather than tight:
    /// Electron-based apps (VS Code, Slack, ...) build their accessibility
    /// tree lazily, and the first few queries after launch can take most of a
    /// second. Too small a value here silently turns every attribute read
    /// into a failure, which shows up as an empty shortcut sheet.
    private static let axCallTimeout: Float = 1.0
    /// Wall-clock budget for the whole read. `axCallTimeout` alone only
    /// bounds a single round trip; a menu tree with thousands of items in an
    /// unresponsive app could otherwise still add up to minutes of blocking
    /// (item count × attributes per item × per-call timeout). This deadline
    /// is checked between calls so a slow app costs at most one extra
    /// `axCallTimeout` beyond the budget, not an unbounded amount.
    private static let overallDeadline: TimeInterval = 5.0

    struct ReadResult {
        let appName: String
        let entries: [ShortcutEntry]
        /// False when macOS hasn't granted Accessibility access, so the UI
        /// can say so instead of claiming the app has no shortcuts.
        let hasAccessibilityPermission: Bool

        static func denied(appName: String) -> ReadResult {
            ReadResult(appName: appName, entries: [], hasAccessibilityPermission: false)
        }
    }

    /// Synchronously reads `app`'s menu bar. Intended to be called off the
    /// main thread (see `ShortcutCoordinator`), since even with per-call
    /// timeouts this can take on the order of hundreds of milliseconds for
    /// apps with deep menus.
    static func read(app: NSRunningApplication) -> ReadResult {
        let appName = app.localizedName ?? "This application"
        guard AXIsProcessTrusted() else {
            return .denied(appName: appName)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, axCallTimeout)

        guard let menuBar = copyAttribute(axApp, kAXMenuBarAttribute),
              CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
            return ReadResult(appName: appName, entries: [], hasAccessibilityPermission: true)
        }
        let menuBarElement = menuBar as! AXUIElement // swiftlint:disable:this force_cast

        guard let topMenus = copyChildren(menuBarElement) else {
            return ReadResult(appName: appName, entries: [], hasAccessibilityPermission: true)
        }

        let deadline = Date().addingTimeInterval(overallDeadline)
        var entries: [ShortcutEntry] = []
        for topMenu in topMenus {
            guard entries.count < maxEntries, Date() < deadline else { break }
            guard let title = copyStringAttribute(topMenu, kAXTitleAttribute), !title.isEmpty else {
                continue
            }
            // The Apple menu is identical in every app and adds nothing
            // useful to an app-specific shortcut sheet.
            if title == "Apple" { continue }
            guard let submenuItems = copySubmenuItems(of: topMenu) else { continue }
            walk(items: submenuItems, menuPath: title, depth: 0, deadline: deadline, into: &entries)
        }

        return ReadResult(appName: appName, entries: entries, hasAccessibilityPermission: true)
    }

    private static func walk(
        items: [AXUIElement],
        menuPath: String,
        depth: Int,
        deadline: Date,
        into entries: inout [ShortcutEntry]
    ) {
        guard depth < maxDepth else { return }
        for item in items {
            guard entries.count < maxEntries, Date() < deadline else { return }

            if let submenuItems = copySubmenuItems(of: item) {
                let title = copyStringAttribute(item, kAXTitleAttribute) ?? menuPath
                walk(
                    items: submenuItems,
                    menuPath: "\(menuPath) \u{203A} \(title)",
                    depth: depth + 1,
                    deadline: deadline,
                    into: &entries
                )
                continue
            }

            guard let title = copyStringAttribute(item, kAXTitleAttribute), !title.isEmpty else { continue }

            // Deliberately *not* filtering on kAXEnabledAttribute: menu items
            // frequently report as disabled until their menu has actually been
            // opened at least once, which would leave the shortcut sheet nearly
            // empty for most apps. A shortcut that's momentarily unavailable is
            // still worth showing — and skipping the check saves an AX round
            // trip per item.
            let cmdChar = copyStringAttribute(item, "AXMenuItemCmdChar")
            let modifiers = copyIntAttribute(item, "AXMenuItemCmdModifiers")
            let virtualKey = copyIntAttribute(item, "AXMenuItemCmdVirtualKey")

            guard let keys = KeyEquivalentFormatter.format(
                cmdChar: cmdChar,
                modifiers: modifiers,
                virtualKey: virtualKey
            ) else { continue }

            entries.append(ShortcutEntry(menuPath: menuPath, title: truncated(title), keys: keys))
        }
    }

    /// Menu titles come from another process and can be arbitrarily long.
    /// They're only ever rendered as plain SwiftUI `Text` (so there's no
    /// injection surface), but bounding the length keeps a buggy or hostile
    /// app from blowing up the overlay's layout or memory use.
    private static func truncated(_ title: String) -> String {
        let maxTitleLength = 120
        guard title.count > maxTitleLength else { return title }
        return title.prefix(maxTitleLength) + "\u{2026}"
    }

    /// Returns the child menu items of `item`'s submenu, or `nil` if `item`
    /// has no submenu (i.e. it is a leaf/actionable item).
    private static func copySubmenuItems(of item: AXUIElement) -> [AXUIElement]? {
        guard let children = copyChildren(item) else { return nil }
        // A menu item's submenu, when present, is itself a single AXMenu
        // child that contains the actual AXMenuItem children.
        for child in children {
            if let role = copyStringAttribute(child, kAXRoleAttribute), role == kAXMenuRole as String {
                return copyChildren(child)
            }
        }
        return nil
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        guard let value = copyAttribute(element, kAXChildrenAttribute) else { return nil }
        return value as? [AXUIElement]
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private static func copyIntAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        guard let number = copyAttribute(element, attribute) as? NSNumber else { return nil }
        return number.intValue
    }
}
