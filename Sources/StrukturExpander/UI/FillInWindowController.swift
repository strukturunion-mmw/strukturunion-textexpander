import AppKit
import SwiftUI

/// Presents the fill-in window at expansion time and returns the collected
/// values (or nil if the user cancelled).
@MainActor
enum FillInWindowController {

    static func present(
        fields: [FillField],
        snippetLabel: String,
        previousApp: NSRunningApplication?
    ) async -> [String: String]? {
        await withCheckedContinuation { continuation in
            let panel = FillInPanel(fields: fields, snippetLabel: snippetLabel) { values in
                continuation.resume(returning: values)
            }
            panel.show()
        }
    }
}

@MainActor
final class FillInPanel: NSObject {
    private let fields: [FillField]
    private let snippetLabel: String
    private let completion: ([String: String]?) -> Void
    private var window: NSWindow?
    private var didComplete = false

    init(fields: [FillField], snippetLabel: String, completion: @escaping ([String: String]?) -> Void) {
        self.fields = fields
        self.snippetLabel = snippetLabel
        self.completion = completion
    }

    func show() {
        let view = FillInFormView(
            fields: fields,
            snippetLabel: snippetLabel,
            onSubmit: { [weak self] values in self?.finish(values) },
            onCancel: { [weak self] in self?.finish(nil) }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = snippetLabel
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(_ values: [String: String]?) {
        guard !didComplete else { return }
        didComplete = true
        window?.close()
        window = nil
        completion(values)
    }
}

struct FillInFormView: View {
    let fields: [FillField]
    let snippetLabel: String
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var values: [String: String] = [:]
    @State private var dateValues: [String: Date] = [:]
    @State private var boolValues: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snippetLabel)
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(fields) { field in
                        fieldView(field)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Insert") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear(perform: seedDefaults)
    }

    @ViewBuilder
    private func fieldView(_ field: FillField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !field.name.isEmpty, !isOptional(field) {
                Text(field.name).font(.subheadline.bold())
            }
            switch field.kind {
            case .text(let width):
                TextField(field.name.isEmpty ? "Value" : field.name, text: binding(for: field.name, default: field.defaultValue))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: CGFloat(width) * 8 + 40)
            case .area(_, let height):
                TextEditor(text: binding(for: field.name, default: field.defaultValue))
                    .frame(height: CGFloat(height) * 18)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            case .popup(let options, _):
                Picker(field.name, selection: binding(for: field.name, default: field.defaultValue)) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            case .date(let format):
                DatePicker(
                    field.name,
                    selection: dateBinding(for: field.name),
                    displayedComponents: format.contains("H") || format.contains("h") ? [.date, .hourAndMinute] : [.date]
                )
                .labelsHidden()
                .datePickerStyle(.field)
            case .optionalPart(let defaultOn):
                Toggle(field.name.isEmpty ? "Include section" : field.name, isOn: boolBinding(for: field.name, default: defaultOn))
            }
        }
    }

    private func isOptional(_ field: FillField) -> Bool {
        if case .optionalPart = field.kind { return true }
        return false
    }

    private func seedDefaults() {
        for field in fields {
            switch field.kind {
            case .optionalPart(let on):
                boolValues[field.name] = on
            case .date:
                dateValues[field.name] = Date()
            default:
                if values[field.name] == nil { values[field.name] = field.defaultValue }
            }
        }
    }

    private func binding(for name: String, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { values[name] ?? defaultValue },
            set: { values[name] = $0 }
        )
    }

    private func dateBinding(for name: String) -> Binding<Date> {
        Binding(
            get: { dateValues[name] ?? Date() },
            set: { dateValues[name] = $0 }
        )
    }

    private func boolBinding(for name: String, default defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { boolValues[name] ?? defaultValue },
            set: { boolValues[name] = $0 }
        )
    }

    private func submit() {
        var result = values
        for (name, date) in dateValues {
            result[name] = String(date.timeIntervalSince1970)
        }
        for (name, on) in boolValues {
            result[name] = on ? "yes" : "no"
        }
        onSubmit(result)
    }
}
