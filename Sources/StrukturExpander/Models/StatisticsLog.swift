import Foundation

/// Lightweight per-day expansion statistics, persisted as JSON alongside the library.
final class StatisticsLog: ObservableObject {
    static let shared = StatisticsLog()

    struct DayStat: Codable, Identifiable {
        var day: String            // yyyy-MM-dd
        var expansions: Int
        var charactersSaved: Int
        var id: String { day }
    }

    @Published private(set) var days: [String: DayStat] = [:]
    /// Per-snippet expansion counts (mirrors Snippet.useCount but survives edits).
    @Published private(set) var perSnippet: [String: Int] = [:]

    private static var url: URL {
        SnippetStore.directoryURL.appendingPathComponent("statistics.json")
    }

    private struct Payload: Codable {
        var days: [String: DayStat]
        var perSnippet: [String: Int]
    }

    init() { load() }

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    func record(snippetID: UUID, charactersSaved: Int) {
        let key = todayKey
        var stat = days[key] ?? DayStat(day: key, expansions: 0, charactersSaved: 0)
        stat.expansions += 1
        stat.charactersSaved += max(0, charactersSaved)
        days[key] = stat
        perSnippet[snippetID.uuidString, default: 0] += 1
        save()
    }

    /// Stats for the last `count` days, oldest first, filling gaps with zeros.
    func recentDays(_ count: Int = 30) -> [DayStat] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var result: [DayStat] = []
        for offset in stride(from: count - 1, through: 0, by: -1) {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = f.string(from: date)
            result.append(days[key] ?? DayStat(day: key, expansions: 0, charactersSaved: 0))
        }
        return result
    }

    var totalExpansions: Int { days.values.reduce(0) { $0 + $1.expansions } }
    var totalCharactersSaved: Int { days.values.reduce(0) { $0 + $1.charactersSaved } }

    /// Estimated time saved, in seconds, given a typing speed in WPM.
    func timeSavedSeconds(wpm: Int) -> Double {
        guard wpm > 0 else { return 0 }
        let words = Double(totalCharactersSaved) / 5.0
        return words / Double(wpm) * 60.0
    }

    private func save() {
        let payload = Payload(days: days, perSnippet: perSnippet)
        DispatchQueue.global(qos: .utility).async {
            do {
                try FileManager.default.createDirectory(at: SnippetStore.directoryURL, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(payload)
                try data.write(to: Self.url, options: .atomic)
            } catch {
                NSLog("StrukturExpander: failed to save statistics: \(error)")
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        days = payload.days
        perSnippet = payload.perSnippet
    }
}
