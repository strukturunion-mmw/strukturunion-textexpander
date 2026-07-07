import AppKit

/// Enumerates installed applications for the app-scoping pickers.
enum AppCatalog {
    struct AppEntry: Identifiable {
        var bundleID: String
        var name: String
        var icon: NSImage
        var id: String { bundleID }
    }

    static func installedApps() -> [AppEntry] {
        var seen = Set<String>()
        var entries: [AppEntry] = []
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let fm = FileManager.default
        for dir in dirs {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(item)
                guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                let name = (item as NSString).deletingPathExtension
                entries.append(AppEntry(bundleID: id, name: name, icon: NSWorkspace.shared.icon(forFile: path)))
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func name(forBundleID id: String) -> String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path {
            return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        return id
    }

    static func icon(forBundleID id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}
