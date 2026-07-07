# StrukturExpander

A local, fully-featured text expander for macOS — a native reimplementation of
the core [TextExpander](https://textexpander.com/) feature set, built for
internal use. **No account, no cloud, no subscription.** Everything runs and
stays on your Mac.

Apple Silicon and Intel are both supported (the build produces a universal
binary). Requires **macOS 13 (Ventura) or later**.

---

## Features

### Expansion engine
- **System-wide abbreviation expansion** in any app, via an Accessibility event tap.
- **Expansion modes**: immediately when typed, or at a delimiter (keeping or
  abandoning the delimiter). Configurable delimiter set.
- **Case handling** per snippet or group: case-sensitive, ignore case, or
  *adapt to the case of the abbreviation* (`sig` → normal, `Sig` → Capitalized,
  `SIG` → ALL CAPS).
- **Expand-when** control per group: after whitespace only, after any
  non-alphanumeric, or anywhere (even mid-word).
- **Insertion** via pasteboard paste (fast, keeps formatting/images) or
  simulated keystrokes (for apps that block paste). Clipboard is restored
  afterwards.
- **Backspace-to-undo** an expansion restores the original abbreviation.
- Optional **expansion sound** and per-app exclusions.

### Snippet content types
- **Plain text**
- **Rich text** (formatted text and inline images, stored as RTFD)
- **AppleScript**, **Shell script** (with shebang), and **JavaScript**
  (with the `TextExpander` JS API: `appendOutput`, `ignoreOutput`,
  `filledValues`, `pasteboardText`, `triggeringAbbreviation`, …).

### Macros (TextExpander-compatible syntax)
- Date/time codes: `%Y %y %B %b %m %1m %A %a %d %e %H %1H %I %1I %M %S %p`
- Custom date format: `%date:EEEE, MMMM d%`
- Date math: `%@+7D`, `%@-2M` (units `Y M D h m s`), affecting following date codes
- `%clipboard`, cursor `%|`, selection `%|…%\`, literal `%%`
- Embedded snippets: `%snippet:abbr%`
- Keys: `%key:tab%`, `%key:return%`, `%key:escape%`; arrows `%> %< %^ %v`
- Delimiter override: `%+` (keep) / `%-` (abandon)
- **Fill-ins**: `%filltext%`, `%fillarea%`, `%fillpopup%`, `%filldate%`,
  optional sections `%fillpart%…%fillpartend%`, `%filltop%`. Same-named fields
  are synchronized; fields from embedded snippets are aggregated.

### AI (via OpenRouter)
- **AI Assistant** in the snippet editor: draft new snippet content from a
  description, refine existing content, or suggest an abbreviation.
- **`%ai:prompt%` macro**: runs a live LLM completion at expansion time.
  Use `{clipboard}` and `{fill:Name}` placeholders inside the prompt, e.g.
  `%ai:Draft a concise reply to this message: {clipboard}%`.
- Bring your own **OpenRouter API key** and choose any model
  (Claude, GPT, Gemini, Llama, …). Configure in **Settings → AI**.

### Organization & UI
- Groups with per-group settings: prefix, case sensitivity, expand-when,
  and app scoping (all / only-in / except-in specific apps).
- Three-column editor, live **abbreviation conflict detection**.
- **Inline Search** floating panel (default ⌘/) to find and insert snippets.
- Menu-bar item with **Quick Actions** (most-used snippets, ⌘1–9),
  enable/disable, and Secure-Input warnings.
- **Statistics**: expansions, characters saved, estimated time saved, per-day
  chart, most-used snippets.
- **Auto-corrections**: capitalize new sentences, fix double capitals.
- **Local snippet suggestions** from your typing habits (fully on-device).
- **Import/Export**: TextExpander `.textexpander` plist, CSV, and native JSON.
- Automatic timestamped **backups** of your library.

Snippets are stored at
`~/Library/Application Support/StrukturExpander/library.json`.

---

## Build & install

You need **Xcode command-line tools** (`xcode-select --install`). Xcode itself
is not required.

```bash
git clone <this repo>
cd strukturunion-textexpander
./scripts/build.sh
```

This produces `build/StrukturExpander.app` — a universal, ad-hoc–signed bundle.

Then:

1. Copy `StrukturExpander.app` into `/Applications`.
2. Launch it. On first launch it asks for **Accessibility** permission —
   grant it in **System Settings → Privacy & Security → Accessibility**
   (required to watch typing and insert text).
3. Start creating snippets. Toggle expansion from the menu-bar icon.

### Installing on a colleague's Mac

The app is **ad-hoc signed**, so Gatekeeper will warn that it is from an
unidentified developer. After copying it over, clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/StrukturExpander.app"
```

Then launch it (or right-click → Open the first time). Grant Accessibility
permission on that Mac as well.

> If you have an Apple Developer ID, set `SIGN_IDENTITY="Developer ID Application: …"`
> before running `build.sh` to produce a properly signed build that installs
> without the quarantine step.

### Optional app icon

Drop a 1024×1024 PNG at `Resources/icon-1024.png` and run
`./scripts/make-icon.sh` before building to embed a custom icon.

---

## Notes

- This is an independent, clean-room reimplementation for personal/internal use.
  It is not affiliated with or derived from TextExpander or Smile Software, and
  ships none of their assets. The `%…%` macro syntax is reproduced for
  familiarity and import compatibility.
- Cloud sync, team sharing, and mobile sync are intentionally **not** included.
