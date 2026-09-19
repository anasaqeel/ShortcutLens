import AppKit

/// Watches the global Command-key state and reports a "held alone for the
/// threshold duration" gesture, without ever intercepting or consuming a
/// single event.
///
/// Two deliberate security/robustness choices:
///
/// - **Observation only.** This uses `NSEvent.addGlobalMonitorForEvents`,
///   which can only *observe* events delivered to other applications, never
///   block or rewrite them. Normal Command-based shortcuts in every other
///   app keep working exactly as before, even while this monitor is active.
/// - **No keystroke content is ever read or stored.** For `.keyDown` this
///   monitor only needs to know that *some* non-modifier key was pressed, to
///   tell an actual shortcut (e.g. ⌘C) apart from an idle Command hold. It
///   never reads `event.characters` or `event.keyCode`, so nothing you type
///   is captured, logged, or retained.
///
/// All state here is only ever touched on the main actor: AppKit delivers
/// event-monitor callbacks on the main thread, and the pending-hold delay
/// uses `Task.sleep` (inheriting this type's main-actor isolation) rather
/// than a `Timer` on `RunLoop.main`, so it fires reliably even when nothing
/// else happens to be pumping the run loop (as in a unit test host).
@MainActor
final class GlobalCommandHoldMonitor {
    /// How long Command must be held alone before the cheat sheet appears.
    var holdThreshold: TimeInterval = 2.0

    /// Called once Command has been held alone for `holdThreshold`, with the
    /// app that was frontmost when Command went down.
    var onHoldThresholdReached: ((NSRunningApplication) -> Void)?

    /// Called as soon as Command is released.
    var onCommandReleased: (() -> Void)?

    /// Seam for unit tests, which can't rely on `NSWorkspace`'s notion of
    /// "frontmost application" being meaningful inside a command-line test
    /// process.
    var frontmostAppProvider: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isCommandDown = false
    private var pendingHoldTask: Task<Void, Never>?
    private var stuckKeyWatchdog: Task<Void, Never>?
    private var frontmostAppAtCommandDown: NSRunningApplication?

    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        // Also observe while our own app is key, so the gesture behaves
        // consistently if focus happens to be on our status item/menu.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        cancelPendingHold()
        stuckKeyWatchdog?.cancel()
        stuckKeyWatchdog = nil
        isCommandDown = false
    }

    /// Not private so unit tests can drive it directly with synthetic
    /// events, since the real global monitor can't be exercised in a test
    /// process without Accessibility permission.
    func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            let commandNowDown = event.modifierFlags.contains(.command)
            if commandNowDown && !isCommandDown {
                isCommandDown = true
                frontmostAppAtCommandDown = frontmostAppProvider()
                schedulePendingHold()
            } else if !commandNowDown && isCommandDown {
                releaseCommand()
            }
        case .keyDown:
            // A real key press while Command is down means the user is
            // using an actual shortcut, not idly holding Command to ask
            // for help — cancel the pending reveal (if it hasn't fired
            // yet) without inspecting which key it was.
            if isCommandDown {
                cancelPendingHold()
            }
        default:
            break
        }
    }

    private func schedulePendingHold() {
        cancelPendingHold()
        let threshold = holdThreshold
        pendingHoldTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(threshold))
            guard !Task.isCancelled else { return }
            self?.fireHoldThreshold()
        }
    }

    private func cancelPendingHold() {
        pendingHoldTask?.cancel()
        pendingHoldTask = nil
    }

    private func fireHoldThreshold() {
        pendingHoldTask = nil
        guard isCommandDown, let app = frontmostAppAtCommandDown else { return }
        startStuckKeyWatchdog()
        onHoldThresholdReached?(app)
    }

    private func releaseCommand() {
        isCommandDown = false
        cancelPendingHold()
        stuckKeyWatchdog?.cancel()
        stuckKeyWatchdog = nil
        onCommandReleased?()
    }

    /// Safety net for a missed key-up. If a `.flagsChanged` release event is
    /// ever dropped — a lost event, Accessibility permission revoked
    /// mid-gesture, a modal grab in another process — the full-screen
    /// overlay would otherwise stay up covering the whole display with no
    /// way to dismiss it. While it's visible, poll the real hardware
    /// modifier state and force the release path if Command isn't actually
    /// held any more.
    private func startStuckKeyWatchdog() {
        stuckKeyWatchdog?.cancel()
        stuckKeyWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, self.isCommandDown else { return }
                if !NSEvent.modifierFlags.contains(.command) {
                    self.releaseCommand()
                    return
                }
            }
        }
    }
}
