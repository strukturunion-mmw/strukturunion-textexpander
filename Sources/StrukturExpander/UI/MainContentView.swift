import SwiftUI

struct MainContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: SnippetStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            GroupSidebar()
                .frame(minWidth: 220)
        } content: {
            SnippetListColumn()
                .frame(minWidth: 260)
        } detail: {
            SnippetDetailColumn()
                .frame(minWidth: 380)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { settings.expansionEnabled },
                    set: { settings.expansionEnabled = $0
                        NotificationCenter.default.post(name: .expansionEnabledChanged, object: nil) }
                )) {
                    Label(settings.expansionEnabled ? "Expansion On" : "Expansion Off",
                          systemImage: settings.expansionEnabled ? "checkmark.circle.fill" : "pause.circle")
                }
                .toggleStyle(.button)
                .help("Enable or disable all expansion")
            }
        }
    }
}

// MARK: - Sidebar (groups)

struct GroupSidebar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: SnippetStore
    @State private var showingGroupSettings = false

    var body: some View {
        List(selection: $appState.selectedGroupID) {
            Section("Snippet Groups") {
                ForEach(store.groups) { group in
                    GroupRow(group: group)
                        .tag(group.id)
                        .contextMenu {
                            Button("Group Settings…") {
                                appState.selectedGroupID = group.id
                                showingGroupSettings = true
                            }
                            Button("Duplicate") { duplicate(group) }
                            Divider()
                            Button("Delete", role: .destructive) { delete(group) }
                        }
                }
                .onMove(perform: moveGroups)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(action: addGroup) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New group")

                Button(action: { if let g = appState.selectedGroup { delete(g) } }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(appState.selectedGroup == nil)
                .help("Delete selected group")

                Button(action: { showingGroupSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .disabled(appState.selectedGroup == nil)
                .help("Group settings")

                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
        .sheet(isPresented: $showingGroupSettings) {
            if let id = appState.selectedGroupID, let binding = appState.binding(forGroup: id) {
                GroupSettingsView(group: binding)
            }
        }
    }

    private func addGroup() {
        let group = SnippetGroup(name: "Untitled Group")
        store.addGroup(group)
        appState.selectedGroupID = group.id
    }

    private func delete(_ group: SnippetGroup) {
        store.removeGroup(id: group.id)
        if appState.selectedGroupID == group.id {
            appState.selectedGroupID = store.groups.first?.id
        }
    }

    private func duplicate(_ group: SnippetGroup) {
        var copy = group
        copy.id = UUID()
        copy.name += " copy"
        copy.snippets = group.snippets.map { s in
            var ns = s; ns.id = UUID(); return ns
        }
        store.addGroup(copy)
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        store.groups.move(fromOffsets: source, toOffset: destination)
    }
}

struct GroupRow: View {
    let group: SnippetGroup

    var body: some View {
        HStack {
            Image(systemName: group.enabled ? "folder.fill" : "folder")
                .foregroundStyle(group.enabled ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name).lineLimit(1)
                Text("\(group.snippets.count) snippet\(group.snippets.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if group.appPolicyMode != .allApps {
                Image(systemName: "app.badge")
                    .foregroundStyle(.secondary)
                    .help("App-specific group")
            }
        }
    }
}
