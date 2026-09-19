import Foundation

/// A displayable key combination, e.g. "⇧⌘Z" or Globe-E.
///
/// Most shortcuts are plain text, but a few keys have no usable Unicode
/// character and must be drawn as SF Symbols instead:
///
/// - The **Globe (fn)** key, which macOS shows for shortcuts like Emoji &
///   Symbols. There is a 🌐 emoji, but it renders in colour and looks
///   nothing like the monochrome key legend.
/// - **Dictation**, which the Accessibility API reports as the 🎤 emoji
///   even though the menu itself draws the mic key symbol.
///
/// Hence elements rather than a `String`: the view substitutes an SF Symbol
/// matching the surrounding text's size and weight.
struct KeyCombination: Hashable, Codable {
    enum Element: Hashable, Codable {
        case text(String)
        /// An SF Symbol name.
        case symbol(String)
    }

    let elements: [Element]

    init(elements: [Element]) {
        self.elements = elements
    }

    /// Text-only rendering, for contexts that can't draw symbols.
    var plainText: String {
        elements.map { element in
            switch element {
            case .text(let text): return text
            case .symbol(let name): return Self.textFallbacks[name] ?? ""
            }
        }.joined()
    }

    private static let textFallbacks = ["globe": "\u{1F310}", "mic": "\u{1F3A4}"]

    // Overrides in `overrides.json` are written as plain strings.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.elements = [.text(try container.decode(String.self))]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(plainText)
    }
}

extension KeyCombination: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(elements: [.text(value)])
    }
}
