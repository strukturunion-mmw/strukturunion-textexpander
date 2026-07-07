import AppKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var controller: NSWindowController?

    static func presentIfNeeded() {
        guard !AccessibilityHelper.isTrusted else { return }
        present()
    }

    static func present() {
        let hosting = NSHostingController(rootView: OnboardingView {
            controller?.close()
            controller = nil
        })
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to StrukturExpander"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 420))
        window.center()
        let wc = NSWindowController(window: window)
        controller = wc
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
    }
}

struct OnboardingView: View {
    let onDone: () -> Void
    @State private var trusted = AccessibilityHelper.isTrusted
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to StrukturExpander")
                .font(.title.bold())
            Text("A local, fully-featured text expander for your Mac.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Label("Grant Accessibility access so StrukturExpander can watch your typing and insert expansions.", systemImage: "1.circle.fill")
                Label("Nothing you type is stored or sent anywhere — matching happens on-device.", systemImage: "lock.shield")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack {
                Image(systemName: trusted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(trusted ? .green : .secondary)
                Text(trusted ? "Accessibility access granted" : "Waiting for Accessibility access…")
            }

            HStack {
                if !trusted {
                    Button("Open System Settings") {
                        AccessibilityHelper.requestPermission()
                        AccessibilityHelper.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(trusted ? "Get Started" : "Continue Anyway") {
                    if trusted { KeystrokeMonitor.shared.start() }
                    onDone()
                }
            }
        }
        .padding(28)
        .frame(width: 480, height: 420)
        .onAppear {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    let nowTrusted = AccessibilityHelper.isTrusted
                    if nowTrusted && !trusted {
                        trusted = true
                        KeystrokeMonitor.shared.start()
                    }
                }
            }
        }
        .onDisappear { pollTimer?.invalidate() }
    }
}
