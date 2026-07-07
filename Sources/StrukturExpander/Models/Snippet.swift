import Foundation

/// The kind of content a snippet holds. Mirrors TextExpander's snippet types.
enum SnippetContentType: String, Codable, CaseIterable, Identifiable {
    case plainText
    case richText
    case appleScript
    case shellScript
    case javaScript

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plainText: return "Plain Text"
        case .richText: return "Formatted Text, Pictures"
        case .appleScript: return "AppleScript"
        case .shellScript: return "Shell Script"
        case .javaScript: return "JavaScript"
        }
    }

    var isScript: Bool {
        switch self {
        case .appleScript, .shellScript, .javaScript: return true
        default: return false
        }
    }
}

/// Per-snippet (and per-group) case handling for the abbreviation trigger.
enum CaseSensitivity: String, Codable, CaseIterable, Identifiable {
    /// Abbreviation must be typed exactly as defined.
    case caseSensitive
    /// Any capitalization triggers; expansion is inserted as defined.
    case caseInsensitive
    /// Any capitalization triggers; expansion adapts to the typed capitalization
    /// (e.g. "Sig" -> capitalize first word, "SIG" -> ALL CAPS).
    case adaptToCase

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .caseSensitive: return "Case Sensitive"
        case .caseInsensitive: return "Ignore Case"
        case .adaptToCase: return "Adapt to Case of Abbreviation"
        }
    }
}

struct Snippet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var abbreviation: String = ""
    /// Human readable label. If empty, UI falls back to a content preview.
    var label: String = ""
    /// Plain-text content, script source, or the plain-text mirror of rich text.
    var content: String = ""
    /// RTFD data when contentType == .richText (preserves formatting and images).
    var rtfData: Data? = nil
    var contentType: SnippetContentType = .plainText
    /// nil means "inherit from group".
    var caseSensitivityOverride: CaseSensitivity? = nil
    var enabled: Bool = true
    var creationDate: Date = Date()
    var modificationDate: Date = Date()
    /// Number of times this snippet has been expanded (for statistics).
    var useCount: Int = 0
    var lastUsed: Date? = nil

    var displayLabel: String {
        if !label.isEmpty { return label }
        let preview = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if preview.isEmpty { return abbreviation.isEmpty ? "New Snippet" : abbreviation }
        return String(preview.prefix(60))
    }
}
