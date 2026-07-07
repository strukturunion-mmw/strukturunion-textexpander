import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeySettingsTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Global Hotkeys") {
                HotkeyField(label: "Inline Search", spec: $settings.searchHotkey)
                HotkeyField(label: "New Snippet from Clipboard", spec: $settings.createFromClipboardHotkey)
                HotkeyField(label: "New Snippet from Selection", spec: $settings.createFromSelectionHotkey)
                HotkeyField(label: "Enable / Disable Expansion", spec: $settings.toggleExpansionHotkey)
            }
            Section {
                Text("Click a field and press the desired key combination. Press Delete to clear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct HotkeyField: View {
    let label: String
    @Binding var spec: HotkeySpec

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HotkeyRecorderView(spec: $spec)
                .frame(width: 160, height: 24)
        }
    }
}

/// A control that records a key combination.
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var spec: HotkeySpec

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = { spec = $0 }
        button.spec = spec
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.spec = spec
        nsView.refreshTitle()
    }

    final class RecorderButton: NSButton {
        var spec = HotkeySpec.disabled
        var onChange: ((HotkeySpec) -> Void)?
        private var recording = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
            refreshTitle()
        }
        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }

        func refreshTitle() {
            title = recording ? "Type shortcut…" : spec.displayString
        }

        @objc private func startRecording() {
            recording = true
            refreshTitle()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == UInt32(kVK_Delete) {
                spec = .disabled
            } else {
                let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                spec = HotkeySpec(keyCode: UInt32(event.keyCode), modifiers: mods)
            }
            recording = false
            onChange?(spec)
            refreshTitle()
            window?.makeFirstResponder(nil)
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            refreshTitle()
            return super.resignFirstResponder()
        }
    }
}
