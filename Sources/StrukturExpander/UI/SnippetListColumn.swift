import SwiftUI

struct SnippetListColumn: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: SnippetStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $appState.selectedSnippetID) {
                ForEach(appState.visibleSnippets) { snippet in
                    SnippetRow(snippet: snippet, conflicts: store.conflicts(
                        forAbbreviation: snippet.abbreviation, excludingSnippetID: snippet.id))
                        .tag(snippet.id)
                        .contextMenu {
                            Button("Duplicate") { duplicate(snippet) }
                            Menu("Move to Group") {
                                ForEach(store.groups) { g in
                                    Button(g.name) { store.moveSnippet(id: snippet.id, to: g.id) }
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { delete(snippet) }
                        }
                }
                .onDelete(perform: deleteAt)
            }
            .searchable(text: $appState.searchText, placement: .automatic, prompt: "Search snippets")

            Divider()
            HStack(spacing: 12) {
                Button(action: addSnippet) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New snippet")

                Button(action: { if let id = appState.selectedSnippetID, let s = store.snippet(withID: id) { delete(s) } }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(appState.selectedSnippetID == nil)
                .help("Delete snippet")

                Spacer()
                Text("\(appState.visibleSnippets.count) snippets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.bar)
        }
    }

    private func addSnippet() {
        guard let groupID = appState.selectedGroupID ?? store.groups.first?.id else { return }
        var snippet = Snippet()
        if let group = store.group(withID: groupID), !group.suggestedPrefixEmpty {
            snippet.abbreviation = ""
        }
        store.addSnippet(snippet, to: groupID)
        appState.selectedGroupID = groupID
        appState.selectedSnippetID = snippet.id
    }

    private func delete(_ snippet: Snippet) {
        store.removeSnippet(id: snippet.id)
        if appState.selectedSnippetID == snippet.id {
            appState.selectedSnippetID = nil
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        let snippets = appState.visibleSnippets
        for index in offsets {
            store.removeSnippet(id: snippets[index].id)
        }
    }

    private func duplicate(_ snippet: Snippet) {
        guard let group = store.groupContaining(snippetID: snippet.id) else { return }
        var copy = snippet
        copy.id = UUID()
        copy.abbreviation += "2"
        store.addSnippet(copy, to: group.id)
    }
}

struct SnippetRow: View {
    let snippet: Snippet
    let conflicts: [Snippet]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.displayLabel)
                    .lineLimit(1)
                    .foregroundStyle(snippet.enabled ? .primary : .secondary)
                if !snippet.abbreviation.isEmpty {
                    Text(snippet.abbreviation)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(conflicts.isEmpty ? Color.secondary : Color.orange)
                }
            }
            Spacer()
            if !conflicts.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Conflicts with \(conflicts.count) other abbreviation(s)")
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch snippet.contentType {
        case .plainText: return "text.alignleft"
        case .richText: return "textformat"
        case .appleScript: return "scroll"
        case .shellScript: return "terminal"
        case .javaScript: return "curlybraces"
        }
    }
}

extension SnippetGroup {
    var suggestedPrefixEmpty: Bool { prefix.isEmpty }
}
