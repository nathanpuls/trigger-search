# Trigger Search for Windows

A rough AutoHotkey v2 version of the Mac Hammerspoon autocomplete. It reads the
same public Google Sheet and does not use OAuth or a Google sign-in.

## Install on the Dell

1. Open [`windows/autocomplete.ahk`](autocomplete.ahk) in this GitHub repository
   and click **Raw**.
2. Save the raw file as `autocomplete.ahk` in a normal writable folder such as
   Documents. If Notepad is used, choose **All files** for the file type and
   keep UTF-8 encoding so Windows does not add `.txt`.
3. Double-click `autocomplete.ahk`. AutoHotkey v2 should place its green H tray
   icon in the notification area.
4. The first launch displays **Set up Trigger Search**. Paste the complete link
   to your published Google Sheet and choose **OK**. Trigger Search extracts the
   spreadsheet ID and verifies the workbook; no script editing is required.
5. Type `;` at the start of a text run or immediately after whitespace. Type to
   filter, use Up/Down, and press Enter to paste. Escape cancels.

The script is explicitly marked `#Requires AutoHotkey v2.0`, so the AutoHotkey
launcher should choose v2 even if another version is also installed.

## Behavior

- `hello;` types a normal semicolon.
- `;`, `hello ;`, and a semicolon after Enter or Tab open the chooser.
- The main chooser opens with up to nine recently used Sheet items. Typing
  searches the complete workbook; clearing the query restores the recent items.
  Nested views still display their choices immediately.
- Every search includes every visible Sheet tab. Tabs remain visible as source
  labels but are not separate searchable containers.
- The search field uses the uncluttered placeholder **Search**. Shortcut hints
  are not repeated on individual results.
- Press `Ctrl+1` through `Ctrl+9` to choose one of the first nine visible items.
- Aliases rank above ordinary label matches.
- A `→` means an item has nested details. No detail count is shown. Press Right
  to open them and Left to return to the same result.
- Clicking a nested parent opens its details. Clicking a pasteable result opens
  its contextual Actions menu, so mouse use never pastes without an explicit
  choice. Enter and Ctrl+number remain the fast keyboard paths for pasting.
- Press Ctrl+E to open the selected item’s exact Google Sheets cell.
- Press Ctrl+C to copy the selected text without pasting it.
- Press Ctrl+P to open the fully expanded text in a scrollable, selectable
  preview with a soft gray reading surface and one non-repeated title. In the
  preview, press P to paste the displayed text, C to copy all of it, or Escape
  to return to the same result.
- Hold Ctrl for 300 ms to reveal the contextual shortcut HUD; keep holding it
  and press Enter for AI, C to copy, E to edit, G to search Google, O to open,
  or P to preview. Ctrl+G searches Google for the literal text currently typed
  in the launcher, even when it does not match a Sheet item. Other actions
  appear only when applicable.
- Press Ctrl+K to open the stable actions and shortcuts list. A filled dot marks
  an available action and a hollow dot marks an unavailable action, without
  extra warning text. The actions view begins with `←`; Left Arrow returns to the selected
  result and Escape closes Trigger Search completely.
- Enter pastes ordinary snippets. If the entire snippet is one recognizable web
  link, Enter or Right Arrow opens it in the default browser instead; Paste
  remains available from Actions. Ctrl+O opens the single detected link even
  when it appears within ordinary text. Explicit `http://` or
  `https://` links and bare domains such as `example.com/help` work. Multiple
  links are never opened automatically because Trigger Search will not guess.
- Dates, times, clipboard text, and cursor position can be calculated with the
  same dynamic placeholders as the Mac version.
- The Sheet is refreshed at startup, whenever the chooser opens, and every 60
  seconds. The last successful data is cached under `%APPDATA%\SheetAutocomplete`
  for offline use.
- The trigger and optional launcher shortcut come from `Settings & Help`, just
  like the Mac version.

## Sheet layouts

A headered tab supports `Label`, `Content`, optional `Alias`, and any additional
nested-detail columns. If Label or Content is blank, the other value is used
for both display and pasting.

For a quick headerless tab, begin on row 1. With one column, each value is both
the label and content. With two columns, the left value is the label and the
right value is the content. Headerless tabs do not provide aliases or nesting;
a headerless tab with more than two populated columns is ignored.

### Search launchers

Create a tab named `Search`. Headers are optional: without them, column A is the
service name, column B is the URL template, and column C is an optional alias.
With headers, columns may be rearranged and use `Service`, `Label`, or `Name`;
`URL Template`, `URL`, or `Link`; and `Alias` or `Nickname`. Use `{query}` where
Trigger Search should place the typed query:

| Service | URL Template | Alias |
|---|---|---|
| Google | `https://www.google.com/search?q={query}` | g |
| ChatGPT | `https://chatgpt.com/?q={query}` | ai |
| PubMed | `https://pubmed.ncbi.nlm.nih.gov/?term={query}` | pm |

Each valid row is a searchable parent item. Select one and press Right Arrow,
type the query, and press Enter to open it in the default browser. Left Arrow
returns to the same service in the main results.

Rows missing either value and templates without the exact `{query}` placeholder
are skipped quietly. `https://` and `http://` are accepted, and a recognizable
domain without a protocol automatically uses HTTPS. Services can therefore be added,
removed, or rearranged entirely in Google Sheets without editing AutoHotkey.
On tabs with other names, the same recognized header pairs still identify the
launcher layout for backward compatibility. Multiple
aliases may be separated by commas, semicolons, vertical bars, or line breaks;
exact alias matches rank first.

### AI prompts

In a headered tab, place `AI Prompt` in the Label cell of a metadata row
(normally row 2). Put prompt templates beneath the detail headers they belong
to. The metadata row is hidden from search. An AI-enabled detail remains
available even if its saved-value cell is blank. Templates may use
`{medication}`, `{item}`, or `{label}`; if none is present, Trigger Search adds
the selected item as context.

Press Ctrl+Enter to use the prompt. Choose `ChatGPT`, `Google AI Mode`, or
`Microsoft Copilot` from the `AI Engine` dropdown in `Settings & Help`.
ChatGPT opens with a prefilled prompt, Google AI Mode runs the query, and
Copilot opens with the prompt copied for pasting. Ctrl+K also exposes **Ask
AI** and **Copy AI prompt** only when the selected result has AI metadata. If
an AI-enabled nested choice has no saved text, Enter runs the AI prompt
automatically. When saved text exists, Enter still pastes it normally.

## Launcher shortcut

In `Settings & Help`, choose values for `Launcher Modifier` and `Launcher Key`.
The plus sign is inferred. Examples are `Alt/Option` + `Space`, `Control` + `K`,
or `None` + `F6`. `Command/Windows` means the Windows key on this platform.

For safety, a bare letter, number, Space, Return, or Tab is not enabled because
it would steal normal typing. A standalone F1–F12 key is allowed. Set either
launcher field to `None` to disable the extra shortcut. The original printable
trigger remains available independently.

## Change the Google Sheet

Right-click the green AutoHotkey **H** tray icon and choose **Change Google
Sheet...**. Paste the new workbook's complete link. Trigger Search tests the
new Sheet before saving it; if validation fails, the previous Sheet and cache
remain in use. **Open Google Sheet** opens the currently connected workbook.

The selected ID is stored in `%APPDATA%\SheetAutocomplete\settings.ini`, not
inside the script, so it survives GitHub updates. It is local to that Windows
computer and may differ from the Sheet used on a Mac or another PC.

## Inline calculations

The root search field recognizes two kinds of complete calculations:

- Enter `4W`, `6M`, `10D`, or `1Y` to see that future date. Units are days,
  weeks, calendar months, and calendar years; lowercase also works.
- Enter arithmetic such as `90 / 3`, `12 * 5`, or `(90 - 10) / 2`. A leading
  equals sign is accepted but not required.

The calculated result appears first with a plain-language interpretation. Read
it and press Escape, or press Enter to paste the result. A plain number such as
`30` remains an ordinary snippet search. Arithmetic is handled by a restricted
parser and never executes AutoHotkey or code from the Sheet.

## Dynamic placeholders

Trigger Search expands a documented subset of
[Raycast-style dynamic placeholders](https://manual.raycast.com/dynamic-placeholders)
only when a snippet is pasted:

| Placeholder | Result |
|---|---|
| `{date}` | Current date, such as `07/30/2026` |
| `{time}` | Current time, such as `4:30 PM` |
| `{datetime}` | Current date and time |
| `{day}` | Current weekday |
| `{clipboard}` | Plain text that was on the clipboard before the paste |
| `{cursor}` | Removes the marker and leaves the cursor at that position |

Dates and times accept `format` and `offset`:

```text
Annual visit by: {date format="MM/dd/yyyy" offset="+1y"}
Follow up around: {date format="MM/dd/yyyy" offset="+3M"}
Created: {datetime format="MMM d, yyyy h:mm a"}
```

Offsets use `y` for years, uppercase `M` for months, `d` for days, `h` for
hours, and lowercase `m` for minutes. Multiple offsets can be combined, as in
`offset="+1M -3d"`. Calendar-month and year offsets clamp to the final valid
day when necessary, so January 31 plus one month becomes February 28 or 29.

Supported format symbols are `yyyy`, `yy`, `MMMM`, `MMM`, `MM`, `M`, `dd`,
`d`, `EEEE`, `EEE`, `HH`, `H`, `hh`, `h`, `mm`, `m`, `ss`, `s`, `SSS`, and
`a`. Text inside single quotes is literal. Trigger Search intentionally does
not support Raycast's script-like or browser-context placeholders. Unknown
placeholders remain unchanged.

## Get future script updates

Right-click the green H tray icon and choose **Update script from GitHub**. The
script downloads the current GitHub version, saves the previous file beside it
as `autocomplete.ahk.backup`, replaces the working file, and reloads itself.
If the script is already current, it leaves everything unchanged.

## Diagnostics

Every handled or unexpected error report includes the script version, current
action, error type, message, function, file, line number, extra details, and
stack trace. The latest report is always saved to
`%APPDATA%\SheetAutocomplete\last-error.txt`. Right-click the green H and choose
**Show last error report** to display it without finding the file manually.
Each distinct refresh error is displayed once. Identical automatic-retry
failures are logged silently so they do not repeatedly interrupt your work.

GitHub validates the AutoHotkey v2 syntax of every pushed version on a Windows
runner. It also runs the empty chooser, text sorting, alias ranking, and category
filtering paths as runtime smoke tests.

## Start automatically with Windows

After the script works normally:

1. Open File Explorer and enter `shell:startup` in its address bar.
2. If that is blocked, enter
   `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup` instead.
3. Right-drag `autocomplete.ahk` into the folder that opens and choose **Create
   shortcuts here**. Keep the real script in Documents so it remains easy to
   edit.

## Work-computer caveats

- Keep the script in a folder where your Windows account can write files.
- AutoHotkey cannot type into an application running as administrator unless
  the script is also running at the same privilege level. Avoid running either
  one as administrator unless your workplace specifically requires it.
- Company security tools can block global keyboard hooks or clipboard
  automation. If the tray icon appears but the trigger never responds, that is
  the first thing to ask IT about.
- The workbook is public by design. Do not place secrets, patient-identifying
  information, or other private work data in it.
- This is a prototype. Exit it from the green H tray icon if anything behaves
  unexpectedly.
