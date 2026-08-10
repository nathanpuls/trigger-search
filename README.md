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

### Sheet layout

The canonical headers are `Name`, `Alias`, and `Content`. `Content` is the only
required value: it is the text, link, template, or other value an action uses.
Name is an optional short display name, and Alias is an optional faster way to
find it. When Name is blank, Trigger Search derives a short display preview
from Content. A row with blank primary Content is still valid when it contains
a nested value or an AI prompt. The older `Label` header remains accepted for
backward compatibility.

### Included Sheets

On Mac and web, the primary workbook can include public Trigger Search
collections maintained in other Google Sheets. In `Settings & Help`, use these columns:

| Included Sheet Name | Google Sheet URL | Enabled |
|---|---|---|
| Shared clinic set | `https://docs.google.com/spreadsheets/d/.../edit` | TRUE |

Each enabled public workbook is merged into search. Its tab names are shown as
`Included Sheet Name · Tab Name` so sources remain clear, and edit actions link
back to the correct workbook. Blank Enabled cells count as enabled; use FALSE,
No, 0, or Off to disable a row. The primary Sheet remains the only link someone
needs to share because it carries the Included Sheets list with it.
Windows support can be added in the later Windows synchronization pass.

Sheet tabs also appear as folder-like results in the ordinary search. A short
prefix finds them quickly (`i` finds `Inbox`), and initials work for multiword
names (`pm` finds `Psych Meds`). Return or Right Arrow opens the tab's entries;
Command-E or Control-E opens the tab itself in Google Sheets. From inside a
tab, the same edit shortcut opens the selected item's exact row. Left Arrow
backs out one level to the complete search.

### Search launchers

The simplest setup is a tab named `Search`. Headers are optional: without them,
column A is the service name, column B is the URL template, and column C is an
optional alias. With headers, use `Name`, `Alias`, and `Content`; Content holds
the URL template. The legacy names `Service`, `Label`, `URL Template`, `URL`,
`Link`, and `Nickname` remain accepted.

| Name | Alias (optional) | Content |
|---|---|---|
| Google | g | `https://www.google.com/search?q={query}` |
| PubMed | pm | `https://pubmed.ncbi.nlm.nih.gov/?term={query}` |
| ChatGPT | ai | `https://chatgpt.com/?q={query}` |

Each valid row becomes a normal searchable parent item. Select a service and
press Right Arrow (or click/tap it on the web) to enter a query, then press
Return/Enter to open the encoded query in the default browser. Left Arrow
returns to the same service in the main results.

Templates must contain the exact placeholder `{query}`. `https://` and
`http://` are accepted, but the protocol is optional for recognizable domains:
`wikipedia.org/w/index.php?search={query}` automatically uses HTTPS. Incomplete
or invalid rows are ignored. This keeps the
feature generic: add search engines, AI services, documentation sites, or an
internal HTTP search tool without changing Trigger Search's code. On tabs with
other names, the same recognized header pairs still identify the launcher
layout for backward compatibility.
Aliases use the same comma, semicolon, vertical-bar, or line-break separators
as ordinary snippets, and exact alias matches rank first.

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

Return/Enter pastes ordinary snippets. When the entire saved value is one
recognizable web link, Return/Enter opens it in the default browser instead.
Command-O on Mac or Control-O on Windows explicitly opens a single link found
within a larger snippet. Command-C on Mac or Control-C
on Windows copies the selected text without pasting it. Command-P on Mac or
Control-P on Windows opens the full expanded text in a readable, selectable
preview; Escape returns to the same result. Command-K or Control-K opens a
contextual action menu for the selected result.

When typed text has no matching result, Return/Enter searches Google for that
text in the system's default browser. Command-G on Mac or Control-G on Windows
does the same thing at any time, even while matching Sheet items are visible.

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

A headered tab can reserve a row whose Name is `AI Prompt`. Text in that row's
detail columns becomes the prompt template for the same column. Command-Return
on Mac or Control-Enter on Windows sends the selected item to the AI engine
chosen in `Settings & Help`. ChatGPT is the default; Google AI Mode and
Microsoft Copilot are also available. The Sheet can also
define an optional launcher shortcut with two dropdowns—modifier and key—while
keeping the normal printable trigger available.

### Launcher shortcut settings

In the Sheet's `Settings & Help` tab, `Launcher Modifier` and `Launcher Key`
normally combine into one shortcut; the plus sign is inferred. Examples include
`Alt/Option` + `Space`, `Control` + `K`, and `None` + `F6`.

On Mac, the Launcher Key dropdown also includes `Right Option (tap)` and
`Right Command (tap)`. Either choice opens Trigger Search when that modifier is
tapped by itself, while combinations such as Option-click and Command-C retain
their normal behavior. `Launcher Modifier` is ignored for these two tap-only
choices. They are Mac-only; use a standard two-key combination or F1–F12 on
Windows. Set the launcher fields to `None` to rely only on the printable
trigger.

## Connect your Google Sheet

Publish your workbook with **File → Share → Publish to web** in Google Sheets.
The first time Trigger Search runs, paste the complete Sheet link into its setup
window and confirm. Trigger Search extracts the spreadsheet ID and checks the
public data without requiring code edits. Mac and Windows save the choice only
on that computer. The web version also places the public Sheet ID in its URL so
the configured launcher can be shared as a normal link.

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
