import Foundation

enum SnippetIOError: LocalizedError {
    case unsupportedFormat
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported file format"
        case .malformed(let detail): return "Malformed file: \(detail)"
        }
    }
}

/// Import/export of snippet groups: native JSON, TextExpander `.textexpander`
/// plist, and CSV.
enum SnippetIO {

    // MARK: Import

    static func importFile(at url: URL) throws -> [SnippetGroup] {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        let baseName = url.deletingPathExtension().lastPathComponent

        switch ext {
        case "json":
            return try importJSON(data: data, name: baseName)
        case "textexpander", "plist", "xml":
            return try importTextExpander(data: data, name: baseName)
        case "csv":
            return [try importCSV(text: String(decoding: data, as: UTF8.self), name: baseName)]
        default:
            // Try JSON, then plist, then CSV.
            if let groups = try? importJSON(data: data, name: baseName) { return groups }
            if let groups = try? importTextExpander(data: data, name: baseName) { return groups }
            return [try importCSV(text: String(decoding: data, as: UTF8.self), name: baseName)]
        }
    }

    private static func importJSON(data: Data, name: String) throws -> [SnippetGroup] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Accept either a full library (array of groups) or a single group.
        if let groups = try? decoder.decode([SnippetGroup].self, from: data) {
            return groups
        }
        if let group = try? decoder.decode(SnippetGroup.self, from: data) {
            return [group]
        }
        throw SnippetIOError.malformed("not a StrukturExpander JSON export")
    }

    /// Parses a TextExpander `.textexpander` / settings plist.
    private static func importTextExpander(data: Data, name: String) throws -> [SnippetGroup] {
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw SnippetIOError.malformed("not a property list")
        }

        // A settings file may contain multiple groups under "groupsTE2"/"groups";
        // a single-group file has "snippetsTE2"/"snippets" at top level.
        if let groupsArray = (plist["groupsTE2"] ?? plist["groups"]) as? [[String: Any]] {
            return groupsArray.map { parseTEGroup($0, fallbackName: name) }
        }
        return [parseTEGroup(plist, fallbackName: name)]
    }

    private static func parseTEGroup(_ dict: [String: Any], fallbackName: String) -> SnippetGroup {
        var group = SnippetGroup(name: (dict["name"] as? String) ?? fallbackName)
        let snippetDicts = (dict["snippetsTE2"] ?? dict["snippets"]) as? [[String: Any]] ?? []
        group.snippets = snippetDicts.map { s in
            var snippet = Snippet()
            snippet.abbreviation = (s["abbreviation"] as? String) ?? ""
            snippet.label = (s["label"] as? String) ?? ""
            snippet.content = (s["plainText"] as? String)
                ?? (s["snippetPlainText"] as? String)
                ?? ""
            snippet.useCount = (s["useCount"] as? Int) ?? 0
            // snippetType: 0 plain, others RTF/script — map best-effort.
            switch (s["snippetType"] as? Int) ?? 0 {
            case 1: snippet.contentType = .richText
            case 2: snippet.contentType = .appleScript
            case 3: snippet.contentType = .shellScript
            case 4: snippet.contentType = .javaScript
            default: snippet.contentType = .plainText
            }
            // abbreviationMode: 0 case-sensitive, 1 insensitive, 2 adapt.
            switch (s["abbreviationMode"] as? Int) ?? 0 {
            case 1: snippet.caseSensitivityOverride = .caseInsensitive
            case 2: snippet.caseSensitivityOverride = .adaptToCase
            default: snippet.caseSensitivityOverride = .caseSensitive
            }
            return snippet
        }
        return group
    }

    /// Parses CSV with header `abbreviation,snippet[,label]`.
    static func importCSV(text: String, name: String) throws -> SnippetGroup {
        let rows = parseCSVRows(text)
        guard !rows.isEmpty else { throw SnippetIOError.malformed("empty CSV") }

        var startIndex = 0
        var abbrCol = 0, contentCol = 1, labelCol = 2
        let header = rows[0].map { $0.lowercased() }
        if header.contains("abbreviation") || header.contains("snippet") {
            abbrCol = header.firstIndex(where: { $0.contains("abbrev") }) ?? 0
            contentCol = header.firstIndex(where: { $0.contains("snippet") || $0.contains("content") || $0.contains("text") }) ?? 1
            labelCol = header.firstIndex(where: { $0.contains("label") || $0.contains("name") }) ?? 2
            startIndex = 1
        }

        var group = SnippetGroup(name: name)
        for row in rows[startIndex...] {
            guard !row.isEmpty, row.contains(where: { !$0.isEmpty }) else { continue }
            var snippet = Snippet()
            snippet.abbreviation = row.indices.contains(abbrCol) ? row[abbrCol] : ""
            snippet.content = row.indices.contains(contentCol) ? row[contentCol] : ""
            snippet.label = row.indices.contains(labelCol) ? row[labelCol] : ""
            group.snippets.append(snippet)
        }
        return group
    }

    /// Minimal RFC-4180 CSV parser (handles quotes, embedded commas, newlines).
    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\""); i += 2; continue
                    }
                    inQuotes = false
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n":
                    row.append(field); field = ""
                    rows.append(row); row = []
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // MARK: Export

    static func exportGroup(_ group: SnippetGroup, to url: URL) throws {
        switch url.pathExtension.lowercased() {
        case "csv":
            try exportCSV(group, to: url)
        case "textexpander", "plist", "xml":
            try exportTextExpander(group, to: url)
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(group).write(to: url)
        }
    }

    private static func exportCSV(_ group: SnippetGroup, to url: URL) throws {
        var lines = ["abbreviation,snippet,label"]
        for s in group.snippets {
            lines.append([s.abbreviation, s.content, s.label].map(csvEscape).joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func exportTextExpander(_ group: SnippetGroup, to url: URL) throws {
        let snippetDicts: [[String: Any]] = group.snippets.map { s in
            var type = 0
            switch s.contentType {
            case .plainText: type = 0
            case .richText: type = 1
            case .appleScript: type = 2
            case .shellScript: type = 3
            case .javaScript: type = 4
            }
            var mode = 0
            switch s.caseSensitivityOverride ?? .caseSensitive {
            case .caseSensitive: mode = 0
            case .caseInsensitive: mode = 1
            case .adaptToCase: mode = 2
            }
            return [
                "abbreviation": s.abbreviation,
                "plainText": s.content,
                "label": s.label,
                "snippetType": type,
                "abbreviationMode": mode,
                "useCount": s.useCount,
                "uuidString": s.id.uuidString,
            ]
        }
        let plist: [String: Any] = [
            "name": group.name,
            "snippetsTE2": snippetDicts,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url)
    }

    // MARK: Printing

    static func printableText(for group: SnippetGroup?, store: SnippetStore) -> String {
        let groups = group.map { [$0] } ?? store.groups
        var out = ""
        for g in groups {
            out += "═══ \(g.name) ═══\n\n"
            for s in g.snippets {
                out += "  \(s.abbreviation.isEmpty ? "(no abbr)" : s.abbreviation)"
                if !s.label.isEmpty { out += "  — \(s.label)" }
                out += "\n"
                let indented = s.content.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "      \($0)" }.joined(separator: "\n")
                out += indented + "\n\n"
            }
        }
        return out
    }
}
