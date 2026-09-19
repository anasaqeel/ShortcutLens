import Testing
import AppKit
@testable import ShortcutLens

@MainActor
struct GlobalCommandHoldMonitorTests {
    private func flagsChangedEvent(commandDown: Bool) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: commandDown ? [.command] : [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 55 // kVK_Command
        )!
    }

    private func keyDownEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8 // kVK_ANSI_C
        )!
    }

    /// Stands in for the physical ⌘ key the stuck-key watchdog polls. It
    /// defaults to held: the real hardware is never held in a test process,
    /// which would otherwise let the watchdog end every gesture on its own.
    final class PhysicalKey {
        var isHeld = true
    }

    private func makeMonitor(threshold: TimeInterval = 0.05, key: PhysicalKey? = nil) -> GlobalCommandHoldMonitor {
        let key = key ?? PhysicalKey()
        let monitor = GlobalCommandHoldMonitor()
        monitor.holdThreshold = threshold
        monitor.frontmostAppProvider = { .current }
        monitor.isCommandPhysicallyDown = { key.isHeld }
        monitor.watchdogInterval = .milliseconds(20)
        return monitor
    }

    @Test func holdingCommandAloneFiresAfterThreshold() async {
        let monitor = makeMonitor()
        await confirmation { thresholdReached in
            monitor.onHoldThresholdReached = { app in
                #expect(app.processIdentifier == NSRunningApplication.current.processIdentifier)
                thresholdReached()
            }
            monitor.handle(flagsChangedEvent(commandDown: true))
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    @Test func pressingAnotherKeyCancelsTheHold() async {
        let monitor = makeMonitor()
        await confirmation(expectedCount: 0) { thresholdReached in
            monitor.onHoldThresholdReached = { _ in thresholdReached() }

            monitor.handle(flagsChangedEvent(commandDown: true))
            monitor.handle(keyDownEvent()) // simulates e.g. Cmd+C, a real shortcut
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    @Test func releasingCommandBeforeThresholdCancelsTheHold() async {
        let monitor = makeMonitor()
        await confirmation(expectedCount: 0) { thresholdReached in
            await confirmation { released in
                monitor.onHoldThresholdReached = { _ in thresholdReached() }
                monitor.onCommandReleased = { released() }

                monitor.handle(flagsChangedEvent(commandDown: true))
                monitor.handle(flagsChangedEvent(commandDown: false))
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    @Test func releasingCommandAfterThresholdInvokesReleaseCallback() async {
        let monitor = makeMonitor()

        await confirmation { thresholdReached in
            monitor.onHoldThresholdReached = { _ in thresholdReached() }
            monitor.handle(flagsChangedEvent(commandDown: true))
            try? await Task.sleep(for: .milliseconds(300))
        }

        await confirmation { released in
            monitor.onCommandReleased = { released() }
            monitor.handle(flagsChangedEvent(commandDown: false))
        }
    }

    // The watchdog exists so a dropped key-up can't leave the sheet stuck on
    // screen. Both halves matter: it must rescue a missed release, and it
    // must never dismiss the sheet while ⌘ really is still held.

    @Test func aMissedKeyUpIsCaughtByTheWatchdog() async {
        let key = PhysicalKey()
        let monitor = makeMonitor(key: key)

        await confirmation { thresholdReached in
            monitor.onHoldThresholdReached = { _ in thresholdReached() }
            monitor.handle(flagsChangedEvent(commandDown: true))
            try? await Task.sleep(for: .milliseconds(150))
        }

        // The user lets go, but the release event never arrives.
        await confirmation { released in
            monitor.onCommandReleased = { released() }
            key.isHeld = false
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    @Test func theWatchdogLeavesAGenuinelyHeldKeyAlone() async {
        let monitor = makeMonitor(key: PhysicalKey())

        await confirmation(expectedCount: 0) { released in
            monitor.onCommandReleased = { released() }
            monitor.handle(flagsChangedEvent(commandDown: true))
            // Past the threshold and through many watchdog checks.
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}
