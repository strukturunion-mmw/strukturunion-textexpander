import Foundation
import Combine

/// The document holding every group and snippet. Persisted as JSON in
/// ~/Library/Application Support/StrukturExpander/library.json with rolling backups.
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published var groups: [SnippetGroup] = [] {
        didSet { scheduleSave() }
    }

    private var saveWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "SnippetStore.save", qos: .utility)

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("StrukturExpander", isDirectory: true)
    }

    static var libraryURL: URL { directoryURL.appendingPathComponent("library.json") }
    static var backupDirectoryURL: URL { directoryURL.appendingPathComponent("Backups", isDirectory: true) }

    init() {
        load()
        if groups.isEmpty {
            groups = [Self.starterGroup()]
        }
    }

    // MARK: - Lookup

    var allSnippets: [Snippet] {
        groups.flatMap { $0.snippets }
    }

    func group(withID id: UUID) -> SnippetGroup? {
        groups.first { $0.id == id }
    }

    func snippet(withID id: UUID) -> Snippet? {
        for group in groups {
            if let s = group.snippets.first(where: { $0.id == id }) { return s }
        }
        return nil
    }

    func groupContaining(snippetID: UUID) -> SnippetGroup? {
        groups.first { $0.snippets.contains(where: { $0.id == snippetID }) }
    }

    /// First enabled snippet matching an abbreviation exactly (used by %snippet:% macro).
    func snippet(forAbbreviation abbreviation: String) -> Snippet? {
        for group in groups where group.enabled {
            if let s = group.snippets.first(where: { $0.abbreviation == abbreviation && $0.enabled }) {
                return s
            }
        }
        // Fall back to a case-insensitive match.
        let lower = abbreviation.lowercased()
        for group in groups where group.enabled {
            if let s = group.snippets.first(where: { $0.abbreviation.lowercased() == lower && $0.enabled }) {
                return s
            }
        }
        return nil
    }

    // MARK: - Mutation

    func updateSnippet(_ snippet: Snippet) {
        for gi in groups.indices {
            if let si = groups[gi].snippets.firstIndex(where: { $0.id == snippet.id }) {
                var s = snippet
                s.modificationDate = Date()
                groups[gi].snippets[si] = s
                return
            }
        }
    }

    /// Records a use of the snippet without touching its modification date.
    func recordUse(of snippetID: UUID) {
        for gi in groups.indices {
            if let si = groups[gi].snippets.firstIndex(where: { $0.id == snippetID }) {
                groups[gi].snippets[si].useCount += 1
                groups[gi].snippets[si].lastUsed = Date()
                return
            }
        }
    }

    func addSnippet(_ snippet: Snippet, to groupID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gi].snippets.append(snippet)
    }

    func removeSnippet(id: UUID) {
        for gi in groups.indices {
            groups[gi].snippets.removeAll { $0.id == id }
        }
    }

    func moveSnippet(id: UUID, to groupID: UUID) {
        guard let sourceGI = groups.firstIndex(where: { $0.snippets.contains(where: { $0.id == id }) }),
              let targetGI = groups.firstIndex(where: { $0.id == groupID }),
              sourceGI != targetGI,
              let si = groups[sourceGI].snippets.firstIndex(where: { $0.id == id })
        else { return }
        let snippet = groups[sourceGI].snippets.remove(at: si)
        groups[targetGI].snippets.append(snippet)
    }

    func addGroup(_ group: SnippetGroup) {
        groups.append(group)
    }

    func removeGroup(id: UUID) {
        groups.removeAll { $0.id == id }
    }

    // MARK: - Conflict detection

    /// Returns abbreviations that conflict with the given one: exact duplicates,
    /// or an existing abbreviation that is a prefix of it (making it unreachable),
    /// or one it is a prefix of.
    func conflicts(forAbbreviation abbreviation: String, excludingSnippetID: UUID? = nil) -> [Snippet] {
        guard !abbreviation.isEmpty else { return [] }
        var result: [Snippet] = []
        for group in groups {
            for s in group.snippets where s.id != excludingSnippetID && !s.abbreviation.isEmpty {
                if s.abbreviation == abbreviation
                    || s.abbreviation.hasPrefix(abbreviation)
                    || abbreviation.hasPrefix(s.abbreviation) {
                    result.append(s)
                }
            }
        }
        return result
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = groups
        let item = DispatchWorkItem { [weak self] in
            self?.write(groups: snapshot)
        }
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        write(groups: groups)
    }

    private func write(groups: [SnippetGroup]) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(groups)
            try data.write(to: Self.libraryURL, options: .atomic)
        } catch {
            NSLog("StrukturExpander: failed to save library: \(error)")
        }
    }

    private func load() {
        let url = Self.libraryURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            groups = try decoder.decode([SnippetGroup].self, from: data)
        } catch {
            NSLog("StrukturExpander: failed to load library: \(error)")
            // Preserve the unreadable file for manual recovery instead of overwriting it.
            let rescue = Self.directoryURL.appendingPathComponent("library-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: rescue)
        }
    }

    /// Writes a timestamped backup copy of the library and prunes old ones.
    func backup(keeping keepCount: Int = 20) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: Self.backupDirectoryURL, withIntermediateDirectories: true)
            saveNow()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            let name = "library-\(formatter.string(from: Date())).json"
            let dest = Self.backupDirectoryURL.appendingPathComponent(name)
            if fm.fileExists(atPath: Self.libraryURL.path) {
                try fm.copyItem(at: Self.libraryURL, to: dest)
            }
            // Prune oldest backups beyond keepCount.
            let backups = try fm.contentsOfDirectory(at: Self.backupDirectoryURL, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if backups.count > keepCount {
                for url in backups.prefix(backups.count - keepCount) {
                    try? fm.removeItem(at: url)
                }
            }
        } catch {
            NSLog("StrukturExpander: backup failed: \(error)")
        }
    }

    // MARK: - Starter content

    static func starterGroup() -> SnippetGroup {
        var group = SnippetGroup(name: "Sample Snippets")
        group.snippets = [
            Snippet(abbreviation: "ddate", label: "Today's Date", content: "%B %e, %Y"),
            Snippet(abbreviation: "ttime", label: "Current Time", content: "%1H:%M"),
            Snippet(abbreviation: "sig1", label: "Signature",
                    content: "Best regards,\n\n%filltext:name=Your Name%\n"),
            Snippet(abbreviation: "thx", label: "Thanks", content: "Thank you very much!"),
            Snippet(abbreviation: "cclip", label: "Paste Clipboard", content: "%clipboard"),
        ]
        return group
    }
}
