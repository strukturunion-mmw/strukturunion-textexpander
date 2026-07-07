import SwiftUI
import AppKit

struct GroupSettingsView: View {
    @Binding var group: SnippetGroup
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var settings: AppSettings

    @State private var showingAppPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Group Settings")
                .font(.headline)
                .padding()
            Divider()

            Form {
                Section("General") {
                    TextField("Name", text: $group.name)
                    Toggle("Enabled", isOn: $group.enabled)
                    TextField("Abbreviation prefix", text: $group.prefix)
                        .help("Prepended to every abbreviation in this group, e.g. \";\"")
                }

                Section("Expansion") {
                    Picker("Case sensitivity", selection: Binding(
                        get: { group.caseSensitivity ?? settings.defaultCaseSensitivity },
                        set: { group.caseSensitivity = $0 }
                    )) {
                        ForEach(CaseSensitivity.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Expand when", selection: Binding(
                        get: { group.triggerContext ?? settings.defaultTriggerContext },
                        set: { group.triggerContext = $0 }
                    )) {
                        ForEach(TriggerContext.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section("Applications") {
                    Picker("Expand in", selection: $group.appPolicyMode) {
                        ForEach(AppPolicyMode.allCases) { Text($0.displayName).tag($0) }
                    }
                    if group.appPolicyMode != .allApps {
                        AppListEditor(bundleIDs: $group.appPolicyBundleIDs)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $group.notes)
                        .frame(height: 60)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 560)
    }
}

/// Editor for a list of app bundle identifiers, with a picker of running/installed apps.
struct AppListEditor: View {
    @Binding var bundleIDs: [String]
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(bundleIDs, id: \.self) { id in
                HStack {
                    Image(nsImage: AppCatalog.icon(forBundleID: id))
                        .resizable().frame(width: 16, height: 16)
                    Text(AppCatalog.name(forBundleID: id))
                    Spacer()
                    Button {
                        bundleIDs.removeAll { $0 == id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                showingPicker = true
            } label: {
                Label("Add Application…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .sheet(isPresented: $showingPicker) {
            AppPickerView { id in
                if !bundleIDs.contains(id) { bundleIDs.append(id) }
                showingPicker = false
            }
        }
    }
}

struct AppPickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    private var apps: [AppCatalog.AppEntry] {
        let all = AppCatalog.installedApps()
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search applications", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            Divider()
            List(apps) { app in
                HStack {
                    Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                    Text(app.name)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(app.bundleID) }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding(10)
        }
        .frame(width: 380, height: 460)
    }
}
