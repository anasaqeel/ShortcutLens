import AppKit

// A `@main` entry point (rather than a `main.swift` script) so this file can
// be explicitly `@MainActor`-isolated under Swift 6 strict concurrency,
// while all real logic stays in separately testable types.
@main
enum CheatSheetApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, no app menu — matches LSUIElement
        app.run()
    }
}
