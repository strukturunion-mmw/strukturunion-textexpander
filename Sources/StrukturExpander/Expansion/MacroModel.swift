import Foundation

/// A parsed element of snippet content, following TextExpander's macro grammar.
enum MacroNode: Equatable {
    case text(String)
    /// A date/time element expressed as a Unicode (DateFormatter) pattern.
    case dateFormat(pattern: String)
    /// %@+3D style rolling date adjustment affecting subsequent date macros.
    case dateMath(value: Int, unit: Character)
    /// %clipboard
    case clipboard
    /// %| — where the insertion point should end up.
    case cursor
    /// %\ — end of the selected range started at %|.
    case selectionEnd
    /// %key:return% etc.
    case key(name: String)
    /// %> %< %^ %v arrow-key macros.
    case arrow(direction: ArrowDirection)
    /// %snippet:abbr% — embedded snippet.
    case nested(abbreviation: String)
    /// A fill-in field reference (field itself described separately).
    case fill(field: FillField)
    /// %fillpart:name=...:default=yes% — start of an optional section.
    case fillPartStart(name: String, defaultOn: Bool)
    /// %fillpartend%
    case fillPartEnd
    /// %filltop% — show this snippet's fields at the top of the fill-in window.
    case fillTop
    /// %+ (keep delimiter) / %- (abandon delimiter) per-snippet override.
    case delimiterOverride(keep: Bool)
    /// %ai:prompt% — StrukturExpander extension: ask the configured LLM at expansion time.
    case aiPrompt(String)
}

enum ArrowDirection: Equatable {
    case up, down, left, right
}

/// One interactive field shown in the fill-in window.
struct FillField: Equatable, Identifiable {
    enum Kind: Equatable {
        case text(width: Int)
        case area(width: Int, height: Int)
        case popup(options: [String], defaultIndex: Int)
        /// Date picker fill-in; format is a Unicode date pattern.
        case date(format: String)
        /// Optional section checkbox (synthesized from fillpart).
        case optionalPart(defaultOn: Bool)
    }

    var name: String
    var defaultValue: String
    var kind: Kind

    var id: String { name }
}

/// The fully evaluated expansion, ready for injection.
struct RenderedExpansion {
    /// Sequential output: text runs interleaved with key presses.
    enum Segment {
        case text(String)
        case keyPress(name: String)
        case arrow(direction: ArrowDirection)
    }

    var segments: [Segment] = []
    /// Rich-text payload (RTFD). When set, `segments` holds the plain mirror
    /// and injection uses the pasteboard.
    var rtfdData: Data? = nil
    /// Number of plain-text characters after the %| marker (cursor repositioning).
    var cursorBackOffset: Int? = nil
    /// Length of the selection between %| and %\ if both were present.
    var selectionLength: Int? = nil
    /// Per-snippet delimiter handling override (%+ / %-).
    var keepDelimiterOverride: Bool? = nil

    var plainText: String {
        segments.map { segment -> String in
            if case .text(let s) = segment { return s }
            return ""
        }.joined()
    }
}
