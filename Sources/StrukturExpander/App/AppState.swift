import SwiftUI
import Combine

/// Shared UI state for the main window's SwiftUI views.
@MainActor
final class AppState: ObservableObject {
    let store = SnippetStore.shared
    let settings = AppSettings.shared

    @Published var selectedGroupID: UUID?
    @Published var selectedSnippetID: UUID?
    @Published var searchText: String = ""

    init() {
        selectedGroupID = store.groups.first?.id
    }

    var selectedGroup: SnippetGroup? {
        guard let id = selectedGroupID else { return nil }
        return store.group(withID: id)
    }

    var visibleSnippets: [Snippet] {
        let base: [Snippet]
        if let group = selectedGroup {
            base = group.snippets
        } else {
            base = store.allSnippets
        }
        guard !searchText.isEmpty else { return base }
        let needle = searchText.lowercased()
        return base.filter {
            $0.abbreviation.lowercased().contains(needle)
                || $0.label.lowercased().contains(needle)
                || $0.content.lowercased().contains(needle)
        }
    }

    func binding(forSnippet id: UUID) -> Binding<Snippet>? {
        guard store.snippet(withID: id) != nil else { return nil }
        return Binding<Snippet>(
            get: { self.store.snippet(withID: id) ?? Snippet() },
            set: { self.store.updateSnippet($0); self.objectWillChange.send() }
        )
    }

    func binding(forGroup id: UUID) -> Binding<SnippetGroup>? {
        guard let index = store.groups.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding<SnippetGroup>(
            get: { self.store.groups[index] },
            set: { self.store.groups[index] = $0; self.objectWillChange.send() }
        )
    }
}
