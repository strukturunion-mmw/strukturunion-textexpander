import Foundation
import AppKit
import JavaScriptCore

enum ScriptError: LocalizedError {
    case appleScriptFailed(String)
    case shellFailed(String)
    case javaScriptFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let msg): return msg
        case .shellFailed(let msg): return msg
        case .javaScriptFailed(let msg): return msg
        case .timeout: return "Script timed out"
        }
    }
}

enum ScriptRunner {

    /// Maximum wall-clock time a script snippet may take.
    static let timeoutSeconds: TimeInterval = 30

    // MARK: AppleScript

    /// Runs AppleScript on the main thread (NSAppleScript requirement) and
    /// returns the script's return value as a string.
    static func runAppleScript(_ source: String) async throws -> String {
        try await MainActor.run {
            var errorInfo: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw ScriptError.appleScriptFailed("Could not compile AppleScript")
            }
            let descriptor = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                throw ScriptError.appleScriptFailed(message)
            }
            return descriptor.stringValue ?? displayString(for: descriptor)
        }
    }

    private static func displayString(for descriptor: NSAppleEventDescriptor) -> String {
        if descriptor.numberOfItems > 0 {
            var parts: [String] = []
            for i in 1...descriptor.numberOfItems {
                if let item = descriptor.atIndex(i) {
                    parts.append(item.stringValue ?? "")
                }
            }
            return parts.joined(separator: ", ")
        }
        return ""
    }

    // MARK: Shell

    /// Writes the script (its first line must be a shebang) to a temp file,
    /// marks it executable and runs it. Returns stdout (UTF-8).
    static func runShellScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let dir = FileManager.default.temporaryDirectory
                    let url = dir.appendingPathComponent("strukturexpander-\(UUID().uuidString).sh")
                    try source.write(to: url, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                    defer { try? FileManager.default.removeItem(at: url) }

                    let process = Process()
                    process.executableURL = url
                    var env = ProcessInfo.processInfo.environment
                    env["LANG"] = (Locale.current.identifier.components(separatedBy: "@").first ?? "en_US") + ".UTF-8"
                    process.environment = env
                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr

                    try process.run()

                    // Enforce the timeout without blocking the pipe reads.
                    let deadline = DispatchTime.now() + timeoutSeconds
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning { process.terminate() }
                    }

                    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus != 0, outData.isEmpty {
                        let message = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
                        continuation.resume(throwing: ScriptError.shellFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
                        return
                    }
                    continuation.resume(returning: String(data: outData, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: JavaScript

    /// Runs JavaScript via JavaScriptCore. Mirrors TextExpander's JS API:
    /// the expansion is the value of the last statement, unless the script
    /// uses TextExpander.appendOutput()/ignoreOutput.
    static func runJavaScript(
        _ source: String,
        fillValues: [String: String],
        triggeringAbbreviation: String,
        baseDate: Date
    ) throws -> String {
        guard let context = JSContext() else {
            throw ScriptError.javaScriptFailed("Could not create JavaScript context")
        }

        var thrownError: String?
        context.exceptionHandler = { _, exception in
            thrownError = exception?.toString()
        }

        // The TextExpander global object.
        let te = JSValue(newObjectIn: context)!
        te.setObject(false, forKeyedSubscript: "ignoreOutput" as NSString)
        te.setObject("", forKeyedSubscript: "accumulatedOutput" as NSString)
        te.setObject(triggeringAbbreviation, forKeyedSubscript: "triggeringAbbreviation" as NSString)
        te.setObject(fillValues, forKeyedSubscript: "filledValues" as NSString)
        te.setObject("macOS", forKeyedSubscript: "platform" as NSString)
        te.setObject("StrukturExpander", forKeyedSubscript: "expansionContext" as NSString)
        te.setObject(baseDate, forKeyedSubscript: "baseDate" as NSString)
        te.setObject(baseDate, forKeyedSubscript: "adjustedDate" as NSString)
        te.setObject(NSPasteboard.general.string(forType: .string) ?? "", forKeyedSubscript: "pasteboardText" as NSString)

        let appendOutput: @convention(block) (String) -> Void = { str in
            let current = te.objectForKeyedSubscript("accumulatedOutput")?.toString() ?? ""
            te.setObject(current + str, forKeyedSubscript: "accumulatedOutput" as NSString)
        }
        te.setObject(appendOutput, forKeyedSubscript: "appendOutput" as NSString)
        context.setObject(te, forKeyedSubscript: "TextExpander" as NSString)

        let result = context.evaluateScript(source)

        if let thrownError {
            throw ScriptError.javaScriptFailed(thrownError)
        }
        if te.objectForKeyedSubscript("ignoreOutput")?.toBool() == true {
            return ""
        }
        let accumulated = te.objectForKeyedSubscript("accumulatedOutput")?.toString() ?? ""
        if !accumulated.isEmpty {
            return accumulated
        }
        guard let result, !result.isUndefined, !result.isNull else { return "" }
        return result.toString() ?? ""
    }
}
