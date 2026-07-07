import SwiftUI

/// AI assistant: draft or refine snippet content via OpenRouter.
/// Mirrors TextExpander's "AI snippet recommendations" but local + OpenRouter-backed.
struct AIAssistantView: View {
    @Binding var snippet: Snippet
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    @State private var instruction: String = ""
    @State private var result: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var mode: Mode = .draft

    enum Mode: String, CaseIterable, Identifiable {
        case draft = "Draft New"
        case refine = "Refine Current"
        case suggestAbbr = "Suggest Abbreviation"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Assistant", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text(settings.openRouterModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.openRouterAPIKey.isEmpty {
                noKeyBanner
            }

            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(promptLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $instruction)
                .font(.body)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Button {
                    run()
                } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Generate")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isLoading || settings.openRouterAPIKey.isEmpty
                          || (mode != .suggestAbbr && instruction.isEmpty))
                Spacer()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !result.isEmpty {
                Divider()
                Text("Result").font(.subheadline.bold())
                ScrollView {
                    Text(result)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor))
                }
                .frame(height: 120)
                HStack {
                    Button(applyButtonTitle) { apply() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 520, height: 560)
    }

    private var noKeyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.slash")
            Text("Add an OpenRouter API key in Settings → AI to use the assistant.")
                .font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var promptLabel: String {
        switch mode {
        case .draft: return "Describe the snippet you want (e.g. \"a polite meeting-reschedule email with a fill-in for the new time\")."
        case .refine: return "How should the current content be changed? (e.g. \"make it more concise and friendly\")"
        case .suggestAbbr: return "Suggests a short abbreviation for the current content. No input needed."
        }
    }

    private var applyButtonTitle: String {
        mode == .suggestAbbr ? "Use as Abbreviation" : "Replace Content"
    }

    private func run() {
        errorMessage = nil
        result = ""
        isLoading = true
        let currentContent = snippet.content
        let selectedMode = mode
        let userInstruction = instruction

        Task { @MainActor in
            defer { isLoading = false }
            do {
                let messages = buildMessages(mode: selectedMode, content: currentContent, instruction: userInstruction)
                result = try await OpenRouterClient.shared.chat(messages: messages)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func buildMessages(mode: Mode, content: String, instruction: String) -> [OpenRouterClient.Message] {
        switch mode {
        case .draft:
            return [
                .init(role: "system", content: "You write text-expansion snippets. You may use these macros where helpful: %filltext:name=X% for a fill-in field, %| for the final cursor position, %clipboard for pasted clipboard text, and date codes like %B %e, %Y. Reply with ONLY the snippet content, no explanation or code fences."),
                .init(role: "user", content: instruction),
            ]
        case .refine:
            return [
                .init(role: "system", content: "You refine text-expansion snippets. Preserve any %…% macros unless asked to change them. Reply with ONLY the revised snippet content, no explanation or code fences."),
                .init(role: "user", content: "Current snippet:\n\n\(content)\n\nInstruction: \(instruction)"),
            ]
        case .suggestAbbr:
            return [
                .init(role: "system", content: "Suggest a single short, memorable abbreviation (3-8 lowercase characters, no spaces) for the given text-expansion snippet. Reply with ONLY the abbreviation."),
                .init(role: "user", content: content.isEmpty ? snippet.label : content),
            ]
        }
    }

    private func apply() {
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .suggestAbbr:
            snippet.abbreviation = cleaned.components(separatedBy: .whitespacesAndNewlines).first ?? cleaned
        case .draft, .refine:
            snippet.content = cleaned
            if snippet.contentType == .richText {
                snippet.rtfData = nil // fall back to plain until re-edited
            }
        }
        dismiss()
    }
}
