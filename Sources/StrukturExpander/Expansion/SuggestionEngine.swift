import Foundation
import AppKit
import UserNotifications

/// Locally detects frequently retyped phrases and suggests turning them into
/// snippets. Runs entirely on-device; nothing leaves the machine.
@MainActor
final class SuggestionEngine {
    private let settings = AppSettings.shared

    /// Frequency of recently completed words/short phrases.
    private var counts: [String: Int] = [:]
    /// Phrases already suggested so we don't nag repeatedly.
    private var suggested: Set<String> = []
    private let threshold = 6
    private let minLength = 12

    /// Called at each word/sentence boundary with the current buffer text.
    func recordBoundary(text: String) {
        // Take the last "phrase": the trailing run up to ~48 chars, trimmed.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength else { return }
        let phrase = String(trimmed.suffix(48))
        // Only consider multi-word phrases (something worth a snippet).
        guard phrase.contains(" ") else { return }

        counts[phrase, default: 0] += 1
        if counts[phrase]! >= threshold, !suggested.contains(phrase) {
            suggested.insert(phrase)
            notifySuggestion(phrase: phrase)
        }
    }

    private func notifySuggestion(phrase: String) {
        guard settings.notifyOnSuggestion else { return }
        let content = UNMutableNotificationContent()
        content.title = "Snippet Suggestion"
        content.body = "You've typed “\(String(phrase.prefix(40)))…” several times. Create a snippet?"
        content.sound = nil
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        // Also stash it so the main window can offer one-click creation.
        SuggestionInbox.shared.add(phrase: phrase)
    }
}

/// Holds pending suggestions for the UI to surface.
@MainActor
final class SuggestionInbox: ObservableObject {
    static let shared = SuggestionInbox()
    @Published private(set) var pending: [String] = []

    func add(phrase: String) {
        guard !pending.contains(phrase) else { return }
        pending.append(phrase)
    }

    func remove(_ phrase: String) {
        pending.removeAll { $0 == phrase }
    }
}
