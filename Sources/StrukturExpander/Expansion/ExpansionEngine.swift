import Foundation
import AppKit
import Carbon.HIToolbox

/// A snippet match produced by the KeystrokeMonitor.
struct ExpansionMatch {
    var snippet: Snippet
    var group: SnippetGroup
    /// The abbreviation exactly as typed (including group prefix, original case).
    var typedAbbreviation: String
    /// The delimiter character the user typed (delimiter expansion modes only).
    var typedDelimiter: Character?
}

/// Record of the last expansion, used for "delete restores abbreviation"
/// and "repeat last expansion".
struct LastExpansionRecord {
    var match: ExpansionMatch
    var insertedPlainLength: Int
    var fillValues: [String: String]
    var date: Date
}

/// Orchestrates a full expansion: erase the typed abbreviation, gather
/// fill-in values, evaluate macros, inject the result, play feedback.
@MainActor
final class ExpansionEngine: ObservableObject {
    static let shared = ExpansionEngine()

    private let store = SnippetStore.shared
    private let settings = AppSettings.shared

    private(set) var lastExpansion: LastExpansionRecord?
    /// True while an expansion is being delivered (monitor suspends matching).
    private(set) var isExpanding = false

    func clearLastExpansion() {
        lastExpansion = nil
    }

    // MARK: Entry point

    func expand(match: ExpansionMatch) {
        guard !isExpanding else { return }
        isExpanding = true
        Task { @MainActor in
            await self.performExpansion(match: match, presetFillValues: nil)
            self.isExpanding = false
        }
    }

    /// Repeat Last Expansion (Cmd+0 equivalent) — replays content and fill values.
    func repeatLastExpansion() {
        guard let last = lastExpansion, !isExpanding else { return }
        isExpanding = true
        Task { @MainActor in
            await self.performExpansion(match: last.match, presetFillValues: last.fillValues, eraseTyped: false)
            self.isExpanding = false
        }
    }

    /// Inserts a snippet directly (inline search / quick actions), no abbreviation to erase.
    func insertSnippet(_ snippet: Snippet, group: SnippetGroup?) {
        guard !isExpanding else { return }
        let match = ExpansionMatch(
            snippet: snippet,
            group: group ?? SnippetGroup(name: ""),
            typedAbbreviation: "",
            typedDelimiter: nil
        )
        isExpanding = true
        Task { @MainActor in
            await self.performExpansion(match: match, presetFillValues: nil, eraseTyped: false)
            self.isExpanding = false
        }
    }

    // MARK: Pipeline

    private func performExpansion(
        match: ExpansionMatch,
        presetFillValues: [String: String]?,
        eraseTyped: Bool = true
    ) async {
        let snippet = match.snippet
        let previousApp = NSWorkspace.shared.frontmostApplication

        // 1. Erase what the user typed (abbreviation + delimiter, if any).
        if eraseTyped {
            var eraseCount = match.typedAbbreviation.count
            if match.typedDelimiter != nil { eraseCount += 1 }
            TextInjector.deleteBackward(count: eraseCount)
        }

        // 2. Parse and gather fill-in values if needed.
        let nodes = MacroParser.parse(snippet.contentType.isScript ? "" : snippet.content)
        var fillValues = presetFillValues ?? [:]

        if presetFillValues == nil {
            let scriptNodes = snippet.contentType.isScript ? MacroParser.parse(snippet.content) : nodes
            let fields = MacroParser.collectFields(from: scriptNodes, store: store)
            if !fields.isEmpty {
                guard let values = await FillInWindowController.present(
                    fields: fields,
                    snippetLabel: snippet.displayLabel,
                    previousApp: previousApp
                ) else {
                    // Cancelled: restore the abbreviation the user typed.
                    if eraseTyped, !match.typedAbbreviation.isEmpty {
                        reactivate(previousApp)
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        var restore = match.typedAbbreviation
                        if let d = match.typedDelimiter { restore.append(d) }
                        TextInjector.typeString(restore)
                    }
                    return
                }
                fillValues = values
                reactivate(previousApp)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        // 3. Evaluate.
        var state = MacroEvaluator.EvaluationState(
            fillValues: fillValues,
            triggeringAbbreviation: match.typedAbbreviation
        )
        let evaluator = MacroEvaluator(store: store, settings: settings)

        var rendered: RenderedExpansion
        if snippet.contentType.isScript {
            let output = await evaluator.runScript(snippet: snippet, state: &state)
            rendered = RenderedExpansion(segments: [.text(output)])
        } else if snippet.contentType == .richText, let rtfData = snippet.rtfData {
            rendered = await renderRichText(rtfData: rtfData, content: snippet.content, evaluator: evaluator, state: &state)
        } else {
            rendered = await evaluator.evaluate(nodes: nodes, state: &state)
        }

        // 4. Adapt case (plain text only).
        let effectiveCase = snippet.caseSensitivityOverride
            ?? match.group.caseSensitivity
            ?? settings.defaultCaseSensitivity
        if effectiveCase == .adaptToCase, rendered.rtfdData == nil, !match.typedAbbreviation.isEmpty {
            rendered = adaptCase(of: rendered, toTyped: match.typedAbbreviation, defined: match.group.effectiveAbbreviation(for: snippet))
        }

        // 5. Delimiter handling: re-type a kept delimiter after the expansion.
        let keepDelimiter = rendered.keepDelimiterOverride ?? (settings.expansionMode == .delimiterKeep)
        var trailingDelimiter: Character? = nil
        if let d = match.typedDelimiter, keepDelimiter {
            trailingDelimiter = d
        }

        // 6. Inject.
        await inject(rendered: rendered, trailingDelimiter: trailingDelimiter)

        // 7. Bookkeeping.
        let insertedLength = rendered.plainText.count + (trailingDelimiter != nil ? 1 : 0)
        lastExpansion = LastExpansionRecord(
            match: match,
            insertedPlainLength: insertedLength,
            fillValues: fillValues,
            date: Date()
        )
        store.recordUse(of: snippet.id)
        let saved = max(0, rendered.plainText.count - match.typedAbbreviation.count)
        settings.totalExpansions += 1
        settings.totalCharactersSaved += saved
        StatisticsLog.shared.record(snippetID: snippet.id, charactersSaved: saved)

        if settings.playSoundOnExpansion {
            NSSound(named: settings.expansionSoundName)?.play()
        }
    }

    private func reactivate(_ app: NSRunningApplication?) {
        app?.activate(options: [])
    }

    // MARK: Injection

    private func inject(rendered: RenderedExpansion, trailingDelimiter: Character?) async {
        // Rich text goes through the pasteboard in one shot.
        if let rtfd = rendered.rtfdData {
            await withCheckedContinuation { continuation in
                TextInjector.paste(
                    rtfdData: rtfd,
                    plainFallback: rendered.plainText,
                    restoreClipboard: settings.restoreClipboard
                ) { continuation.resume() }
            }
            if let d = trailingDelimiter { TextInjector.typeString(String(d)) }
            applyCursorMoves(rendered: rendered, trailingDelimiter: trailingDelimiter)
            return
        }

        // Plain text: segments of text interleaved with key/arrow presses.
        let useKeystrokes = settings.insertionMethod == .keystrokes
        for segment in rendered.segments {
            switch segment {
            case .text(let text):
                guard !text.isEmpty else { continue }
                if useKeystrokes {
                    TextInjector.typeString(text)
                } else {
                    await withCheckedContinuation { continuation in
                        TextInjector.paste(plainText: text, restoreClipboard: settings.restoreClipboard) {
                            continuation.resume()
                        }
                    }
                }
            case .keyPress(let name):
                switch name {
                case "return", "enter": TextInjector.postKey(CGKeyCode(kVK_Return))
                case "tab": TextInjector.postKey(CGKeyCode(kVK_Tab))
                case "escape", "esc": TextInjector.postKey(CGKeyCode(kVK_Escape))
                case "delete", "backspace": TextInjector.postKey(CGKeyCode(kVK_Delete))
                case "space": TextInjector.postKey(CGKeyCode(kVK_Space))
                default: break
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            case .arrow(let direction):
                switch direction {
                case .up: TextInjector.postKey(CGKeyCode(kVK_UpArrow))
                case .down: TextInjector.postKey(CGKeyCode(kVK_DownArrow))
                case .left: TextInjector.postKey(CGKeyCode(kVK_LeftArrow))
                case .right: TextInjector.postKey(CGKeyCode(kVK_RightArrow))
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        if let d = trailingDelimiter {
            if d == "\n" {
                TextInjector.postKey(CGKeyCode(kVK_Return))
            } else if d == "\t" {
                TextInjector.postKey(CGKeyCode(kVK_Tab))
            } else {
                TextInjector.typeString(String(d))
            }
        }
        applyCursorMoves(rendered: rendered, trailingDelimiter: trailingDelimiter)
    }

    private func applyCursorMoves(rendered: RenderedExpansion, trailingDelimiter: Character?) {
        guard let backOffset = rendered.cursorBackOffset else { return }
        let total = backOffset + (trailingDelimiter != nil ? 1 : 0)
        TextInjector.moveCursorLeft(count: total)
        if let selection = rendered.selectionLength, selection > 0 {
            for _ in 0..<selection {
                TextInjector.postKey(CGKeyCode(kVK_LeftArrow), flags: .maskShift)
                usleep(1500)
            }
        }
    }

    // MARK: Rich text rendering

    /// Replaces macros inside an RTFD attributed string, preserving formatting.
    /// `content` must be the exact plain-text mirror of the attributed string.
    private func renderRichText(
        rtfData: Data,
        content: String,
        evaluator: MacroEvaluator,
        state: inout MacroEvaluator.EvaluationState
    ) async -> RenderedExpansion {
        var result = RenderedExpansion()

        guard let attributed = try? NSMutableAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) else {
            // Fall back to plain evaluation.
            return await evaluator.evaluate(nodes: MacroParser.parse(content), state: &state)
        }

        let parsed = MacroParser.parseWithLengths(content)
        let fields = MacroParser.collectFields(from: parsed.map { $0.node }, store: store)
        _ = fields // fill values already resolved by caller

        var location = 0
        var cursorLocation: Int? = nil
        var keepDelimiterOverride: Bool? = nil

        // NSAttributedString uses UTF-16 offsets; track source in UTF-16 too.
        func utf16Length(_ s: Substring) -> Int { s.utf16.count }

        var sourceOffsetChars = 0
        let contentChars = Array(content)

        for (node, sourceLength) in parsed {
            let sourceText = String(contentChars[sourceOffsetChars..<min(sourceOffsetChars + sourceLength, contentChars.count)])
            let sourceUTF16 = sourceText.utf16.count
            sourceOffsetChars += sourceLength

            switch node {
            case .text(let s):
                // Text may differ from source (e.g. "%%" -> "%"): replace if needed.
                if s == sourceText {
                    location += sourceUTF16
                } else {
                    attributed.replaceCharacters(in: NSRange(location: location, length: sourceUTF16), with: s)
                    location += s.utf16.count
                }
            case .cursor:
                attributed.replaceCharacters(in: NSRange(location: location, length: sourceUTF16), with: "")
                cursorLocation = location
            case .delimiterOverride(let keep):
                attributed.replaceCharacters(in: NSRange(location: location, length: sourceUTF16), with: "")
                keepDelimiterOverride = keep
            case .selectionEnd, .key, .arrow, .fillPartStart, .fillPartEnd, .fillTop:
                // Not supported inside rich text: strip the macro.
                attributed.replaceCharacters(in: NSRange(location: location, length: sourceUTF16), with: "")
            default:
                // Text-producing macro: evaluate it in isolation.
                let mini = await evaluator.evaluate(nodes: [node], state: &state)
                let replacement = mini.plainText
                let attrs: [NSAttributedString.Key: Any] =
                    location < attributed.length
                        ? attributed.attributes(at: location, effectiveRange: nil)
                        : (attributed.length > 0 ? attributed.attributes(at: attributed.length - 1, effectiveRange: nil) : [:])
                attributed.replaceCharacters(
                    in: NSRange(location: location, length: sourceUTF16),
                    with: NSAttributedString(string: replacement, attributes: attrs)
                )
                location += replacement.utf16.count
            }
        }

        let range = NSRange(location: 0, length: attributed.length)
        result.rtfdData = attributed.rtfd(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        result.segments = [.text(attributed.string)]
        result.keepDelimiterOverride = keepDelimiterOverride
        if let cursorLocation {
            result.cursorBackOffset = (attributed.string as NSString).substring(from: cursorLocation).count
        }
        return result
    }

    // MARK: Case adaptation

    /// "Adapt to Case of Abbreviation": typed "Abbr" capitalizes the expansion,
    /// typed "ABBR" (all caps, length > 1) upper-cases it entirely.
    private func adaptCase(of rendered: RenderedExpansion, toTyped typed: String, defined: String) -> RenderedExpansion {
        guard typed != defined else { return rendered }
        var result = rendered

        let isAllCaps = typed.count > 1 && typed == typed.uppercased() && typed.rangeOfCharacter(from: .lowercaseLetters) == nil
        let firstTyped = typed.first.map(String.init) ?? ""
        let isFirstCapped = firstTyped == firstTyped.uppercased() && firstTyped != firstTyped.lowercased()

        func transform(_ text: String, isFirstSegment: Bool) -> String {
            if isAllCaps { return text.uppercased() }
            if isFirstCapped && isFirstSegment && !text.isEmpty {
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            return text
        }

        var first = true
        result.segments = result.segments.map { segment in
            if case .text(let t) = segment {
                let transformed = transform(t, isFirstSegment: first)
                first = false
                return .text(transformed)
            }
            return segment
        }
        return result
    }
}
