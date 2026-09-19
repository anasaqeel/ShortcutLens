import Foundation

/// Turns the raw values the Accessibility API reports for a menu item's key
/// equivalent into the same glyphs macOS itself shows in its menu bar.
///
/// The `AXMenuItemCmdModifiers` bitmask is not formally documented by Apple,
/// but its meaning has been stable across macOS releases and is relied on by
/// several shipping accessibility tools:
///   bit 0 (0x01) = Shift is part of the shortcut
///   bit 1 (0x02) = Option is part of the shortcut
///   bit 2 (0x04) = Control is part of the shortcut
///   bit 3 (0x08) = Command is *not* part of the shortcut (it is included by default)
enum KeyEquivalentFormatter {
    private struct ModifierBits {
        static let shift = 0x01
        static let option = 0x02
        static let control = 0x04
        static let noCommand = 0x08
        /// The Globe (fn) key, used by shortcuts like Emoji & Symbols
        /// (reported as `0x18`: Globe set, Command cleared). Undocumented
        /// like the rest of the mask, and confirmed by reading back what
        /// macOS reports for its own menu items.
        static let function = 0x10
    }

    /// macOS reports Dictation's key as the microphone *emoji*, but draws it
    /// in the menu as the mic key legend. Substitute the SF Symbol so it
    /// matches the keyboard, rather than showing a colour emoji.
    private static let symbolSubstitutions: [UInt32: String] = [
        0x1F3A4: "mic",
    ]

    /// Characters that have no printable glyph and must be substituted.
    ///
    /// Two families show up in `AXMenuItemCmdChar`:
    ///
    /// - **ASCII control codes** — tab, return, escape and friends.
    /// - **AppKit's function-key constants**, which live in the Unicode
    ///   Private Use Area (`U+F700`–`U+F8FF`; `NSUpArrowFunctionKey` and
    ///   company). No font defines glyphs for these, so rendering one
    ///   directly produces the missing-character box or a literal "?".
    ///   Every arrow, F-key, Home/End and Page Up/Down shortcut in a typical
    ///   menu bar arrives this way, which is why so many entries showed as
    ///   "?" before they were mapped.
    private static let characterSymbols: [UInt32: String] = [
        0x03: "\u{2324}",   // enter          ⌤
        0x08: "\u{232B}",   // backspace      ⌫
        0x09: "\u{21E5}",   // tab            ⇥
        0x0A: "\u{21A9}",   // linefeed       ↩
        0x0D: "\u{21A9}",   // return         ↩
        0x19: "\u{21E4}",   // back-tab       ⇤
        0x1B: "\u{238B}",   // escape         ⎋
        0x20: "Space",
        0x7F: "\u{232B}",   // delete         ⌫

        0xF700: "\u{2191}", // NSUpArrowFunctionKey      ↑
        0xF701: "\u{2193}", // NSDownArrowFunctionKey    ↓
        0xF702: "\u{2190}", // NSLeftArrowFunctionKey    ←
        0xF703: "\u{2192}", // NSRightArrowFunctionKey   →
        0xF727: "Ins",      // NSInsertFunctionKey
        0xF728: "\u{2326}", // NSDeleteFunctionKey       ⌦
        0xF729: "\u{2196}", // NSHomeFunctionKey         ↖
        0xF72A: "\u{2196}", // NSBeginFunctionKey        ↖
        0xF72B: "\u{2198}", // NSEndFunctionKey          ↘
        0xF72C: "\u{21DE}", // NSPageUpFunctionKey       ⇞
        0xF72D: "\u{21DF}", // NSPageDownFunctionKey     ⇟
        0xF739: "\u{2327}", // NSClearLineFunctionKey    ⌧
        0xF746: "Help",     // NSHelpFunctionKey
    ]

    /// `NSF1FunctionKey` … `NSF35FunctionKey` are consecutive from here.
    private static let firstFunctionKey: UInt32 = 0xF704
    private static let lastFunctionKey: UInt32 = 0xF726

    /// Maps the non-printing virtual key codes menu items commonly bind to.
    /// Codes come from Carbon's HIToolbox `kVK_*` constants, hardcoded here
    /// so the target doesn't need to link the deprecated Carbon framework.
    private static let virtualKeySymbols: [Int: String] = [
        36: "\u{21A9}",   // kVK_Return        ↩
        48: "\u{21E5}",   // kVK_Tab           ⇥
        49: "Space",      // kVK_Space
        51: "\u{232B}",   // kVK_Delete        ⌫
        53: "\u{238B}",   // kVK_Escape        ⎋
        71: "\u{2327}",   // kVK_ANSI_KeypadClear ⌧
        76: "\u{2324}",   // kVK_ANSI_KeypadEnter ⌤
        115: "\u{2196}",  // kVK_Home          ↖
        116: "\u{21DE}",  // kVK_PageUp        ⇞
        117: "\u{2326}",  // kVK_ForwardDelete ⌦
        119: "\u{2198}",  // kVK_End           ↘
        121: "\u{21DF}",  // kVK_PageDown      ⇟
        123: "\u{2190}",  // kVK_LeftArrow     ←
        124: "\u{2192}",  // kVK_RightArrow    →
        125: "\u{2193}",  // kVK_DownArrow     ↓
        126: "\u{2191}",  // kVK_UpArrow       ↑
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// - Parameters:
    ///   - cmdChar: `AXMenuItemCmdCharAttribute` value, usually a single character.
    ///   - modifiers: `AXMenuItemCmdModifiersAttribute` bitmask.
    ///   - virtualKey: `AXMenuItemCmdVirtualKeyAttribute`, used when `cmdChar`
    ///     is missing or isn't something that can be drawn.
    /// - Returns: A combination like "⇧⌘Z", or `nil` if the item has no shortcut.
    static func format(cmdChar: String?, modifiers: Int?, virtualKey: Int?) -> KeyCombination? {
        guard let key = keyGlyph(cmdChar: cmdChar, virtualKey: virtualKey) else { return nil }

        let mods = modifiers ?? 0
        var elements: [KeyCombination.Element] = []

        // The Globe key is drawn first, as macOS does for "🌐 E".
        if mods & ModifierBits.function != 0 {
            elements.append(.symbol("globe"))
        }

        var modifierGlyphs = ""
        if mods & ModifierBits.control != 0 { modifierGlyphs += "\u{2303}" }   // ⌃
        if mods & ModifierBits.option != 0 { modifierGlyphs += "\u{2325}" }    // ⌥
        if mods & ModifierBits.shift != 0 { modifierGlyphs += "\u{21E7}" }     // ⇧
        if mods & ModifierBits.noCommand == 0 { modifierGlyphs += "\u{2318}" } // ⌘

        // A thin space keeps the Globe symbol from colliding with what
        // follows; the stacked ⌃⌥⇧⌘ glyphs are meant to sit flush.
        let leadingGap = elements.isEmpty ? "" : "\u{2009}"

        switch key {
        case .text(let text):
            // Items with no modifiers at all are legitimate (Space for Quick
            // Look, a bare Delete) — still show them rather than hiding a
            // real shortcut.
            elements.append(.text(leadingGap + modifierGlyphs + text))
        case .symbol(let name):
            if !modifierGlyphs.isEmpty || !leadingGap.isEmpty {
                elements.append(.text(leadingGap + modifierGlyphs))
            }
            elements.append(.symbol(name))
        }

        return KeyCombination(elements: elements)
    }

    private static func keyGlyph(cmdChar: String?, virtualKey: Int?) -> KeyCombination.Element? {
        if let cmdChar, let scalar = cmdChar.unicodeScalars.first {
            if let symbolName = symbolSubstitutions[scalar.value] {
                return .symbol(symbolName)
            }
            if let symbol = symbol(for: scalar) {
                return .text(symbol)
            }
            if isPrintable(scalar) {
                // Normally a single character, but the value comes from
                // another process — cap it so a bogus value can't dominate
                // the layout.
                return .text(String(cmdChar.prefix(4)).uppercased())
            }
            // Falls through: an unprintable character we have no symbol for
            // is better served by the virtual key code, if there is one.
        }
        if let virtualKey, let symbol = virtualKeySymbols[virtualKey] {
            return .text(symbol)
        }
        return nil
    }

    private static func symbol(for scalar: Unicode.Scalar) -> String? {
        if let symbol = characterSymbols[scalar.value] { return symbol }
        if (firstFunctionKey...lastFunctionKey).contains(scalar.value) {
            return "F\(scalar.value - firstFunctionKey + 1)"
        }
        return nil
    }

    /// False for ASCII control codes and for anything in the Private Use
    /// Area, neither of which any font can draw.
    private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value < 0x20 || scalar.value == 0x7F { return false }
        if (0xE000...0xF8FF).contains(scalar.value) { return false }
        return true
    }
}
