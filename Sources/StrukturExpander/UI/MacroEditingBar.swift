import SwiftUI
import AppKit

/// The toolbar of macro-insertion buttons above the content editor,
/// mirroring TextExpander's editing bar (Date, Time, Fill-ins, Keys, …).
struct MacroEditingBar: View {
    @Binding var snippet: Snippet

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    macroButton("Year (2026)", "%Y")
                    macroButton("Year (26)", "%y")
                    macroButton("Month name (January)", "%B")
                    macroButton("Month (01)", "%m")
                    macroButton("Day (05)", "%d")
                    macroButton("Day (5)", "%e")
                    macroButton("Weekday (Monday)", "%A")
                    Divider()
                    macroButton("Full date (Jan 5, 2026)", "%B %e, %Y")
                    macroButton("ISO date (2026-01-05)", "%Y-%m-%d")
                    Divider()
                    macroButton("Date +7 days", "%@+7D%B %e, %Y")
                    macroButton("Custom format…", "%date:EEEE, MMMM d%")
                } label: {
                    Label("Date", systemImage: "calendar")
                }

                Menu {
                    macroButton("Time (14:30)", "%1H:%M")
                    macroButton("Time (2:30 PM)", "%1I:%M %p")
                    macroButton("Time with seconds", "%1H:%M:%S")
                } label: {
                    Label("Time", systemImage: "clock")
                }

                Menu {
                    macroButton("Single-line field", "%filltext:name=Field:default=%")
                    macroButton("Multi-line field", "%fillarea:name=Notes:default=%")
                    macroButton("Popup menu", "%fillpopup:name=Choice:default=Option 1:Option 2:Option 3%")
                    macroButton("Date picker", "%filldate:name=Date:format=MMMM d, yyyy%")
                    Divider()
                    macroButton("Optional section", "%fillpart:name=Section:default=yes%…%fillpartend%")
                    macroButton("Show fields on top", "%filltop%")
                } label: {
                    Label("Fill-in", systemImage: "rectangle.and.pencil.and.ellipsis")
                }

                Menu {
                    macroButton("Cursor position", "%|")
                    macroButton("Selection (start…end)", "%|selected%\\")
                    Divider()
                    macroButton("Return", "%key:return%")
                    macroButton("Tab", "%key:tab%")
                    macroButton("Escape", "%key:escape%")
                    Divider()
                    macroButton("Arrow up", "%^")
                    macroButton("Arrow down", "%v")
                    macroButton("Arrow left", "%<")
                    macroButton("Arrow right", "%>")
                } label: {
                    Label("Keys", systemImage: "keyboard")
                }

                Menu {
                    macroButton("Clipboard contents", "%clipboard")
                    macroButton("Embed snippet…", "%snippet:abbr%")
                    macroButton("Literal percent", "%%")
                    Divider()
                    macroButton("Keep delimiter", "%+")
                    macroButton("Abandon delimiter", "%-")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }

                Menu {
                    macroButton("AI: rewrite clipboard", "%ai:Rewrite the following professionally: {clipboard}%")
                    macroButton("AI: reply to clipboard", "%ai:Draft a concise reply to this message: {clipboard}%")
                    macroButton("AI: custom prompt…", "%ai:Your prompt here%")
                } label: {
                    Label("AI Macro", systemImage: "sparkles")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .disabled(snippet.contentType == .richText)
        .opacity(snippet.contentType == .richText ? 0.5 : 1)
        .help(snippet.contentType == .richText ? "Switch to Plain Text to insert macros as text" : "")
    }

    private func macroButton(_ title: String, _ macro: String) -> some View {
        Button(title) {
            insert(macro)
        }
    }

    private func insert(_ macro: String) {
        // Insert at the end (rich-text editing handled separately). For plain
        // text, append with a space if needed.
        if snippet.content.isEmpty || snippet.content.hasSuffix("\n") || snippet.content.hasSuffix(" ") {
            snippet.content += macro
        } else {
            snippet.content += macro
        }
    }
}
