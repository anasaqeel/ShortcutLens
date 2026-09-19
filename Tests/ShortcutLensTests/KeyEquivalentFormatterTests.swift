import Testing
@testable import ShortcutLens

struct KeyEquivalentFormatterTests {
    @Test func plainCommandShortcut() {
        // AXMenuItemCmdModifiers == 0 means "Command only".
        let result = KeyEquivalentFormatter.format(cmdChar: "s", modifiers: 0, virtualKey: nil)
        #expect(result == "\u{2318}S")
    }

    @Test func shiftCommandShortcut() {
        let result = KeyEquivalentFormatter.format(cmdChar: "z", modifiers: 0x01, virtualKey: nil)
        #expect(result == "\u{21E7}\u{2318}Z")
    }

    @Test func allModifiers() {
        let result = KeyEquivalentFormatter.format(cmdChar: "d", modifiers: 0x01 | 0x02 | 0x04, virtualKey: nil)
        #expect(result == "\u{2303}\u{2325}\u{21E7}\u{2318}D")
    }

    @Test func noCommandBitOmitsCommandGlyph() {
        // bit 3 (0x08) means Command is explicitly NOT part of the shortcut.
        let result = KeyEquivalentFormatter.format(cmdChar: "?", modifiers: 0x08, virtualKey: nil)
        #expect(result == "?")
    }

    @Test func fallsBackToVirtualKeyWhenNoCmdChar() {
        let result = KeyEquivalentFormatter.format(cmdChar: nil, modifiers: 0, virtualKey: 126) // Up arrow
        #expect(result == "\u{2318}\u{2191}")
    }

    @Test func emptyCmdCharFallsBackToVirtualKey() {
        let result = KeyEquivalentFormatter.format(cmdChar: "", modifiers: 0, virtualKey: 53) // Escape
        #expect(result == "\u{2318}\u{238B}")
    }

    @Test func noShortcutInformationReturnsNil() {
        #expect(KeyEquivalentFormatter.format(cmdChar: nil, modifiers: nil, virtualKey: nil) == nil)
    }

    @Test func unknownVirtualKeyWithoutCmdCharReturnsNil() {
        #expect(KeyEquivalentFormatter.format(cmdChar: nil, modifiers: 0, virtualKey: 9999) == nil)
    }

    @Test func absurdlyLongCmdCharFromAnotherProcessIsCapped() {
        let result = KeyEquivalentFormatter.format(
            cmdChar: String(repeating: "X", count: 5_000),
            modifiers: 0,
            virtualKey: nil
        )
        #expect(result == "\u{2318}XXXX")
    }

    // AppKit reports arrows, F-keys and friends as Private Use Area
    // characters that no font can draw; rendering them raw produced "?".
    @Test func privateUseAreaArrowKeysBecomeArrowGlyphs() {
        let up = KeyEquivalentFormatter.format(cmdChar: "\u{F700}", modifiers: 0, virtualKey: nil)
        let left = KeyEquivalentFormatter.format(cmdChar: "\u{F702}", modifiers: 0x01, virtualKey: nil)

        #expect(up == "\u{2318}\u{2191}")
        #expect(left == "\u{21E7}\u{2318}\u{2190}")
    }

    @Test func privateUseAreaFunctionKeysBecomeFFNames() {
        #expect(KeyEquivalentFormatter.format(cmdChar: "\u{F704}", modifiers: 0x08, virtualKey: nil) == "F1")
        #expect(KeyEquivalentFormatter.format(cmdChar: "\u{F70E}", modifiers: 0x08, virtualKey: nil) == "F11")
    }

    @Test func controlCharactersBecomeTheirMacOSSymbols() {
        #expect(KeyEquivalentFormatter.format(cmdChar: "\u{1B}", modifiers: 0x08, virtualKey: nil) == "\u{238B}")
        #expect(KeyEquivalentFormatter.format(cmdChar: "\u{0D}", modifiers: 0, virtualKey: nil) == "\u{2318}\u{21A9}")
        #expect(KeyEquivalentFormatter.format(cmdChar: "\u{08}", modifiers: 0, virtualKey: nil) == "\u{2318}\u{232B}")
    }

    @Test func anUndrawableCharacterFallsBackToTheVirtualKey() {
        // Unmapped Private Use Area character, but a usable virtual key.
        let result = KeyEquivalentFormatter.format(cmdChar: "\u{F8FF}", modifiers: 0, virtualKey: 123)
        #expect(result == "\u{2318}\u{2190}")
    }

    @Test func noGlyphIsEverAQuestionMarkPlaceholder() {
        // Sweep the whole Private Use Area and the control range: nothing
        // may render as a raw, undrawable character.
        for value in Array(0x00...0x1F) + Array(0xE000...0xF8FF) {
            guard let scalar = Unicode.Scalar(UInt32(value)) else { continue }
            let result = KeyEquivalentFormatter.format(
                cmdChar: String(Character(scalar)),
                modifiers: 0,
                virtualKey: nil
            )
            guard let result else { continue }
            for element in result.elements {
                guard case .text(let text) = element else { continue }
                #expect(!text.unicodeScalars.contains {
                    $0.value < 0x20 || (0xE000...0xF8FF).contains($0.value)
                })
            }
        }
    }

    // macOS reports these two with encodings that don't match any ordinary
    // shortcut — verified by reading back what the system puts in its own
    // menus (Globe = modifier bit 0x10; Dictation = the 🎤 emoji).
    @Test func theGlobeModifierIsShownAsTheGlobeSymbol() {
        // "Emoji & Symbols": char 'E', modifiers 0x18 = Globe + no-Command.
        let result = KeyEquivalentFormatter.format(cmdChar: "E", modifiers: 0x18, virtualKey: nil)

        #expect(result?.elements.first == .symbol("globe"))
        #expect(result?.elements.count == 2)
        if case .text(let trailing) = result?.elements.last {
            #expect(trailing.contains("E"))
            #expect(!trailing.contains("\u{2318}")) // no ⌘, since 0x08 is set
        } else {
            Issue.record("expected a trailing text element")
        }
    }

    @Test func dictationsMicrophoneEmojiBecomesTheMicSymbol() {
        // "Start Dictation": char U+1F3A4, modifiers 0x08 (no Command).
        let result = KeyEquivalentFormatter.format(cmdChar: "\u{1F3A4}", modifiers: 0x08, virtualKey: 128)

        #expect(result?.elements == [.symbol("mic")])
    }

    @Test func aGlobeShortcutStillShowsItsOtherModifiers() {
        let result = KeyEquivalentFormatter.format(cmdChar: "A", modifiers: 0x10 | 0x01, virtualKey: nil)

        #expect(result?.elements.first == .symbol("globe"))
        // Globe, then ⇧ and ⌘ (0x08 not set), then the key.
        #expect(result?.plainText.contains("\u{21E7}") == true)
        #expect(result?.plainText.contains("\u{2318}") == true)
    }

    @Test func noSymbolIsEverRenderedAsAColourEmoji() {
        for (char, modifiers) in [("\u{1F3A4}", 0x08), ("E", 0x18)] {
            let result = KeyEquivalentFormatter.format(cmdChar: char, modifiers: modifiers, virtualKey: nil)
            for element in result?.elements ?? [] {
                guard case .text(let text) = element else { continue }
                // No emoji presentation characters should survive into text.
                #expect(!text.unicodeScalars.contains { $0.properties.isEmojiPresentation })
            }
        }
    }

    @Test func bareKeyWithNoModifiersAtAllIsStillShown() {
        // e.g. a menu item bound to a plain, unmodified key.
        let result = KeyEquivalentFormatter.format(cmdChar: "a", modifiers: 0x08, virtualKey: nil)
        #expect(result == "A")
    }
}
