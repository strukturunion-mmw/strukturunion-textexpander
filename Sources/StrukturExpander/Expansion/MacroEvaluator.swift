import Foundation
import AppKit

/// Evaluates parsed MacroNodes into a RenderedExpansion.
/// Handles rolling date math, fill-in values, optional sections, embedded
/// snippets, script execution and the %ai:% extension.
final class MacroEvaluator {

    struct EvaluationState {
        var fillValues: [String: String] = [:]
        /// Rolling date used by date macros; date math mutates it.
        var currentDate: Date = Date()
        var triggeringAbbreviation: String = ""
        var depth: Int = 0
    }

    private let store: SnippetStore
    private let settings: AppSettings

    init(store: SnippetStore = .shared, settings: AppSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    /// Evaluates a snippet's parsed nodes. Fill values must already be resolved.
    func evaluate(nodes: [MacroNode], state: inout EvaluationState) async -> RenderedExpansion {
        var result = RenderedExpansion()
        var textLengthAfterCursor = 0
        var textLengthAfterSelectionEnd: Int? = nil
        var sawCursor = false

        // Pre-scan optional sections: build a stack-aware include mask.
        let includedNodes = filterOptionalParts(nodes: nodes, fillValues: state.fillValues)

        func appendText(_ s: String) {
            guard !s.isEmpty else { return }
            if case .text(let existing)? = result.segments.last {
                result.segments[result.segments.count - 1] = .text(existing + s)
            } else {
                result.segments.append(.text(s))
            }
            if sawCursor { textLengthAfterCursor += s.count }
            if textLengthAfterSelectionEnd != nil { textLengthAfterSelectionEnd! += s.count }
        }

        for node in includedNodes {
            switch node {
            case .text(let s):
                appendText(s)

            case .dateFormat(let pattern):
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                formatter.dateFormat = pattern
                appendText(formatter.string(from: state.currentDate))

            case .dateMath(let value, let unit):
                var components = DateComponents()
                switch unit {
                case "Y": components.year = value
                case "M": components.month = value
                case "D": components.day = value
                case "h": components.hour = value
                case "m": components.minute = value
                case "s": components.second = value
                default: break
                }
                state.currentDate = Calendar.current.date(byAdding: components, to: state.currentDate) ?? state.currentDate

            case .clipboard:
                appendText(NSPasteboard.general.string(forType: .string) ?? "")

            case .cursor:
                sawCursor = true
                textLengthAfterCursor = 0

            case .selectionEnd:
                textLengthAfterSelectionEnd = 0

            case .key(let name):
                result.segments.append(.keyPress(name: name))

            case .arrow(let direction):
                result.segments.append(.arrow(direction: direction))

            case .nested(let abbreviation):
                guard state.depth < 10 else { break }
                if let snippet = store.snippet(forAbbreviation: abbreviation) {
                    if snippet.contentType.isScript {
                        let output = await runScript(snippet: snippet, state: &state)
                        appendText(output)
                    } else {
                        var nestedState = state
                        nestedState.depth += 1
                        let nested = await evaluate(nodes: MacroParser.parse(snippet.content), state: &nestedState)
                        state.currentDate = nestedState.currentDate
                        appendText(nested.plainText)
                    }
                } else {
                    appendText("%snippet:\(abbreviation)%")
                }

            case .fill(let field):
                let name = field.name
                let value = state.fillValues[name] ?? field.defaultValue
                if case .date(let format) = field.kind {
                    // Fill value for date pickers is stored as an ISO timestamp.
                    if let interval = TimeInterval(value) {
                        let formatter = DateFormatter()
                        formatter.locale = Locale.current
                        formatter.dateFormat = format
                        appendText(formatter.string(from: Date(timeIntervalSince1970: interval)))
                    } else {
                        appendText(value)
                    }
                } else {
                    appendText(value)
                }

            case .fillPartStart, .fillPartEnd, .fillTop:
                break // handled by filterOptionalParts / fill window ordering

            case .delimiterOverride(let keep):
                result.keepDelimiterOverride = keep

            case .aiPrompt(let prompt):
                let resolved = resolveAIPromptPlaceholders(prompt, state: state)
                do {
                    let completion = try await OpenRouterClient.shared.complete(prompt: resolved)
                    appendText(completion)
                } catch {
                    appendText("[AI error: \(error.localizedDescription)]")
                }
            }
        }

        if sawCursor {
            if let afterSelection = textLengthAfterSelectionEnd {
                // %|selected%\ : move back past the tail, then shift-select the
                // range between the two markers (cursor lands on the %| side).
                result.cursorBackOffset = afterSelection
                result.selectionLength = max(0, textLengthAfterCursor - afterSelection)
            } else {
                result.cursorBackOffset = textLengthAfterCursor
            }
        }
        return result
    }

    /// Removes optional-section content whose checkbox was left off.
    /// Sections may not nest (matching TextExpander).
    private func filterOptionalParts(nodes: [MacroNode], fillValues: [String: String]) -> [MacroNode] {
        var result: [MacroNode] = []
        var skipping = false
        var autoIndex = 1
        var seenNames = Set<String>()

        for node in nodes {
            switch node {
            case .fillPartStart(let name, let defaultOn):
                var effectiveName = name
                if effectiveName.isEmpty {
                    effectiveName = "Variable \(autoIndex)"
                }
                // Track auto-index consistently with field collection: every
                // unnamed field bumps the counter, so recount below.
                autoIndex += name.isEmpty ? 1 : 0
                seenNames.insert(effectiveName)
                let value = fillValues[effectiveName] ?? (defaultOn ? "yes" : "no")
                skipping = value.lowercased() != "yes"
            case .fillPartEnd:
                skipping = false
            case .fill(let field) where field.name.isEmpty:
                if !skipping {
                    var f = field
                    f.name = "Variable \(autoIndex)"
                    result.append(.fill(field: f))
                }
                autoIndex += 1
            default:
                if !skipping { result.append(node) }
            }
        }
        return result
    }

    /// {clipboard} and {fill:Name} placeholders inside %ai:% prompts.
    private func resolveAIPromptPlaceholders(_ prompt: String, state: EvaluationState) -> String {
        var resolved = prompt.replacingOccurrences(
            of: "{clipboard}",
            with: NSPasteboard.general.string(forType: .string) ?? ""
        )
        for (name, value) in state.fillValues {
            resolved = resolved.replacingOccurrences(of: "{fill:\(name)}", with: value)
        }
        return resolved
    }

    // MARK: Scripts

    /// Runs a script snippet: fills, dates and clipboard macros inside the
    /// source are substituted first, then the script executes.
    func runScript(snippet: Snippet, state: inout EvaluationState) async -> String {
        guard settings.runScriptSnippets else { return "" }
        let source = await renderScriptSource(snippet.content, state: &state)
        do {
            switch snippet.contentType {
            case .appleScript:
                return try await ScriptRunner.runAppleScript(source)
            case .shellScript:
                return try await ScriptRunner.runShellScript(source)
            case .javaScript:
                return try ScriptRunner.runJavaScript(
                    source,
                    fillValues: state.fillValues,
                    triggeringAbbreviation: state.triggeringAbbreviation,
                    baseDate: state.currentDate
                )
            default:
                return snippet.content
            }
        } catch {
            return "[Script error: \(error.localizedDescription)]"
        }
    }

    /// Substitutes text-producing macros inside script source code.
    private func renderScriptSource(_ source: String, state: inout EvaluationState) async -> String {
        let nodes = MacroParser.parse(source)
        var output = ""
        for node in nodes {
            switch node {
            case .text(let s):
                output += s
            case .dateFormat(let pattern):
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                formatter.dateFormat = pattern
                output += formatter.string(from: state.currentDate)
            case .dateMath(let value, let unit):
                var components = DateComponents()
                switch unit {
                case "Y": components.year = value
                case "M": components.month = value
                case "D": components.day = value
                case "h": components.hour = value
                case "m": components.minute = value
                case "s": components.second = value
                default: break
                }
                state.currentDate = Calendar.current.date(byAdding: components, to: state.currentDate) ?? state.currentDate
            case .clipboard:
                output += NSPasteboard.general.string(forType: .string) ?? ""
            case .fill(let field):
                output += state.fillValues[field.name] ?? field.defaultValue
            case .nested(let abbreviation):
                if state.depth < 10, let nested = store.snippet(forAbbreviation: abbreviation) {
                    if nested.contentType.isScript {
                        var nestedState = state
                        nestedState.depth += 1
                        output += await runScript(snippet: nested, state: &nestedState)
                    } else {
                        output += nested.content
                    }
                }
            case .cursor, .selectionEnd, .key, .arrow, .fillPartStart, .fillPartEnd, .fillTop, .delimiterOverride:
                break
            case .aiPrompt(let prompt):
                let resolved = resolveAIPromptPlaceholders(prompt, state: state)
                output += (try? await OpenRouterClient.shared.complete(prompt: resolved)) ?? ""
            }
        }
        return output
    }
}
