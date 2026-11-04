# qNOTES

[Français](README.fr.md)

## About

qNOTES is a personal Markdown notes app for macOS, inspired by Tot (The Iconfactory) and not affiliated with its authors. Written by Starbudweiser with Claude Code (Anthropic). MIT license, provided as is, without warranty.

## Features

- **Unlimited notes in Markdown**, shown with live formatting: headings, bold, italic, strikethrough, code, quotes, links, task lists.
- **Smart bullets**: Return continues a list, an empty bullet ends it, Tab and Shift-Tab indent, `[]` starts a task, a click on `[ ]` checks it. The bullet character is yours to choose.
- **Custom separators**: type `---` then Return to get the separator you picked (or your own).
- **Word and character counter**, for the whole note or the selection.
- **iCloud Drive sync**: notes live in `iCloud Drive/qNOTES`, one file per note, newest edit wins.
- **Automatic backups**, with restore (your current notes are backed up first).
- **Automatic updates** from GitHub releases (signature and notarization checked).
- Four languages (French, English, Spanish, Italian), picked from the system language.

## Build

```bash
swift test
./build_app.sh        # builds, signs and installs qNOTES.app
```

Data: `~/Library/Application Support/qNOTES/` (`QNOTES_DATA_DIR` to override, for tests).
