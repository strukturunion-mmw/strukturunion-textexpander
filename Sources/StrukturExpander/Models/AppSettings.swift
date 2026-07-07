import Foundation
import Combine
import AppKit

/// How expanded text is delivered into the target application.
enum InsertionMethod: String, Codable, CaseIterable, Identifiable {
    /// Copy to the pasteboard and simulate Cmd-V (fast, supports rich text/images).
    case pasteboard
    /// Simulate individual key events (slower, works in apps that block pasting).
    case keystrokes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pasteboard: return "Paste (fast, supports formatting and images)"
        case .keystrokes: return "Simulate Keystrokes (for apps that block pasting)"
        }
    }
}

/// When expansion fires relative to the abbreviation being typed.
enum ExpansionMode: String, Codable, CaseIterable, Identifiable {
    /// Expand the instant the last character of the abbreviation is typed.
    case immediate
    /// Wait for a delimiter key; type the delimiter after the expansion.
    case delimiterKeep
    /// Wait for a delimiter key; swallow the delimiter.
    case delimiterAbandon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .immediate: return "Immediately When Typed"
        case .delimiterKeep: return "At Delimiter (Keep Delimiter)"
        case .delimiterAbandon: return "At Delimiter (Abandon Delimiter)"
        }
    }
}

/// Handling of accidental double capitals ("THe" -> "The").
enum DoubleCapitalCorrection: String, Codable, CaseIterable, Identifiable {
    case off
    case sentenceStart
    case wordStart

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Do Not Correct"
        case .sentenceStart: return "Eliminate at Sentence Start"
        case .wordStart: return "Eliminate at Word Start"
        }
    }
}

/// Global, UserDefaults-backed preferences.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: Expansion behaviour

    @Published var expansionEnabled: Bool {
        didSet { defaults.set(expansionEnabled, forKey: "expansionEnabled") }
    }
    @Published var expansionMode: ExpansionMode {
        didSet { defaults.set(expansionMode.rawValue, forKey: "expansionMode") }
    }
    /// Delimiter characters used by the delimiter expansion modes.
    /// Return, Tab and Esc are handled as keys; this holds printable delimiters.
    @Published var delimiters: String {
        didSet { defaults.set(delimiters, forKey: "delimiters") }
    }
    /// Global default; groups/snippets may override.
    @Published var defaultCaseSensitivity: CaseSensitivity {
        didSet { defaults.set(defaultCaseSensitivity.rawValue, forKey: "defaultCaseSensitivity") }
    }
    /// Global default; groups may override.
    @Published var defaultTriggerContext: TriggerContext {
        didSet { defaults.set(defaultTriggerContext.rawValue, forKey: "defaultTriggerContext") }
    }
    @Published var insertionMethod: InsertionMethod {
        didSet { defaults.set(insertionMethod.rawValue, forKey: "insertionMethod") }
    }
    @Published var playSoundOnExpansion: Bool {
        didSet { defaults.set(playSoundOnExpansion, forKey: "playSoundOnExpansion") }
    }
    @Published var expansionSoundName: String {
        didSet { defaults.set(expansionSoundName, forKey: "expansionSoundName") }
    }
    /// Restore the previous clipboard contents after a pasteboard expansion.
    @Published var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: "restoreClipboard") }
    }
    /// Backspace over the abbreviation deletes the whole expansion (undo-like helper):
    /// pressing Delete immediately after an expansion restores the typed abbreviation.
    @Published var restoreAbbreviationOnDelete: Bool {
        didSet { defaults.set(restoreAbbreviationOnDelete, forKey: "restoreAbbreviationOnDelete") }
    }
    /// Bundle identifiers in which expansion is globally disabled.
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: "excludedBundleIDs") }
    }
    /// Allow AppleScript / shell / JavaScript snippets to run on expansion.
    @Published var runScriptSnippets: Bool {
        didSet { defaults.set(runScriptSnippets, forKey: "runScriptSnippets") }
    }

    // MARK: Options (typo correction)

    /// Auto-capitalize the first letter of new sentences.
    @Published var capitalizeNewSentences: Bool {
        didSet { defaults.set(capitalizeNewSentences, forKey: "capitalizeNewSentences") }
    }
    @Published var doubleCapitalCorrection: DoubleCapitalCorrection {
        didSet { defaults.set(doubleCapitalCorrection.rawValue, forKey: "doubleCapitalCorrection") }
    }
    /// Bundle IDs excluded from the capitalization corrections above.
    @Published var correctionExcludedBundleIDs: [String] {
        didSet { defaults.set(correctionExcludedBundleIDs, forKey: "correctionExcludedBundleIDs") }
    }

    // MARK: Suggestions

    /// Locally detect frequently typed phrases and suggest snippets for them.
    @Published var suggestionsEnabled: Bool {
        didSet { defaults.set(suggestionsEnabled, forKey: "suggestionsEnabled") }
    }
    @Published var notifyOnSuggestion: Bool {
        didSet { defaults.set(notifyOnSuggestion, forKey: "notifyOnSuggestion") }
    }
    /// Remind me when I type out the full content of an existing snippet.
    @Published var notifyOnMissedExpansion: Bool {
        didSet { defaults.set(notifyOnMissedExpansion, forKey: "notifyOnMissedExpansion") }
    }

    // MARK: App behaviour

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: "showDockIcon") }
    }

    // MARK: Hotkeys (stored as keyCode + modifier flags; 0 keyCode+mods = disabled)

    @Published var searchHotkey: HotkeySpec {
        didSet { HotkeySpec.store(searchHotkey, key: "searchHotkey", in: defaults) }
    }
    @Published var createFromSelectionHotkey: HotkeySpec {
        didSet { HotkeySpec.store(createFromSelectionHotkey, key: "createFromSelectionHotkey", in: defaults) }
    }
    @Published var createFromClipboardHotkey: HotkeySpec {
        didSet { HotkeySpec.store(createFromClipboardHotkey, key: "createFromClipboardHotkey", in: defaults) }
    }
    @Published var toggleExpansionHotkey: HotkeySpec {
        didSet { HotkeySpec.store(toggleExpansionHotkey, key: "toggleExpansionHotkey", in: defaults) }
    }

    // MARK: AI (OpenRouter)

    @Published var openRouterAPIKey: String {
        didSet { defaults.set(openRouterAPIKey, forKey: "openRouterAPIKey") }
    }
    @Published var openRouterModel: String {
        didSet { defaults.set(openRouterModel, forKey: "openRouterModel") }
    }
    @Published var aiSuggestionsEnabled: Bool {
        didSet { defaults.set(aiSuggestionsEnabled, forKey: "aiSuggestionsEnabled") }
    }

    // MARK: Statistics

    @Published var totalExpansions: Int {
        didSet { defaults.set(totalExpansions, forKey: "totalExpansions") }
    }
    @Published var totalCharactersSaved: Int {
        didSet { defaults.set(totalCharactersSaved, forKey: "totalCharactersSaved") }
    }
    /// Assumed typing speed (words per minute) used for the "time saved" statistic.
    @Published var typingSpeedWPM: Int {
        didSet { defaults.set(typingSpeedWPM, forKey: "typingSpeedWPM") }
    }

    private init() {
        expansionEnabled = defaults.object(forKey: "expansionEnabled") as? Bool ?? true
        expansionMode = ExpansionMode(rawValue: defaults.string(forKey: "expansionMode") ?? "") ?? .immediate
        delimiters = defaults.string(forKey: "delimiters") ?? " .,;:!?/()[]{}<>\"'\n\t"
        defaultCaseSensitivity = CaseSensitivity(rawValue: defaults.string(forKey: "defaultCaseSensitivity") ?? "") ?? .caseSensitive
        defaultTriggerContext = TriggerContext(rawValue: defaults.string(forKey: "defaultTriggerContext") ?? "") ?? .whitespace
        runScriptSnippets = defaults.object(forKey: "runScriptSnippets") as? Bool ?? true
        capitalizeNewSentences = defaults.object(forKey: "capitalizeNewSentences") as? Bool ?? false
        doubleCapitalCorrection = DoubleCapitalCorrection(rawValue: defaults.string(forKey: "doubleCapitalCorrection") ?? "") ?? .off
        correctionExcludedBundleIDs = defaults.stringArray(forKey: "correctionExcludedBundleIDs") ?? []
        suggestionsEnabled = defaults.object(forKey: "suggestionsEnabled") as? Bool ?? false
        notifyOnSuggestion = defaults.object(forKey: "notifyOnSuggestion") as? Bool ?? true
        notifyOnMissedExpansion = defaults.object(forKey: "notifyOnMissedExpansion") as? Bool ?? false
        insertionMethod = InsertionMethod(rawValue: defaults.string(forKey: "insertionMethod") ?? "") ?? .pasteboard
        playSoundOnExpansion = defaults.object(forKey: "playSoundOnExpansion") as? Bool ?? true
        expansionSoundName = defaults.string(forKey: "expansionSoundName") ?? "Pop"
        restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        restoreAbbreviationOnDelete = defaults.object(forKey: "restoreAbbreviationOnDelete") as? Bool ?? true
        excludedBundleIDs = defaults.stringArray(forKey: "excludedBundleIDs") ?? []
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? false
        searchHotkey = HotkeySpec.load(key: "searchHotkey", in: defaults)
            ?? HotkeySpec(keyCode: 44, modifiers: [.command]) // Cmd-/ (TextExpander's inline search default)
        createFromSelectionHotkey = HotkeySpec.load(key: "createFromSelectionHotkey", in: defaults)
            ?? HotkeySpec(keyCode: 8, modifiers: [.command, .shift, .option]) // Cmd-Opt-Shift-C
        createFromClipboardHotkey = HotkeySpec.load(key: "createFromClipboardHotkey", in: defaults)
            ?? HotkeySpec.disabled
        toggleExpansionHotkey = HotkeySpec.load(key: "toggleExpansionHotkey", in: defaults)
            ?? HotkeySpec.disabled
        openRouterAPIKey = defaults.string(forKey: "openRouterAPIKey") ?? ""
        openRouterModel = defaults.string(forKey: "openRouterModel") ?? "anthropic/claude-sonnet-4.5"
        aiSuggestionsEnabled = defaults.object(forKey: "aiSuggestionsEnabled") as? Bool ?? false
        totalExpansions = defaults.integer(forKey: "totalExpansions")
        totalCharactersSaved = defaults.integer(forKey: "totalCharactersSaved")
        typingSpeedWPM = defaults.object(forKey: "typingSpeedWPM") as? Int ?? 50
    }
}

/// A global hotkey: virtual key code plus modifier flags. Codable via UserDefaults dictionary.
struct HotkeySpec: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    static let disabled = HotkeySpec(keyCode: 0, modifiers: [])

    var isEnabled: Bool { !(keyCode == 0 && modifiers.isEmpty) }

    static func store(_ spec: HotkeySpec, key: String, in defaults: UserDefaults) {
        defaults.set(["keyCode": Int(spec.keyCode), "modifiers": Int(spec.modifiers.rawValue)], forKey: key)
    }

    static func load(key: String, in defaults: UserDefaults) -> HotkeySpec? {
        guard let dict = defaults.dictionary(forKey: key),
              let keyCode = dict["keyCode"] as? Int,
              let modifiers = dict["modifiers"] as? Int else { return nil }
        return HotkeySpec(keyCode: UInt32(keyCode), modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
    }

    /// Human-readable description like "⌘⇧Space".
    var displayString: String {
        guard isEnabled else { return "None" }
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode)
        return s
    }
}

enum KeyCodeNames {
    static func name(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
            27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
            36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
            53: "Esc", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}
