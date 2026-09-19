import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private let monitor = GlobalCommandHoldMonitor()
    private let coordinator = ShortcutCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !terminateIfAlreadyRunning() else { return }

        // Agent apps (LSUIElement) don't get a Dock icon or app menu, so the
        // status item is the only UI surface — make sure it's there before
        // anything else.
        setUpStatusItem()

        monitor.onHoldThresholdReached = { [weak self] app in
            self?.coordinator.present(for: app)
        }
        monitor.onCommandReleased = { [weak self] in
            self?.coordinator.dismiss()
        }
        monitor.start()

        // Ask for Accessibility access after the UI exists, so there's
        // something on screen besides a system dialog appearing out of
        // nowhere at launch.
        AccessibilityPermission.requestIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    /// macOS normally prevents launching a second copy of the same bundle,
    /// but that check is by bundle *path* — and an ad-hoc signed app run from
    /// outside /Applications gets translocated to a fresh random path each
    /// launch, which defeats it. Two live copies means two global monitors
    /// racing to show two overlays, so bail out explicitly.
    private func terminateIfAlreadyRunning() -> Bool {
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.anasaqeel.ShortcutLens"
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == myBundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        guard !others.isEmpty else { return false }
        NSApp.terminate(nil)
        return true
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "command.square",
            accessibilityDescription: "Shortcut Lens"
        )

        let menu = NSMenu()
        menu.delegate = self

        let permissionItem = NSMenuItem(
            title: "",
            action: #selector(requestAccessibility),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)
        self.permissionItem = permissionItem

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginItem = launchAtLoginItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Shortcut Lens", action: #selector(quit), keyEquivalent: "q"))

        refreshMenuState()
        item.menu = menu
        statusItem = item
    }

    /// Permission and login-item state can both change outside the app (in
    /// System Settings), so refresh them each time the menu is opened rather
    /// than trusting whatever was true at launch.
    private func refreshMenuState() {
        let granted = AccessibilityPermission.isGranted
        permissionItem?.title = granted
            ? "Accessibility Access: Granted"
            : "Grant Accessibility Access\u{2026}"
        permissionItem?.isEnabled = !granted
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func requestAccessibility() {
        AccessibilityPermission.requestIfNeeded()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }
}
