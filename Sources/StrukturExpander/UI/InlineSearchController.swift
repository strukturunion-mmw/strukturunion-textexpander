import AppKit
import SwiftUI
import Carbon.HIToolbox

/// A floating quick-search panel (TextExpander's Inline Search): type to filter
/// snippets, Return inserts the selected one into the previously focused app.
@MainActor
final class InlineSearchController {
    private var window: NSPanel?
    private var previousApp: NSRunningApplication?

    func present() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            let view = InlineSearchView(
                onInsert: { [weak self] snippet in self?.insert(snippet) },
                onClose: { [weak self] in self?.close() }
            )
            panel.contentView = NSHostingView(rootView: view)
            window = panel
        }

        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func insert(_ snippet: Snippet) {
        let group = SnippetStore.shared.groupContaining(snippetID: snippet.id)
        close()
        previousApp?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            ExpansionEngine.shared.insertSnippet(snippet, group: group)
        }
    }

    private func close() {
        window?.orderOut(nil)
    }
}

struct InlineSearchView: View {
    let onInsert: (Snippet) -> Void
    let onClose: () -> Void

    @ObservedObject private var store = SnippetStore.shared
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private var results: [Snippet] {
        let all = store.allSnippets.filter { !$0.abbreviation.isEmpty || !$0.label.isEmpty }
        guard !query.isEmpty else {
            return Array(all.sorted { $0.useCount > $1.useCount }.prefix(20))
        }
        let needle = query.lowercased()
        return all.filter {
            $0.abbreviation.lowercased().contains(needle)
                || $0.label.lowercased().contains(needle)
                || $0.content.lowercased().contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search snippets…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit(insertSelected)
                    .onChange(of: query) { _ in selectedIndex = 0 }
            }
            .padding(12)
            Divider()

            ScrollViewReader { proxy in
                List(Array(results.enumerated()), id: \.element.id) { index, snippet in
                    InlineResultRow(snippet: snippet, isSelected: index == selectedIndex)
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture { onInsert(snippet) }
                        .listRowBackground(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                }
                .onChange(of: selectedIndex) { idx in
                    withAnimation { proxy.scrollTo(idx) }
                }
            }
        }
        .frame(width: 460, height: 320)
        .onAppear { searchFocused = true }
        .background(KeyCaptureView(
            onUp: { move(-1) },
            onDown: { move(1) },
            onEscape: onClose,
            onReturn: insertSelected
        ))
    }

    private func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func insertSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onInsert(results[selectedIndex])
    }
}

struct InlineResultRow: View {
    let snippet: Snippet
    let isSelected: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(snippet.displayLabel).lineLimit(1)
                if !snippet.abbreviation.isEmpty {
                    Text(snippet.abbreviation)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// Captures arrow / escape / return keys for the inline search list.
struct KeyCaptureView: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEscape: () -> Void
    let onReturn: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onUp = onUp
        view.onDown = onDown
        view.onEscape = onEscape
        view.onReturn = onReturn
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onEscape: (() -> Void)?
        var onReturn: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            switch Int(event.keyCode) {
            case kVK_UpArrow: onUp?()
            case kVK_DownArrow: onDown?()
            case kVK_Escape: onEscape?()
            case kVK_Return, kVK_ANSI_KeypadEnter: onReturn?()
            default: super.keyDown(with: event)
            }
        }
    }
}
