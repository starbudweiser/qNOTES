# qNOTES

[Français](README.fr.md)

## About

qNOTES is a personal rich-text notes app for macOS, inspired by Tot (The Iconfactory) and not affiliated with its authors. Written by Starbudweiser with Claude Code (Anthropic). MIT license, provided as is, without warranty.

## Features

- **Unlimited rich-text notes**: headings, bold, italic, underline, strikethrough, colors, alignment, bulleted / numbered / task lists, links. Notes are stored as RTF with a plain-text mirror.
- **Import from Tot**: File > Import Notes… reads Tot's latest backup (Tot is not modified) or any `.json`, `.md`, `.txt` file; dates are kept, nothing is duplicated.
- **Window options**: monospaced font, text size slider, translucent background and stay-on-top (Settings).
- **Font picker**: Settings > Writing lets you choose the font (any installed family, previewed in itself) and the text size for all notes.
- **Classic formatting tools**: a toolbar, a Format menu with the usual shortcuts (⌘B, ⌘I, ⌘U, ⌘K…) and a floating mini toolbar over the selected text; the buttons light up for the style under the cursor. Old Markdown notes are converted when opened.
- **Free note order**: drag notes in the list to arrange them as you like (dropping onto a pinned note pins it); new notes arrive first, editing never moves a note. The quick panel shows one color dot per note in that same order.
- **Smart bullets**: Return continues a list, an empty bullet ends it, Tab and Shift-Tab indent, `[]` starts a task, a click on its box checks it. The bullet character is yours to choose.
- **Custom separators**: type `---` then Return to get the separator you picked (or your own).
- **Word and character counter**, for the whole note or the selection.
- **iCloud Drive sync**: notes live in `iCloud Drive/qNOTES`, one file per note, newest edit wins.
- **Automatic backups**, with restore (your current notes are backed up first).
- **Menu bar panel**: an icon in the menu bar opens a quick notes panel (colored dots for your latest notes, editor, counters); global shortcut ⌃⌥N; Dock, menu bar or both in Settings.
- **Widget** (small, medium, large): your pinned or latest notes on the desktop; a click opens the note.
- **Automatic updates** from GitHub releases (signature and notarization checked).
- Four languages (French, English, Spanish, Italian), picked from the system language.

## Build

```bash
swift test
./build_app.sh        # builds, signs and installs qNOTES.app
```

Data: `~/Library/Application Support/qNOTES/` (`QNOTES_DATA_DIR` to override, for tests).
