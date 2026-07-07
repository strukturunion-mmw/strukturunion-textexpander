import Foundation

/// Parses snippet content into MacroNodes following TextExpander's `%…%` grammar.
///
/// Supported syntax:
///   %Y %y %B %b %m %1m %A %a %d %e %H %1H %I %1I %M %1M %S %1S %p   date/time codes
///   %date:<unicode pattern>%                                        custom date format
///   %@+3D / %@-2M                                                   date math (Y M D h m s)
///   %clipboard                                                      clipboard contents
///   %|  %\                                                          cursor / selection end
///   %key:return% %key:tab% %key:enter% %key:escape% %key:delete%    key presses
///   %> %< %^ %v                                                     arrow keys
///   %snippet:abbr%                                                  embedded snippet
///   %filltext:name=X:default=Y:width=20%                            single-line field
///   %fillarea:name=X:default=Y:width=30:height=5%                   multi-line field
///   %fillpopup:name=X:opt1:default=opt2:opt3%                       popup menu
///   %fillpart:name=X:default=yes% … %fillpartend%                   optional section
///   %filldate:name=X:format=<pattern>%                              date-picker field
///   %filltop%                                                       fields shown on top
///   %+ / %-                                                         delimiter override
///   %%                                                              literal percent
///   %ai:prompt text%                                                LLM completion (extension)
enum MacroParser {

    /// Maps TextExpander's strftime-like codes to DateFormatter patterns.
    static let dateCodeMap: [String: String] = [
        "Y": "yyyy", "y": "yy",
        "B": "MMMM", "b": "MMM",
        "m": "MM", "1m": "M",
        "A": "EEEE", "a": "EEE",
        "d": "dd", "e": "d", "1d": "d",
        "H": "HH", "1H": "H",
        "I": "hh", "1I": "h",
        "M": "mm", "1M": "m",
        "S": "ss", "1S": "s",
        "p": "a",
    ]

    static func parse(_ content: String) -> [MacroNode] {
        parseWithLengths(content).map { $0.node }
    }

    /// Like parse, but each node carries the number of source characters it
    /// consumed — needed to map macros back into an attributed string.
    static func parseWithLengths(_ content: String) -> [(node: MacroNode, sourceLength: Int)] {
        var nodes: [(node: MacroNode, sourceLength: Int)] = []
        var textBuffer = ""
        var textSourceLength = 0
        let chars = Array(content)
        var i = 0

        func flushText() {
            if !textBuffer.isEmpty {
                nodes.append((.text(textBuffer), textSourceLength))
                textBuffer = ""
            }
            textSourceLength = 0
        }

        /// Content between the current position and the next unescaped '%'.
        func scanBody(from start: Int) -> (body: String, next: Int)? {
            var j = start
            var body = ""
            while j < chars.count {
                if chars[j] == "%" {
                    return (body, j + 1)
                }
                body.append(chars[j])
                j += 1
            }
            return nil
        }

        while i < chars.count {
            guard chars[i] == "%" else {
                textBuffer.append(chars[i])
                textSourceLength += 1
                i += 1
                continue
            }

            // Trailing bare '%'
            guard i + 1 < chars.count else {
                textBuffer.append("%")
                textSourceLength += 1
                i += 1
                continue
            }

            let next = chars[i + 1]
            var consumed = false

            switch next {
            case "%":
                textBuffer.append("%")
                textSourceLength += 2
                i += 2
                consumed = true
            case "|":
                flushText()
                nodes.append((.cursor, 2))
                i += 2
                consumed = true
            case "\\":
                flushText()
                nodes.append((.selectionEnd, 2))
                i += 2
                consumed = true
            case ">":
                flushText()
                nodes.append((.arrow(direction: .right), 2))
                i += 2
                consumed = true
            case "<":
                flushText()
                nodes.append((.arrow(direction: .left), 2))
                i += 2
                consumed = true
            case "^":
                flushText()
                nodes.append((.arrow(direction: .up), 2))
                i += 2
                consumed = true
            case "v":
                flushText()
                nodes.append((.arrow(direction: .down), 2))
                i += 2
                consumed = true
            case "+":
                flushText()
                nodes.append((.delimiterOverride(keep: true), 2))
                i += 2
                consumed = true
            case "-":
                flushText()
                nodes.append((.delimiterOverride(keep: false), 2))
                i += 2
                consumed = true
            case "@":
                // Date math: %@+15D or %@-2M (no trailing %)
                var j = i + 2
                guard j < chars.count, chars[j] == "+" || chars[j] == "-" else { break }
                let sign = chars[j] == "-" ? -1 : 1
                j += 1
                var digits = ""
                while j < chars.count, chars[j].isNumber {
                    digits.append(chars[j])
                    j += 1
                }
                guard !digits.isEmpty, j < chars.count, "YMDhms".contains(chars[j]),
                      let value = Int(digits) else { break }
                flushText()
                nodes.append((.dateMath(value: sign * value, unit: chars[j]), j + 1 - i))
                i = j + 1
                consumed = true
            default:
                break
            }

            if consumed { continue }

            let rest = String(chars[(i + 1)...])

            // %clipboard — no trailing %
            if rest.hasPrefix("clipboard") {
                flushText()
                nodes.append((.clipboard, 1 + "clipboard".count))
                i += 1 + "clipboard".count
                continue
            }

            // Keyword macros with a closing %.
            var matchedKeyword = false
            for keyword in ["key:", "snippet:", "Snippet:", "date:", "ai:",
                            "filltext", "fillarea", "fillpopup", "fillpartend",
                            "fillpart", "filltop", "filldate"] {
                guard rest.hasPrefix(keyword) else { continue }
                guard let (fullBody, after) = scanBody(from: i + 1) else { break }
                flushText()
                appendKeywordNode(keyword: keyword, body: fullBody, sourceLength: after - i, to: &nodes)
                i = after
                matchedKeyword = true
                break
            }
            if matchedKeyword { continue }

            // Single-character (or %1x) date codes.
            var codeLength = 0
            var code = ""
            if next == "1", i + 2 < chars.count, dateCodeMap["1" + String(chars[i + 2])] != nil {
                code = "1" + String(chars[i + 2])
                codeLength = 3
            } else if dateCodeMap[String(next)] != nil {
                code = String(next)
                codeLength = 2
            }
            if !code.isEmpty, let pattern = dateCodeMap[code] {
                flushText()
                nodes.append((.dateFormat(pattern: pattern), codeLength))
                i += codeLength
                continue
            }

            // Unknown '%' sequence: treat literally.
            textBuffer.append("%")
            textSourceLength += 1
            i += 1
        }

        flushText()
        return nodes
    }

    // MARK: Keyword bodies

    private static func appendKeywordNode(
        keyword: String,
        body: String,
        sourceLength: Int,
        to nodes: inout [(node: MacroNode, sourceLength: Int)]
    ) {
        func emit(_ node: MacroNode) {
            nodes.append((node, sourceLength))
        }
        switch keyword {
        case "key:":
            emit(.key(name: String(body.dropFirst("key:".count)).lowercased()))
        case "snippet:", "Snippet:":
            emit(.nested(abbreviation: String(body.dropFirst(keyword.count))))
        case "date:":
            emit(.dateFormat(pattern: String(body.dropFirst("date:".count))))
        case "ai:":
            emit(.aiPrompt(String(body.dropFirst("ai:".count))))
        case "filltop":
            emit(.fillTop)
        case "fillpartend":
            emit(.fillPartEnd)
        case "fillpart":
            let params = parseParams(body: body, keyword: "fillpart")
            let defaultOn = (params["default"] ?? "no").lowercased() == "yes"
            emit(.fillPartStart(name: params["name"] ?? "", defaultOn: defaultOn))
        case "filltext":
            let params = parseParams(body: body, keyword: "filltext")
            emit(.fill(field: FillField(
                name: params["name"] ?? "",
                defaultValue: params["default"] ?? "",
                kind: .text(width: Int(params["width"] ?? "") ?? 20)
            )))
        case "fillarea":
            let params = parseParams(body: body, keyword: "fillarea")
            emit(.fill(field: FillField(
                name: params["name"] ?? "",
                defaultValue: params["default"] ?? "",
                kind: .area(width: Int(params["width"] ?? "") ?? 30,
                            height: Int(params["height"] ?? "") ?? 5)
            )))
        case "filldate":
            let params = parseParams(body: body, keyword: "filldate")
            emit(.fill(field: FillField(
                name: params["name"] ?? "",
                defaultValue: params["default"] ?? "",
                kind: .date(format: params["format"] ?? "yyyy-MM-dd")
            )))
        case "fillpopup":
            // Colon-separated values; "name=" labels the field, "default=" marks the default value.
            let parts = String(body.dropFirst("fillpopup".count))
                .split(separator: ":", omittingEmptySubsequences: false)
                .filter { !$0.isEmpty }
                .map(String.init)
            var name = ""
            var options: [String] = []
            var defaultIndex = 0
            for part in parts {
                if part.hasPrefix("name=") {
                    name = String(part.dropFirst("name=".count))
                } else if part.hasPrefix("default=") {
                    defaultIndex = options.count
                    options.append(String(part.dropFirst("default=".count)))
                } else {
                    options.append(part)
                }
            }
            if options.isEmpty { options = [""] }
            emit(.fill(field: FillField(
                name: name,
                defaultValue: options[min(defaultIndex, options.count - 1)],
                kind: .popup(options: options, defaultIndex: defaultIndex)
            )))
        default:
            break
        }
    }

    /// Parses ":name=X:default=Y:width=20" bodies into a dictionary.
    private static func parseParams(body: String, keyword: String) -> [String: String] {
        var params: [String: String] = [:]
        let paramString = String(body.dropFirst(keyword.count))
        for part in paramString.split(separator: ":", omittingEmptySubsequences: true) {
            if let eq = part.firstIndex(of: "=") {
                let key = String(part[..<eq])
                let value = String(part[part.index(after: eq)...])
                params[key] = value
            }
        }
        return params
    }

    // MARK: Field collection (for the fill-in window)

    /// Walks nodes (recursing into embedded snippets) and returns every fill
    /// field in display order, de-duplicated by name (same-name fields sync),
    /// plus whether a %filltop% was seen.
    static func collectFields(
        from nodes: [MacroNode],
        store: SnippetStore,
        depth: Int = 0
    ) -> [FillField] {
        guard depth < 10 else { return [] }
        var fields: [FillField] = []
        var seenNames = Set<String>()
        var autoIndex = 1

        func add(_ field: FillField) {
            var f = field
            if f.name.isEmpty {
                f.name = "Variable \(autoIndex)"
                autoIndex += 1
            }
            guard !seenNames.contains(f.name) else { return }
            seenNames.insert(f.name)
            fields.append(f)
        }

        func walk(_ nodes: [MacroNode], depth: Int) {
            guard depth < 10 else { return }
            for node in nodes {
                switch node {
                case .fill(let field):
                    add(field)
                case .fillPartStart(let name, let defaultOn):
                    add(FillField(name: name.isEmpty ? "" : name,
                                  defaultValue: defaultOn ? "yes" : "no",
                                  kind: .optionalPart(defaultOn: defaultOn)))
                case .nested(let abbreviation):
                    if let snippet = store.snippet(forAbbreviation: abbreviation),
                       !snippet.contentType.isScript {
                        walk(parse(snippet.content), depth: depth + 1)
                    }
                default:
                    break
                }
            }
        }

        walk(nodes, depth: depth)
        return fields
    }
}
