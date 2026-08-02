# Trigger Search

A lightweight personal autocomplete powered by a public Google Sheet. The same
snippet collection works across macOS with Hammerspoon and Windows with
AutoHotkey v2—without OAuth, sign-in, a browser extension, or a dedicated app.

## Choose your platform

- **macOS:** See [`mac/README.md`](mac/README.md) and install Hammerspoon.
- **Windows:** See [`windows/README.md`](windows/README.md) and install
  AutoHotkey v2.
- **Web/mobile:** See [`web/README.md`](web/README.md) for the responsive,
  installable copy/open companion, or open
  [trigger-search.pages.dev](https://trigger-search.pages.dev/).

Both versions read visible category tabs through Google Sheets' public CSV
endpoints, support full headered tabs or simple one/two-column headerless tabs,
cache successful responses for offline use, and link results back to their
exact Sheet cells. Headered tabs additionally support aliases and nested choices.
Every search covers every visible data tab; tab names remain useful for Sheet
organization and result context without creating separate search modes.
When the search is empty, both versions show up to nine recently used Sheet
items, with direct Command-1–9 or Control-1–9 selection.

### Search & AI launchers

Add a tab named `Search & AI` with two columns:

| Service | URL Template |
|---|---|
| Google | `https://www.google.com/search?q={query}` |
| PubMed | `https://pubmed.ncbi.nlm.nih.gov/?term={query}` |
| ChatGPT | `https://chatgpt.com/?q={query}` |

Each valid row becomes a normal searchable parent item. Select a service and
press Right Arrow (or click/tap it on the web) to enter a query, then press
Return/Enter to open the encoded query in the default browser. Left Arrow
returns to the same service in the main results. The older header `URL` is also
accepted, but `URL Template` is clearer for new Sheets.

Templates must contain the exact placeholder `{query}` and begin with
`https://` or `http://`. Incomplete or invalid rows are ignored. This keeps the
feature generic: add search engines, AI services, documentation sites, or an
internal HTTP search tool without changing Trigger Search's code.

Both versions also expand the same small
[Raycast-style dynamic-placeholder subset](https://manual.raycast.com/dynamic-placeholders)
at paste time: dates and times with formats or relative offsets,
`{clipboard}`, and `{cursor}`. See the platform guides for the exact supported
syntax. Trigger Search does not execute scripts or arbitrary code stored in the
public Sheet.

The search field also doubles as a small calculator. Enter a duration such as
`4W` or `6M` to see the future date, or a complete arithmetic expression such
as `90 / 3`. The equals sign is optional. These calculated results appear above
ordinary Sheet matches and can be read without selecting them.

Return/Enter always pastes. Right Arrow opens a result whose entire content is
one recognizable web link. Command-O on Mac or Control-O on Windows explicitly
opens a single link found within a larger snippet. Command-C on Mac or Control-C
on Windows copies the selected text without pasting it. Command-P on Mac or
Control-P on Windows opens the full expanded text in a readable, selectable
preview; Escape returns to the same result. Command-K or Control-K opens a
contextual action menu for the selected result.

Command-G on Mac or Control-G on Windows searches Google for the literal text
currently typed into Trigger Search, even when it does not match a Sheet item.
The search opens in the system's default browser.

Holding Command on Mac or Control on Windows for about 300 ms reveals a compact
contextual shortcut HUD. Continue holding the modifier and press Return/Enter
for AI, C to copy, E to edit, G to search Google, O to open, or P to preview.
Google remains available for arbitrary typed text; the other HUD actions depend
on the selected result. The HUD disappears when the modifier is
released. Preview uses a soft gray reading surface to stand apart from the
underlying application. Its title appears only once; inside Preview, P pastes
the displayed text, C copies all of it, and Escape returns to the chooser.

Mouse use is deliberately exploratory: clicking a nested parent opens its
details, while clicking a pasteable result opens that result's Actions menu.
Keyboard Return/Enter and the numbered shortcuts still paste immediately.

A headered tab can reserve a row whose Label is `AI Prompt`. Text in that row's
detail columns becomes the prompt template for the same column. Command-Return
on Mac or Control-Enter on Windows sends the selected item to the AI engine
chosen in `Settings & Help`. ChatGPT is the default; Google AI Mode and
Microsoft Copilot are also available. The Sheet can also
define an optional launcher shortcut with two dropdowns—modifier and key—while
keeping the normal printable trigger available.

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
web/                  Responsive Progressive Web App for phones and desktops
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
AI prompts and the selected item name are sent to the selected external AI
service when the AI action is used.

## Project status

This is an intentionally small personal prototype. It favors understandable,
working behavior over application architecture or visual polish.
