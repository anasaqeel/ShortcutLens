import Foundation
import Testing
@testable import ShortcutLens

struct InstallLocationTests {
    @Test func aTranslocatedCopyIsTreatedAsTemporary() {
        let translocated = URL(fileURLWithPath:
            "/private/var/folders/ab/xyz/T/AppTranslocation/1234-ABCD/d/Shortcut Lens.app")

        #expect(InstallLocation.isTemporary(translocated))
    }

    // The other trigger — running from inside a mounted disk image, which
    // reports `volumeIsReadOnly` — needs a mounted image to exercise, so it's
    // verified against the real release DMG rather than in a unit test.

    @Test func theApplicationsFolderIsAPermanentInstall() {
        // Where the app is meant to live: it must never be refused there.
        #expect(!InstallLocation.isTemporary(URL(fileURLWithPath: "/Applications")))
    }

    @Test func aWritableFolderIsAPermanentInstall() {
        #expect(!InstallLocation.isTemporary(FileManager.default.temporaryDirectory))
    }
}
