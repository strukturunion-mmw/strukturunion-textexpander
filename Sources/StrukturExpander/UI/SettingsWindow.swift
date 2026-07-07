import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hosting = NSHostingController(rootView: SettingsView()
            .environmentObject(AppSettings.shared))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 560))
        self.init(window: window)
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            ExpansionSettingsTab().tabItem { Label("Expansion", systemImage: "arrow.up.left.and.arrow.down.right") }
            OptionsSettingsTab().tabItem { Label("Options", systemImage: "textformat.abc") }
            HotkeySettingsTab().tabItem { Label("Hotkeys", systemImage: "keyboard") }
            SuggestionsSettingsTab().tabItem { Label("Suggestions", systemImage: "lightbulb") }
            AISettingsTab().tabItem { Label("AI", systemImage: "sparkles") }
            GeneralSettingsTab().tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 620, height: 560)
    }
}

struct ExpansionSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                Toggle("Expand abbreviations", isOn: Binding(
                    get: { settings.expansionEnabled },
                    set: { settings.expansionEnabled = $0
                        NotificationCenter.default.post(name: .expansionEnabledChanged, object: nil) }
                ))
                Picker("Expansion mode", selection: $settings.expansionMode) {
                    ForEach(ExpansionMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Default case sensitivity", selection: $settings.defaultCaseSensitivity) {
                    ForEach(CaseSensitivity.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Default expand when", selection: $settings.defaultTriggerContext) {
                    ForEach(TriggerContext.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("When expanding") {
                Picker("Insertion method", selection: $settings.insertionMethod) {
                    ForEach(InsertionMethod.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Restore clipboard after expansion", isOn: $settings.restoreClipboard)
                Toggle("Backspace restores the abbreviation", isOn: $settings.restoreAbbreviationOnDelete)
                Toggle("Run script snippets", isOn: $settings.runScriptSnippets)
                Toggle("Play sound on expansion", isOn: $settings.playSoundOnExpansion)
                if settings.playSoundOnExpansion {
                    Picker("Sound", selection: $settings.expansionSoundName) {
                        ForEach(["Pop", "Tink", "Glass", "Ping", "Submarine", "Morse"], id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            Section("Delimiters") {
                Text("Characters that trigger delimiter-mode expansion:")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Delimiters", text: $settings.delimiters)
                    .font(.system(.body, design: .monospaced))
            }
            Section("Excluded applications") {
                AppListEditor(bundleIDs: $settings.excludedBundleIDs)
                Text("Expansion is disabled in these apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct OptionsSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section("Automatic corrections") {
                Toggle("Capitalize new sentences", isOn: $settings.capitalizeNewSentences)
                Picker("Double capitals", selection: $settings.doubleCapitalCorrection) {
                    ForEach(DoubleCapitalCorrection.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Correction scope") {
                AppListEditor(bundleIDs: $settings.correctionExcludedBundleIDs)
                Text("Corrections are disabled in these apps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct SuggestionsSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    var body: some View {
        Form {
            Section {
                Toggle("Suggest snippets based on my typing habits", isOn: $settings.suggestionsEnabled)
                Toggle("Notify me about snippet suggestions", isOn: $settings.notifyOnSuggestion)
                    .disabled(!settings.suggestionsEnabled)
                Toggle("Notify me when I type a snippet's full content", isOn: $settings.notifyOnMissedExpansion)
            }
            Section {
                Text("Suggestions are computed entirely on this Mac. Nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AISettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var testResult: String?
    @State private var testing = false

    private static let modelSuggestions = [
        "anthropic/claude-sonnet-4.5",
        "anthropic/claude-opus-4.1",
        "openai/gpt-4o",
        "openai/gpt-4o-mini",
        "google/gemini-2.5-pro",
        "meta-llama/llama-3.3-70b-instruct",
    ]

    var body: some View {
        Form {
            Section("OpenRouter") {
                Toggle("Enable AI features", isOn: $settings.aiSuggestionsEnabled)
                SecureField("API Key (sk-or-…)", text: $settings.openRouterAPIKey)
                    .textFieldStyle(.roundedBorder)
                Picker("Model", selection: $settings.openRouterModel) {
                    ForEach(Self.modelSuggestions, id: \.self) { Text($0).tag($0) }
                    if !Self.modelSuggestions.contains(settings.openRouterModel) {
                        Text(settings.openRouterModel).tag(settings.openRouterModel)
                    }
                }
                TextField("Custom model ID", text: $settings.openRouterModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }
            Section {
                HStack {
                    Button {
                        runTest()
                    } label: {
                        if testing { ProgressView().controlSize(.small) } else { Text("Test Connection") }
                    }
                    .disabled(testing || settings.openRouterAPIKey.isEmpty)
                    if let testResult {
                        Text(testResult).font(.caption).foregroundStyle(testResult.hasPrefix("OK") ? .green : .red)
                    }
                }
            }
            Section("About AI features") {
                Text("""
                • The AI Assistant (in the snippet editor) drafts and refines snippet content.
                • The %ai:prompt% macro runs a live completion at expansion time. Use {clipboard} and {fill:Name} inside the prompt.
                Your API key is stored locally in this app's preferences and used only to call OpenRouter.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func runTest() {
        testing = true
        testResult = nil
        Task { @MainActor in
            let result = await OpenRouterClient.shared.test()
            testing = false
            switch result {
            case .success(let reply): testResult = "OK — \(reply)"
            case .failure(let error): testResult = error.localizedDescription
            }
        }
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @State private var accessibilityTrusted = AccessibilityHelper.isTrusted

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0; LoginItem.setEnabled($0) }
                ))
                Toggle("Show Dock icon", isOn: Binding(
                    get: { settings.showDockIcon },
                    set: { settings.showDockIcon = $0
                        NotificationCenter.default.post(name: .dockIconSettingChanged, object: nil) }
                ))
            }
            Section("Permissions") {
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Text(accessibilityTrusted ? "Accessibility access granted" : "Accessibility access required")
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Open Settings") { AccessibilityHelper.openSystemSettings() }
                    }
                }
                Text("StrukturExpander needs Accessibility access to watch typing and insert expansions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Statistics") {
                Stepper("Typing speed: \(settings.typingSpeedWPM) WPM", value: $settings.typingSpeedWPM, in: 20...150, step: 5)
            }
            Section("Data") {
                Button("Back Up Snippet Library Now") { SnippetStore.shared.backup() }
                Button("Reveal Library in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([SnippetStore.libraryURL])
                }
            }
            Section {
                Text("StrukturExpander \(AppInfo.version) — local TextExpander-style expander")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { accessibilityTrusted = AccessibilityHelper.isTrusted }
    }
}
