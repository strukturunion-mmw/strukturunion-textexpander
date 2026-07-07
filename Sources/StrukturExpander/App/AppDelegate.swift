import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private let store = SnippetStore.shared
    private let monitor = KeystrokeMonitor.shared

    private var statusItem: NSStatusItem?
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var statisticsWindowController: NSWindowController?
    private var inlineSearchController: InlineSearchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
        setupStatusItem()
        setupMainMenu()
        wireMonitorHotkeys()

        // Periodic backup on launch.
        store.backup()

        // Start monitoring if we already have accessibility permission,
        // otherwise open onboarding.
        if AXIsProcessTrusted() {
            monitor.start()
        } else {
            showMainWindow()
            OnboardingWindow.presentIfNeeded()
        }

        // Observe settings that affect app-level behaviour.
        NotificationCenter.default.addObserver(
            self, selector: #selector(dockIconSettingChanged),
            name: .dockIconSettingChanged, object: nil
        )
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        monitor.stop()
    }

    // MARK: Activation policy (Dock icon)

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }

    @objc private func dockIconSettingChanged() {
        applyActivationPolicy()
        if settings.showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: Status (menu bar) item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = StatusItemIcon.image(enabled: settings.expansionEnabled)
            button.image?.isTemplate = true
        }
        item.menu = buildStatusMenu()
        statusItem = item

        // Keep the icon in sync with the enabled flag.
        NotificationCenter.default.addObserver(
            forName: .expansionEnabledChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatusItem()
            }
        }
    }

    func refreshStatusItem() {
        statusItem?.button?.image = StatusItemIcon.image(enabled: settings.expansionEnabled)
        statusItem?.button?.image?.isTemplate = true
        statusItem?.menu = buildStatusMenu()
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: settings.expansionEnabled ? "Disable Expansion" : "Enable Expansion",
            action: #selector(toggleExpansion), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        if monitor.secureInputActive {
            let warn = NSMenuItem(title: "⚠︎ Secure Input active — expansion paused", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(title: "⚠︎ Accessibility permission needed", action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open StrukturExpander", action: #selector(showMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let newSnippet = NSMenuItem(title: "New Snippet…", action: #selector(newSnippet), keyEquivalent: "n")
        newSnippet.target = self
        menu.addItem(newSnippet)

        let fromClipboard = NSMenuItem(title: "New Snippet from Clipboard", action: #selector(newSnippetFromClipboard), keyEquivalent: "")
        fromClipboard.target = self
        menu.addItem(fromClipboard)

        let search = NSMenuItem(title: "Inline Search…", action: #selector(showInlineSearch), keyEquivalent: "")
        search.target = self
        menu.addItem(search)

        menu.addItem(.separator())

        // Quick actions: the most-used snippets.
        let topSnippets = store.allSnippets
            .filter { !$0.abbreviation.isEmpty }
            .sorted { $0.useCount > $1.useCount }
            .prefix(9)
        if !topSnippets.isEmpty {
            let header = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for (index, snippet) in topSnippets.enumerated() {
                let mi = NSMenuItem(
                    title: "  \(snippet.displayLabel)",
                    action: #selector(quickInsert(_:)),
                    keyEquivalent: "\(index + 1)"
                )
                mi.keyEquivalentModifierMask = .command
                mi.target = self
                mi.representedObject = snippet.id.uuidString
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        let stats = NSMenuItem(title: "Statistics…", action: #selector(showStatistics), keyEquivalent: "")
        stats.target = self
        menu.addItem(stats)

        let prefs = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit StrukturExpander", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    // MARK: Main menu (menu bar for the app when active)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About StrukturExpander", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let prefItem = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        prefItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide StrukturExpander", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit StrukturExpander", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let newItem = fileMenu.addItem(withTitle: "New Snippet", action: #selector(newSnippet), keyEquivalent: "n")
        newItem.target = self
        let newGroup = fileMenu.addItem(withTitle: "New Group", action: #selector(newGroup), keyEquivalent: "N")
        newGroup.target = self
        fileMenu.addItem(.separator())
        let importItem = fileMenu.addItem(withTitle: "Import…", action: #selector(importSnippets), keyEquivalent: "i")
        importItem.target = self
        let exportItem = fileMenu.addItem(withTitle: "Export…", action: #selector(exportSnippets), keyEquivalent: "e")
        exportItem.target = self
        fileMenu.addItem(.separator())
        let printItem = fileMenu.addItem(withTitle: "Print…", action: #selector(printSnippets), keyEquivalent: "p")
        printItem.target = self
        fileItem.submenu = fileMenu

        // Edit menu (standard editing shortcuts)
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // Window menu
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Main Window", action: #selector(showMainWindow), keyEquivalent: "0")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func wireMonitorHotkeys() {
        monitor.onSearchHotkey = { [weak self] in
            MainActor.assumeIsolated { self?.showInlineSearch() }
        }
        monitor.onCreateFromClipboardHotkey = { [weak self] in
            MainActor.assumeIsolated { self?.newSnippetFromClipboard() }
        }
        monitor.onCreateFromSelectionHotkey = { [weak self] in
            MainActor.assumeIsolated { self?.newSnippetFromSelection() }
        }
    }

    // MARK: Actions

    @objc func toggleExpansion() {
        settings.expansionEnabled.toggle()
        NotificationCenter.default.post(name: .expansionEnabledChanged, object: nil)
    }

    @objc func showMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func newSnippet() {
        showMainWindow()
        mainWindowController?.createNewSnippet()
    }

    @objc func newGroup() {
        showMainWindow()
        mainWindowController?.createNewGroup()
    }

    @objc func newSnippetFromClipboard() {
        let clip = NSPasteboard.general.string(forType: .string) ?? ""
        showMainWindow()
        mainWindowController?.createNewSnippet(content: clip)
    }

    @objc func newSnippetFromSelection() {
        // Copy the current selection, then create a snippet from it.
        let previousChangeCount = NSPasteboard.general.changeCount
        TextInjector.postKey(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            let pb = NSPasteboard.general
            let content = pb.changeCount != previousChangeCount ? (pb.string(forType: .string) ?? "") : ""
            self?.showMainWindow()
            self?.mainWindowController?.createNewSnippet(content: content)
        }
    }

    @objc func quickInsert(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let snippet = store.snippet(withID: id) else { return }
        let group = store.groupContaining(snippetID: id)
        // Give focus back to the previous app before inserting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            ExpansionEngine.shared.insertSnippet(snippet, group: group)
        }
    }

    @objc func showInlineSearch() {
        if inlineSearchController == nil {
            inlineSearchController = InlineSearchController()
        }
        inlineSearchController?.present()
    }

    @objc func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showStatistics() {
        if statisticsWindowController == nil {
            let hosting = NSHostingController(rootView: StatisticsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Statistics"
            window.setContentSize(NSSize(width: 640, height: 520))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            statisticsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        statisticsWindowController?.showWindow(nil)
        statisticsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "StrukturExpander",
            .applicationVersion: AppInfo.version,
        ])
    }

    @objc func openAccessibility() {
        AccessibilityHelper.openSystemSettings()
    }

    @objc func importSnippets() {
        showMainWindow()
        mainWindowController?.importSnippets()
    }

    @objc func exportSnippets() {
        showMainWindow()
        mainWindowController?.exportSnippets()
    }

    @objc func printSnippets() {
        showMainWindow()
        mainWindowController?.printSnippets()
    }
}

enum AppInfo {
    static let version = "1.0.0"
}

extension Notification.Name {
    static let expansionEnabledChanged = Notification.Name("expansionEnabledChanged")
    static let dockIconSettingChanged = Notification.Name("dockIconSettingChanged")
    static let libraryChanged = Notification.Name("libraryChanged")
}
