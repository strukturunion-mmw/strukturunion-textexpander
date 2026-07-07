import Foundation
import AppKit
import Carbon.HIToolbox

/// Implements the "Options" auto-corrections: capitalize the first letter of a
/// new sentence, and eliminate accidental double capitals ("THe" -> "The").
///
/// Corrections rewrite characters that were just typed, so they run only when
/// the frontmost app is not excluded and expansion is not in progress.
@MainActor
final class CorrectionEngine {
    private let settings = AppSettings.shared

    /// Recently typed characters, mirrored from the monitor's buffer.
    /// The monitor calls `consider` after each printable character.
    func consider(recentText: String, justTyped: Character, bundleID: String?) {
        guard settings.capitalizeNewSentences || settings.doubleCapitalCorrection != .off else { return }
        if let bundleID, settings.correctionExcludedBundleIDs.contains(bundleID) { return }
        guard !ExpansionEngine.shared.isExpanding else { return }

        if considerDoubleCapital(recentText: recentText, justTyped: justTyped) { return }
        considerSentenceCapitalization(recentText: recentText, justTyped: justTyped)
    }

    /// "THe" -> "The": when a lowercase letter follows two uppercase letters
    /// that begin a word, lowercase the second uppercase letter.
    private func considerDoubleCapital(recentText: String, justTyped: Character) -> Bool {
        guard settings.doubleCapitalCorrection != .off else { return false }
        guard justTyped.isLowercase, justTyped.isLetter else { return false }

        let chars = Array(recentText)
        // recentText ends with justTyped. We need: [boundary?] U U l
        guard chars.count >= 3 else { return false }
        let l = chars[chars.count - 1]     // justTyped (lowercase)
        let u2 = chars[chars.count - 2]    // should be uppercase
        let u1 = chars[chars.count - 3]    // should be uppercase
        guard l.isLowercase, u2.isUppercase, u1.isUppercase else { return false }

        // Character before u1 must be a word boundary.
        let before: Character? = chars.count >= 4 ? chars[chars.count - 4] : nil
        let atWordStart = before == nil || !(before!.isLetter || before!.isNumber)

        switch settings.doubleCapitalCorrection {
        case .off:
            return false
        case .sentenceStart:
            // Only correct if this is also a sentence start.
            guard atWordStart, isSentenceStart(chars: chars, wordStartIndex: chars.count - 3) else { return false }
        case .wordStart:
            guard atWordStart else { return false }
        }

        // Rewrite u2 (the second capital): delete l and u2, retype lowercase u2 + l.
        let replacement = String(u2).lowercased() + String(l)
        rewriteTail(deleteCount: 2, insert: replacement)
        return true
    }

    /// Capitalizes the first letter typed at the start of a new sentence.
    private func considerSentenceCapitalization(recentText: String, justTyped: Character) {
        guard settings.capitalizeNewSentences else { return }
        guard justTyped.isLowercase, justTyped.isLetter else { return }

        let chars = Array(recentText)
        guard isSentenceStart(chars: chars, wordStartIndex: chars.count - 1) else { return }

        rewriteTail(deleteCount: 1, insert: String(justTyped).uppercased())
    }

    /// True if the letter at `wordStartIndex` begins a new sentence: preceded by
    /// start-of-text, or by a sentence terminator (. ! ?) and whitespace.
    private func isSentenceStart(chars: [Character], wordStartIndex: Int) -> Bool {
        guard wordStartIndex >= 0, wordStartIndex < chars.count else { return false }
        var i = wordStartIndex - 1
        // Skip immediate spaces before the letter.
        var sawSpace = false
        while i >= 0, chars[i] == " " {
            sawSpace = true
            i -= 1
        }
        if i < 0 { return wordStartIndex == 0 || sawSpace } // start of buffer
        if wordStartIndex == 0 { return true }
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        if terminators.contains(chars[i]), sawSpace || chars[i] == "\n" {
            return true
        }
        return false
    }

    /// Deletes `deleteCount` characters and types `insert` in their place.
    private func rewriteTail(deleteCount: Int, insert: String) {
        Task { @MainActor in
            TextInjector.deleteBackward(count: deleteCount)
            try? await Task.sleep(nanoseconds: 15_000_000)
            TextInjector.typeString(insert)
        }
    }
}
