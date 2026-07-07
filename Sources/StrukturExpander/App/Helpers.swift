import AppKit
import ApplicationServices

/// Draws the menu-bar status icon, dimmed when expansion is disabled.
enum StatusItemIcon {
    static func image(enabled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let color: NSColor = enabled ? .labelColor : .tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let text = "sx" as NSString
        let textSize = text.size(withAttributes: attrs)
        let point = NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
        text.draw(at: point, withAttributes: attrs)
        if !enabled {
            // Strike-through to indicate disabled state.
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 2, y: 3))
            path.line(to: NSPoint(x: size.width - 2, y: size.height - 3))
            color.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        image.unlockFocus()
        return image
    }
}

/// Accessibility-permission helpers.
enum AccessibilityHelper {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts the system permission dialog (adds the app to the list).
    @discardableResult
    static func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
