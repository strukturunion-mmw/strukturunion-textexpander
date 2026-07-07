import Foundation
import AppKit
import Carbon.HIToolbox

/// Watches system-wide keystrokes via a CGEvent tap, maintains a rolling
/// typing buffer, and triggers expansions when an abbreviation matches.
///
/// Requires Accessibility permission. Ignores its own synthetic events and
/// suspends while an expansion is being delivered or Secure Input is active.
@MainActor
final class KeystrokeMonitor: ObservableObject {
    static let shared = KeystrokeMonitor()

    @Published private(set) var isRunning = false
    @Published private(set) var secureInputActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let store = SnippetStore.shared
    private let settings = AppSettings.shared

    /// Rolling buffer of recently typed characters in the focused app.
    private var buffer = TypingBuffer()
    private let correctionEngine = CorrectionEngine()
    private let suggestionEngine = SuggestionEngine()

    /// Callback invoked when the search hotkey is pressed.
    var onSearchHotkey: (() -> Void)?
    var onCreateFromClipboardHotkey: (() -> Void)?
    var onCreateFromSelectionHotkey: (() -> Void)?

    // MARK: Lifecycle

    func start() {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            NSLog("StrukturExpander: accessibility not granted; monitor not started")
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("StrukturExpander: failed to create event tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true

        // Reset the buffer whenever the frontmost app changes.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate() {
        buffer.reset()
    }

    // MARK: Event handling

    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable the tap if the system disabled it (timeout / user input).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = MainActor.assumeIsolated({ self.eventTap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Ignore our own synthetic events.
        if event.getIntegerValueField(.eventSourceUserData) == TextInjector.syntheticEventMagic {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let modifiers = Self.modifierFlags(from: flags)

        // Handle global hotkeys on the main actor synchronously via dispatch.
        let handled = MainActor.assumeIsolated {
            self.processKeyDown(keyCode: keyCode, modifiers: modifiers, event: event)
        }
        if handled {
            return nil // swallow the event
        }
        return Unmanaged.passUnretained(event)
    }

    /// Returns true if the event should be swallowed.
    private func processKeyDown(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, event: CGEvent) -> Bool {
        // Global hotkeys first.
        if matches(settings.searchHotkey, keyCode: keyCode, modifiers: modifiers) {
            onSearchHotkey?()
            return true
        }
        if matches(settings.createFromClipboardHotkey, keyCode: keyCode, modifiers: modifiers) {
            onCreateFromClipboardHotkey?()
            return true
        }
        if matches(settings.createFromSelectionHotkey, keyCode: keyCode, modifiers: modifiers) {
            onCreateFromSelectionHotkey?()
            return true
        }
        if matches(settings.toggleExpansionHotkey, keyCode: keyCode, modifiers: modifiers) {
            settings.expansionEnabled.toggle()
            return true
        }

        // "Delete restores abbreviation" — Backspace right after an expansion.
        if keyCode == UInt32(kVK_Delete),
           settings.restoreAbbreviationOnDelete,
           handleUndoDelete() {
            return true
        }

        guard settings.expansionEnabled, !ExpansionEngine.shared.isExpanding else {
            return false
        }

        // Detect Secure Input (password fields) — expansion is impossible then.
        secureInputActive = IsSecureEventInputEnabled()
        if secureInputActive { return false }

        // Skip when a command/control modifier is held (shortcuts, not typing).
        if modifiers.contains(.command) || modifiers.contains(.control) {
            buffer.reset()
            return false
        }

        // Translate the key event to characters.
        guard let typed = Self.characters(from: event), !typed.isEmpty else {
            // Navigation / editing keys reset the buffer.
            if [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
                kVK_Home, kVK_End, kVK_Return, kVK_Escape].map({ UInt32($0) }).contains(keyCode) {
                buffer.reset()
            } else if keyCode == UInt32(kVK_Delete) {
                buffer.deleteLast()
            }
            return false
        }

        for character in typed {
            handleTypedCharacter(character)
        }
        return false
    }

    /// Feeds one typed character to the buffer and checks for a match.
    private func handleTypedCharacter(_ character: Character) {
        if character == "\u{8}" || character == "\u{7f}" {
            buffer.deleteLast()
            return
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let bundleID, settings.excludedBundleIDs.contains(bundleID) {
            buffer.append(character)
            return
        }

        // In immediate mode we test after each char; in delimiter mode we test
        // when a delimiter is typed.
        let isDelimiter = isDelimiterCharacter(character)

        if settings.expansionMode == .immediate {
            buffer.append(character)
            if tryMatch(delimiter: nil, bundleID: bundleID) { return }
            applyCorrectionsAndSuggestions(justTyped: character, isDelimiter: isDelimiter, bundleID: bundleID)
        } else {
            if isDelimiter {
                // Try to match the buffer as-is, consuming this delimiter.
                if tryMatch(delimiter: character, bundleID: bundleID) {
                    return
                }
                buffer.append(character)
                applyCorrectionsAndSuggestions(justTyped: character, isDelimiter: true, bundleID: bundleID)
            } else {
                buffer.append(character)
                applyCorrectionsAndSuggestions(justTyped: character, isDelimiter: false, bundleID: bundleID)
            }
        }
    }

    private func applyCorrectionsAndSuggestions(justTyped: Character, isDelimiter: Bool, bundleID: String?) {
        correctionEngine.consider(recentText: buffer.text, justTyped: justTyped, bundleID: bundleID)
        if settings.suggestionsEnabled, isDelimiter {
            suggestionEngine.recordBoundary(text: buffer.text)
        }
    }

    /// Attempts to match the current buffer tail against an abbreviation.
    /// Returns true if an expansion was fired.
    @discardableResult
    private func tryMatch(delimiter: Character?, bundleID: String?) -> Bool {
        let text = buffer.text
        guard !text.isEmpty else { return false }

        var best: ExpansionMatch?
        var bestLength = 0

        for group in store.groups where group.enabled && group.appliesTo(bundleID: bundleID) {
            let triggerContext = group.triggerContext ?? settings.defaultTriggerContext
            for snippet in group.snippets where snippet.enabled && !snippet.abbreviation.isEmpty {
                let abbr = group.effectiveAbbreviation(for: snippet)
                guard !abbr.isEmpty, text.count >= abbr.count else { continue }

                let tail = String(text.suffix(abbr.count))
                let caseMode = snippet.caseSensitivityOverride ?? group.caseSensitivity ?? settings.defaultCaseSensitivity
                let isMatch: Bool
                switch caseMode {
                case .caseSensitive:
                    isMatch = tail == abbr
                case .caseInsensitive, .adaptToCase:
                    isMatch = tail.lowercased() == abbr.lowercased()
                }
                guard isMatch else { continue }

                // Check the character preceding the abbreviation for the trigger context.
                let precedingIndex = text.count - abbr.count
                let preceding: Character? = precedingIndex > 0
                    ? text[text.index(text.startIndex, offsetBy: precedingIndex - 1)]
                    : nil
                guard triggerContext.allows(precedingCharacter: preceding) else { continue }

                // Prefer the longest matching abbreviation.
                if abbr.count > bestLength {
                    bestLength = abbr.count
                    best = ExpansionMatch(
                        snippet: snippet,
                        group: group,
                        typedAbbreviation: tail,
                        typedDelimiter: delimiter
                    )
                }
            }
        }

        guard let match = best else { return false }
        buffer.reset()
        ExpansionEngine.shared.expand(match: match)
        return true
    }

    /// If the last action was an expansion and the user hit Backspace, undo it.
    private func handleUndoDelete() -> Bool {
        guard let last = ExpansionEngine.shared.lastExpansion,
              Date().timeIntervalSince(last.date) < 3.0,
              !last.match.typedAbbreviation.isEmpty,
              last.match.snippet.contentType == .plainText else {
            return false
        }
        // Consume this so it only fires once.
        ExpansionEngine.shared.clearLastExpansion()
        Task { @MainActor in
            TextInjector.deleteBackward(count: last.insertedPlainLength)
            try? await Task.sleep(nanoseconds: 30_000_000)
            TextInjector.typeString(last.match.typedAbbreviation)
        }
        return true
    }

    // MARK: Helpers

    private func isDelimiterCharacter(_ character: Character) -> Bool {
        if character == "\n" || character == "\t" { return true }
        return settings.delimiters.contains(character)
    }

    private func matches(_ hotkey: HotkeySpec, keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard hotkey.isEnabled else { return false }
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        return hotkey.keyCode == keyCode && hotkey.modifiers.intersection(relevant) == modifiers.intersection(relevant)
    }

    private nonisolated static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        return result
    }

    /// Converts a key-down event to the characters it produces.
    private nonisolated static func characters(from event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length)
        // Filter out control characters except tab/newline handled elsewhere.
        if let scalar = string.unicodeScalars.first, scalar.value < 0x20,
           scalar != "\t", scalar != "\n" {
            return nil
        }
        return string
    }
}

/// A bounded rolling buffer of the most recently typed characters.
struct TypingBuffer {
    private var characters: [Character] = []
    private let maxLength = 128

    var text: String { String(characters) }

    mutating func append(_ character: Character) {
        characters.append(character)
        if characters.count > maxLength {
            characters.removeFirst(characters.count - maxLength)
        }
    }

    mutating func deleteLast() {
        if !characters.isEmpty { characters.removeLast() }
    }

    mutating func reset() {
        characters.removeAll(keepingCapacity: true)
    }
}
