import Foundation
import AppKit
import Carbon.HIToolbox

/// Posts synthetic keyboard events and pasteboard operations to deliver
/// expansions into the frontmost application.
///
/// All synthetic events carry a magic `eventSourceUserData` so the
/// KeystrokeMonitor's event tap can ignore them.
enum TextInjector {
    static let syntheticEventMagic: Int64 = 0x53545845 // "STXE" — tags our own synthetic events

    private static func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = syntheticEventMagic
        return source
    }

    // MARK: Key events

    static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        guard let source = makeSource(),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Deletes `count` characters before the insertion point by simulated Backspace presses.
    static func deleteBackward(count: Int, interKeyDelayMicroseconds: UInt32 = 1500) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(CGKeyCode(kVK_Delete))
            usleep(interKeyDelayMicroseconds)
        }
    }

    /// Types a plain-text string by posting unicode keyboard events.
    /// Newlines and tabs are sent as real Return/Tab key presses so that
    /// every application interprets them correctly.
    static func typeString(_ string: String, interChunkDelayMicroseconds: UInt32 = 2500) {
        guard let source = makeSource() else { return }
        var chunk: [UniChar] = []

        func flushChunk() {
            guard !chunk.isEmpty else { return }
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { return }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(interChunkDelayMicroseconds)
            chunk.removeAll(keepingCapacity: true)
        }

        for scalarChar in string {
            if scalarChar == "\n" || scalarChar == "\r" {
                flushChunk()
                postKey(CGKeyCode(kVK_Return))
                usleep(interChunkDelayMicroseconds)
            } else if scalarChar == "\t" {
                flushChunk()
                postKey(CGKeyCode(kVK_Tab))
                usleep(interChunkDelayMicroseconds)
            } else {
                chunk.append(contentsOf: Array(String(scalarChar).utf16))
                // keyboardSetUnicodeString supports a limited number of UTF-16 units per event.
                if chunk.count >= 16 { flushChunk() }
            }
        }
        flushChunk()
    }

    // MARK: Pasteboard insertion

    private static func snapshotPasteboard() -> [[String: Data]] {
        let pb = NSPasteboard.general
        var snapshot: [[String: Data]] = []
        for item in pb.pasteboardItems ?? [] {
            var entry: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    entry[type.rawValue] = data
                }
            }
            snapshot.append(entry)
        }
        return snapshot
    }

    private static func restorePasteboard(_ snapshot: [[String: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }

    /// Pastes a plain string via the pasteboard and Cmd-V, optionally restoring
    /// the previous pasteboard contents afterwards.
    static func paste(plainText: String, restoreClipboard: Bool, completion: (() -> Void)? = nil) {
        paste(restoreClipboard: restoreClipboard, completion: completion) { pb in
            pb.setString(plainText, forType: .string)
        }
    }

    /// Pastes rich text (RTFD data) via the pasteboard and Cmd-V.
    static func paste(rtfdData: Data, plainFallback: String, restoreClipboard: Bool, completion: (() -> Void)? = nil) {
        paste(restoreClipboard: restoreClipboard, completion: completion) { pb in
            if let attributed = try? NSAttributedString(
                data: rtfdData,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            ) {
                let range = NSRange(location: 0, length: attributed.length)
                if let rtfd = attributed.rtfd(from: range, documentAttributes: [:]) {
                    pb.setData(rtfd, forType: .rtfd)
                }
                if let rtf = attributed.rtf(from: range, documentAttributes: [:]) {
                    pb.setData(rtf, forType: .rtf)
                }
            }
            pb.setString(plainFallback, forType: .string)
        }
    }

    private static func paste(restoreClipboard: Bool, completion: (() -> Void)?, write: (NSPasteboard) -> Void) {
        let snapshot = restoreClipboard ? snapshotPasteboard() : []
        let pb = NSPasteboard.general
        pb.clearContents()
        write(pb)

        // Small delay lets the pasteboard settle before the target app reads it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            postKey(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
            if restoreClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    restorePasteboard(snapshot)
                    completion?()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    completion?()
                }
            }
        }
    }

    /// Moves the insertion point left by `count` characters (for the %| cursor macro).
    static func moveCursorLeft(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(CGKeyCode(kVK_LeftArrow))
            usleep(1500)
        }
    }
}
