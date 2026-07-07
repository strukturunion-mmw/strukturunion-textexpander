import SwiftUI
import AppKit

struct SnippetDetailColumn: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: SnippetStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if let id = appState.selectedSnippetID, let binding = appState.binding(forSnippet: id) {
            SnippetEditor(snippet: binding)
                .id(id)
        } else {
            ContentUnavailableCompat(
                title: "No Snippet Selected",
                systemImage: "text.cursor",
                description: "Select a snippet, or press ⌘N to create one."
            )
        }
    }
}

struct SnippetEditor: View {
    @Binding var snippet: Snippet
    @EnvironmentObject var store: SnippetStore
    @EnvironmentObject var settings: AppSettings

    @State private var showAIAssistant = false
    @State private var showPreview = false
    @State private var previewText = ""
    @FocusState private var contentFocused: Bool

    private var conflicts: [Snippet] {
        store.conflicts(forAbbreviation: snippet.abbreviation, excludingSnippetID: snippet.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MacroEditingBar(snippet: $snippet)
            Divider()
            editorArea
            if !conflicts.isEmpty {
                Divider()
                ConflictBanner(conflicts: conflicts)
            }
            Divider()
            footer
        }
        .sheet(isPresented: $showAIAssistant) {
            AIAssistantView(snippet: $snippet)
        }
        .sheet(isPresented: $showPreview) {
            PreviewSheet(text: previewText)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Label", text: $snippet.label)
                    .textFieldStyle(.plain)
                    .font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $snippet.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            HStack(spacing: 8) {
                Text("Abbreviation")
                    .foregroundStyle(.secondary)
                TextField("abbr", text: $snippet.abbreviation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 220)

                Picker("", selection: $snippet.contentType) {
                    ForEach(SnippetContentType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)

                Spacer()

                Menu {
                    Picker("Case", selection: Binding(
                        get: { snippet.caseSensitivityOverride ?? settings.defaultCaseSensitivity },
                        set: { snippet.caseSensitivityOverride = $0 }
                    )) {
                        ForEach(CaseSensitivity.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Use Group Default") { snippet.caseSensitivityOverride = nil }
                } label: {
                    Image(systemName: "textformat.size")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Case sensitivity")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var editorArea: some View {
        if snippet.contentType == .richText {
            RichTextEditor(
                rtfData: $snippet.rtfData,
                plainMirror: $snippet.content
            )
            .focused($contentFocused)
        } else {
            CodeTextEditor(text: $snippet.content, isMonospaced: snippet.contentType.isScript)
                .focused($contentFocused)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                runPreview()
            } label: {
                Label("Preview", systemImage: "eye")
            }

            Button {
                showAIAssistant = true
            } label: {
                Label("AI Assist", systemImage: "sparkles")
            }
            .help("Use AI to draft or refine this snippet")

            Spacer()

            if snippet.useCount > 0 {
                Text("Expanded \(snippet.useCount)×")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.bar)
    }

    private func runPreview() {
        Task { @MainActor in
            let evaluator = MacroEvaluator()
            var state = MacroEvaluator.EvaluationState()
            if snippet.contentType.isScript {
                previewText = await evaluator.runScript(snippet: snippet, state: &state)
            } else {
                // For preview, use default fill values.
                let nodes = MacroParser.parse(snippet.content)
                let fields = MacroParser.collectFields(from: nodes, store: store)
                state.fillValues = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.defaultValue) })
                let rendered = await evaluator.evaluate(nodes: nodes, state: &state)
                previewText = rendered.plainText
            }
            showPreview = true
        }
    }
}

struct ConflictBanner: View {
    let conflicts: [Snippet]
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Abbreviation conflict")
                    .font(.caption.bold())
                Text(conflicts.map { $0.abbreviation.isEmpty ? "(empty)" : $0.abbreviation }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
    }
}

struct PreviewSheet: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview").font(.headline)
            ScrollView {
                Text(text.isEmpty ? "(empty expansion)" : text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
            }
            .frame(minHeight: 120)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: 300)
    }
}

/// Fallback for ContentUnavailableView on macOS 13.
struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let description: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.bold())
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
