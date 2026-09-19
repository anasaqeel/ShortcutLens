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

    private func makeMonitor(threshold: TimeInterval = 0.05) -> GlobalCommandHoldMonitor {
        let monitor = GlobalCommandHoldMonitor()
        monitor.holdThreshold = threshold
        monitor.frontmostAppProvider = { .current }
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
}
