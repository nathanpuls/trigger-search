# Trigger Search

A lightweight personal autocomplete powered by a public Google Sheet. The same
snippet collection works across macOS with Hammerspoon and Windows with
AutoHotkey v2—without OAuth, sign-in, a browser extension, or a dedicated app.

## Choose your platform

- **macOS:** See [`mac/README.md`](mac/README.md) and install Hammerspoon.
- **Windows:** See [`windows/README.md`](windows/README.md) and install
  AutoHotkey v2.

Both versions read visible category tabs through Google Sheets' public CSV
endpoints, support labels, content, aliases, and nested choices, cache successful
responses for offline use, and link results back to their exact Sheet cells.
Every search covers every visible data tab; tab names remain useful for Sheet
organization and result context without creating separate search modes.

## Connect your Google Sheet

Publish your workbook with **File → Share → Publish to web** in Google Sheets.
The first time Trigger Search runs, paste the complete Sheet link into its setup
window and confirm. Trigger Search extracts the spreadsheet ID,
checks the public data, and saves the choice only on that computer—no code
editing is required.

Each computer has its own setting. A Mac can therefore use a personal Sheet
while a Windows work computer uses a different Sheet. Script updates do not
replace either choice.

## Repository layout

```text
mac/                  Hammerspoon implementation and examples
windows/              AutoHotkey v2 implementation and instructions
.github/workflows/    Windows syntax and runtime validation
autocomplete.ahk      Temporary compatibility bridge for older Windows installs
```

The root `autocomplete.ahk` remains temporarily so Windows versions installed
before the folder reorganization can update themselves. Current Windows code
lives at `windows/autocomplete.ahk`; version `0.5.0` and later update directly
from that path.

## Data and privacy

The configured workbook is public by design. Do not put passwords, patient
information, private work data, or other secrets in it. Use your own published
Google Sheet if the included workbook is only being used as an example.

## Project status

This is an intentionally small personal prototype. It favors understandable,
working behavior over application architecture or visual polish.
