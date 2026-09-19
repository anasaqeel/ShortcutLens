import AppKit
import SwiftUI

/// An `NSPanel` that can never take keyboard focus or activate the app.
///
/// The cheat sheet is purely informational and transient — it must not steal
/// focus from whatever the user was doing, must not appear in Cmd-Tab / the
/// Dock, and must never be able to intercept keystrokes meant for the app
/// underneath it.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the overlay window and the SwiftUI content inside it.
///
/// The window is sized to its content rather than to a fixed rectangle, so a
/// small app gets a small sheet and an app with a huge menu bar gets a large
/// one — up to the usable screen area — instead of everything being crammed
/// into a scroll view.
@MainActor
final class CheatSheetWindowController {
    /// Margin left between the sheet and the edges of the usable screen.
    private static let screenMargin: CGFloat = 20

    private var panel: OverlayPanel?
    private var hostingView: NSHostingView<CheatSheetView>?

    /// Shows the sheet immediately at its final size, so the 2-second wait
    /// isn't followed by another visible delay — and so the window never
    /// resizes or jumps once the shortcuts arrive.
    func showLoading(appName: String, appIcon: NSImage?) {
        let view = CheatSheetView(appName: appName, appIcon: appIcon, plan: nil, state: .loading)
        let screen = NSScreen.main ?? NSScreen.screens.first
        present(view: view, contentSize: CheatSheetLayout.contentSize(available: Self.availableSize(for: screen)))
    }

    /// Replaces the sheet's content once shortcuts have been read. The window
    /// keeps the size it was shown at. If the user has already released
    /// Command, `hide()` will have torn the panel down and this is a no-op.
    func update(appName: String, appIcon: NSImage?, groups: [ShortcutGroup], state: CheatSheetView.State) {
        guard let panel else { return }

        let plan: CheatSheetLayout.Plan?
        if state == .loaded && !groups.isEmpty {
            plan = CheatSheetLayout.plan(groups: groups, available: Self.availableSize(for: panel.screen))
        } else {
            plan = nil
        }

        hostingView?.rootView = CheatSheetView(
            appName: appName,
            appIcon: appIcon,
            plan: plan,
            state: state
        )
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    private static func availableSize(for screen: NSScreen?) -> CGSize {
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(
            width: visible.width - (screenMargin * 2),
            height: visible.height - (screenMargin * 2)
        )
    }

    private static func centeredFrame(size: CGSize, on screen: NSScreen?) -> NSRect {
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(size.width, visible.width - (screenMargin * 2))
        let height = min(size.height, visible.height - (screenMargin * 2))
        return NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func present(view: CheatSheetView, contentSize: CGSize) {
        hide() // never leave a previous panel orphaned on screen

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = Self.centeredFrame(size: contentSize, on: screen)

        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = panel.contentView?.bounds ?? frame
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.orderFrontRegardless() // shows the panel without activating our app or stealing focus

        self.panel = panel
        self.hostingView = hostingView
    }
}
