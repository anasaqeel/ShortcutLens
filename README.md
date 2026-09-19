# CheatSheet

Hold **⌘** for two seconds in any Mac app, and a sheet appears showing that
app's keyboard shortcuts — read live from its own menu bar. Let go and it
disappears.

No configuration, no per-app setup, and nothing to maintain: the shortcuts
come from whatever app you happen to be using, so it works with apps that
didn't exist when this was written.

- **Works in any app.** Shortcuts are read from the frontmost app's real menu
  bar through the macOS Accessibility API, not from a bundled list.
- **Stays out of the way.** Holding ⌘ and pressing another key — an ordinary
  shortcut like ⌘C — cancels the sheet, so normal typing is unaffected. The
  overlay never takes keyboard focus.
- **Follows your theme.** Light and Dark Mode are handled by using system
  materials and semantic colours, with no theme switching logic.
- **Private by construction.** No network access of any kind, and keystrokes
  are never read, logged or stored. See [Privacy and security](#privacy-and-security).

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon or Intel
- Xcode Command Line Tools — `xcode-select --install`

## Install

There is no prebuilt download. Distributing a Mac app so that it opens
without Gatekeeper warnings requires an Apple Developer ID certificate and
notarization, and shipping an *unnotarized* app that asks for Accessibility
access is exactly the pattern you should be suspicious of. Building it
yourself takes one command and means you can read what you're granting
access to.

```sh
git clone https://github.com/<your-username>/CheatSheet.git
cd CheatSheet
./Scripts/create_signing_identity.sh   # once — see Signing below
./Scripts/build_app.sh --install       # builds and installs to /Applications
```

Then open **System Settings → Privacy & Security → Accessibility**, add
`/Applications/CheatSheet.app`, and switch it on. Relaunch the app
afterwards — macOS only tells a process about the permission at launch.

A menu bar icon lets you re-check permission, toggle Launch at Login, or
quit.

### Signing

`create_signing_identity.sh` creates a self-signed code-signing certificate
in your login keychain and the build signs with it. This is not about
distribution — it's about the app keeping a *stable identity*.

With ad-hoc signing (`codesign --sign -`), macOS derives the app's identity
from a hash of the binary, so every rebuild looks like a brand-new app and
silently loses the Accessibility permission you granted. A fixed certificate
produces a stable designated requirement, so the grant survives rebuilds.
The key never leaves your Mac.

> **Always run the app from `/Applications`.** Launched from an ordinary
> folder, an app signed this way is subject to *App Translocation*: macOS
> runs it from a randomised read-only copy under
> `/private/var/folders/.../AppTranslocation/<uuid>/` whose path changes on
> every launch, so Accessibility permission can never stick. `--install`
> handles this for you.

## How it works

| Component | Responsibility |
|---|---|
| [`GlobalCommandHoldMonitor`](Sources/CheatSheet/GlobalCommandHoldMonitor.swift) | Detects "⌘ held alone for 2s" by *observing* events — it can't intercept or block them, so other apps' shortcuts are untouched. |
| [`MenuBarShortcutReader`](Sources/CheatSheet/MenuBarShortcutReader.swift) | Walks the frontmost app's menu bar over the Accessibility API, with per-call and overall timeouts plus depth/count caps. |
| [`KeyEquivalentFormatter`](Sources/CheatSheet/KeyEquivalentFormatter.swift) | Decodes the undocumented `AXMenuItemCmdModifiers` bitmask and turns key characters into the glyphs macOS itself draws. |
| [`ShortcutOverridesStore`](Sources/CheatSheet/ShortcutOverridesStore.swift) | Merges a small bundled `overrides.json` for shortcuts that aren't exposed as menu items. |
| [`CheatSheetLayout`](Sources/CheatSheet/CheatSheetLayout.swift) | Packs everything into a fixed-size four-column sheet, flowing menus across columns and stepping down through three text densities so it fits without scrolling. |
| [`CheatSheetWindowController`](Sources/CheatSheet/CheatSheetWindowController.swift) | A borderless, non-activating panel that can never become key or steal focus. |

Two details worth knowing if you're reading the code:

- **Menu items aren't filtered by `AXEnabled`.** Items frequently report as
  disabled until their menu has been opened at least once, which would leave
  the sheet nearly empty for most apps.
- **Some keys have no drawable character.** Arrows, F-keys and similar arrive
  as AppKit's function-key constants in the Unicode Private Use Area
  (`U+F700`–`U+F8FF`), which render as `?`; Dictation arrives as the 🎤
  emoji; and the Globe/fn key is modifier bit `0x10`. These are substituted
  with SF Symbols or proper glyphs.

## Development

```sh
./Scripts/run_tests.sh          # unit tests
./Scripts/build_app.sh          # build to dist/ without installing
swift Scripts/make_icon.swift   # regenerate Resources/AppIcon.icns
```

`run_tests.sh` wraps `swift test`, adding the framework and rpath flags
swift-testing needs on machines that have the Command Line Tools but not
full Xcode.

The tests cover the pure logic: key formatting, the override merge rules,
hold/cancel/release timing (using synthetic `NSEvent`s and an injected
frontmost-app provider), and layout packing. They deliberately don't drive
the real global monitor or read a live app's menu bar — both need
Accessibility permission and a GUI session, so verify those by hand:

1. Hold ⌘ for two seconds over another app — the sheet should appear.
2. Release ⌘ — it should disappear immediately.
3. Press ⌘C quickly — the sheet must *not* appear, and copy must still work.
4. Switch between Light and Dark Mode and check the sheet follows.

## Privacy and security

- **Read-only.** The app only reads Accessibility data (menu titles and key
  equivalents) and observes the ⌘ key's state. It never synthesises
  keystrokes, sends Apple Events, or modifies another app.
- **Not a keylogger.** To tell a real shortcut from an idle ⌘ hold it only
  needs to know that *some* key was pressed. It never reads
  `event.characters` or `event.keyCode`, so what you type is never captured.
- **No network, no analytics, no persistence** beyond the Launch at Login
  registration you opt into from the menu bar.
- **Hostile input is bounded.** Menu data comes from other processes, so
  every Accessibility call is time-limited, the tree walk is depth- and
  count-capped, and strings are length-capped — a frozen, enormous or
  malicious app can't hang the sheet or exhaust memory.
- The bundled `overrides.json` is read-only inside the app bundle: it is
  never fetched remotely and never written to.

## Limitations

- Only shortcuts that appear in an app's menu bar are discovered. Anything
  bound purely in-app (many of VS Code's, for instance) won't show unless
  added to `overrides.json`.
- On a laptop display, apps with very large menu bars (Xcode) still need to
  scroll; the layout widens to six columns before that happens.
- The signing certificate is local and self-signed. Sharing the built app
  with other people would need a Developer ID certificate and notarization.

## License

[MIT](LICENSE)
