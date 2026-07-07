import Foundation

/// How the group decides in which applications its snippets expand.
enum AppPolicyMode: String, Codable, CaseIterable, Identifiable {
    case allApps
    case onlyIn
    case exceptIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allApps: return "Expand in All Applications"
        case .onlyIn: return "Expand Only in Selected Applications"
        case .exceptIn: return "Expand Except in Selected Applications"
        }
    }
}

/// What must precede an abbreviation for it to trigger ("Expand When").
enum TriggerContext: String, Codable, CaseIterable, Identifiable {
    /// Only after whitespace or at the start of input (default; safest).
    case whitespace
    /// After whitespace or punctuation — anything except letters and digits.
    case allButLettersAndNumbers
    /// Anywhere, even in the middle of a word.
    case anyCharacter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whitespace: return "Whitespace Precedes Abbreviation"
        case .allButLettersAndNumbers: return "All but Letters and Numbers Precedes Abbreviation"
        case .anyCharacter: return "Any Character Precedes Abbreviation"
        }
    }

    /// Whether a preceding character allows expansion under this context.
    /// `nil` means "start of the typing buffer", which always allows expansion.
    func allows(precedingCharacter: Character?) -> Bool {
        guard let ch = precedingCharacter else { return true }
        switch self {
        case .whitespace:
            return ch.isWhitespace || ch.isNewline
        case .allButLettersAndNumbers:
            return !(ch.isLetter || ch.isNumber)
        case .anyCharacter:
            return true
        }
    }
}

struct SnippetGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Group"
    var snippets: [Snippet] = []
    var enabled: Bool = true
    /// nil means "inherit the global default from Settings".
    var caseSensitivity: CaseSensitivity? = nil
    /// nil means "inherit the global default from Settings".
    var triggerContext: TriggerContext? = nil
    /// Prefix implicitly prepended to every abbreviation in this group
    /// (e.g. ";" so that snippet "sig" triggers on ";sig").
    var prefix: String = ""
    /// Optional free-form notes shown in Group Settings.
    var notes: String = ""
    var appPolicyMode: AppPolicyMode = .allApps
    /// Bundle identifiers for the onlyIn / exceptIn policies.
    var appPolicyBundleIDs: [String] = []
    var creationDate: Date = Date()

    /// The abbreviation actually typed to trigger a snippet in this group.
    func effectiveAbbreviation(for snippet: Snippet) -> String {
        prefix + snippet.abbreviation
    }

    func appliesTo(bundleID: String?) -> Bool {
        guard enabled else { return false }
        switch appPolicyMode {
        case .allApps:
            return true
        case .onlyIn:
            guard let bundleID else { return false }
            return appPolicyBundleIDs.contains(bundleID)
        case .exceptIn:
            guard let bundleID else { return true }
            return !appPolicyBundleIDs.contains(bundleID)
        }
    }
}
