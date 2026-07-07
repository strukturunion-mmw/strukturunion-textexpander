import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let appState = AppState()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "StrukturExpander"
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.minSize = NSSize(width: 820, height: 480)
        self.init(window: window)

        let root = MainContentView()
            .environmentObject(appState)
            .environmentObject(SnippetStore.shared)
            .environmentObject(AppSettings.shared)
        window.contentView = NSHostingView(rootView: root)
        window.delegate = self
    }

    // MARK: Actions invoked from the app delegate / menus

    func createNewSnippet(content: String = "") {
        let groupID = appState.selectedGroupID ?? SnippetStore.shared.groups.first?.id
        guard let groupID else {
            createNewGroup()
            return
        }
        var snippet = Snippet()
        snippet.content = content
        SnippetStore.shared.addSnippet(snippet, to: groupID)
        appState.selectedGroupID = groupID
        appState.selectedSnippetID = snippet.id
        appState.objectWillChange.send()
    }

    func createNewGroup() {
        var group = SnippetGroup(name: "Untitled Group")
        SnippetStore.shared.addGroup(group)
        appState.selectedGroupID = group.id
        appState.objectWillChange.send()
    }

    // MARK: Import / Export

    func importSnippets() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "textexpander") ?? .xml,
            .commaSeparatedText,
            .json,
            UTType(filenameExtension: "plist") ?? .propertyList,
            .plainText,
        ]
        panel.message = "Import snippets from a .textexpander, CSV, or JSON file"
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                do {
                    let imported = try SnippetIO.importFile(at: url)
                    for group in imported {
                        SnippetStore.shared.addGroup(group)
                    }
                } catch {
                    self.presentError(error, title: "Import Failed")
                }
            }
            self.appState.objectWillChange.send()
        }
    }

    func exportSnippets() {
        guard let group = appState.selectedGroup else {
            presentInfo(title: "No Group Selected", message: "Select a group in the sidebar to export.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "textexpander") ?? .xml, .json, .commaSeparatedText]
        panel.nameFieldStringValue = group.name
        panel.message = "Export the selected group"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try SnippetIO.exportGroup(group, to: url)
            } catch {
                self.presentError(error, title: "Export Failed")
            }
        }
    }

    func printSnippets() {
        let group = appState.selectedGroup
        let text = SnippetIO.printableText(for: group, store: SnippetStore.shared)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 720))
        textView.string = text
        textView.font = NSFont.userFixedPitchFont(ofSize: 11)
        let printInfo = NSPrintInfo.shared
        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.runModal(for: window ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Alerts

    private func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
