# Trigger Search for Mac

A small personal Hammerspoon autocomplete backed by a public Google Sheet. It
discovers every visible tab, loads it through Google's public CSV endpoints, and
keeps the latest tab list and valid responses in
`~/.hammerspoon/autocomplete-snippets-cache.json` for offline use.

## 1. Make the Sheet public

Use one tab per category. Every tab must always contain these two headers:

| Label | Content |
|---|---|
| Email address | me@example.com |
| Short signature | Thanks, Nathan |

Both columns remain present even when one is unused. If either cell is blank,
the other value is used for both display and pasting. When both are filled,
Label is displayed and Content is pasted.

An optional `Alias` column provides short search terms without creating a
nested paste choice. Exact alias matches rank first; multiple aliases can be
separated with commas, semicolons, vertical bars, or line breaks.

Optional columns after `Content`, such as `SIG`, `Dose range`, or `Notes`, are
nested details for the item on that row. A main item with filled details shows
a `›` after its label and the number of available details beneath it while keeping them hidden
from the main result list. Press Return or click the medication to paste its
ordinary value; press Right Arrow to open only its detail choices. The nested
search field begins with `←` to show that Left Arrow returns to the same parent
search and highlighted item. Escape closes the chooser, and the next trigger
starts a clean search. Blank details stay hidden.

Visible tabs are discovered automatically from the public workbook. Add,
rename, rearrange, or remove a tab in Google Sheets and the chooser will follow
on its next refresh. `sheetNames` remains only as a fallback if tab discovery
is temporarily unavailable. The reserved `Settings & Help` tab contains both
configuration and usage guidance while staying hidden from autocomplete. The
reserved `Blank Template` tab is also hidden. Duplicate it, rename the copy,
and add your items whenever you want a new autocomplete category. The reserved
`AutoHotkey` tab is a legacy transfer area and is hidden as well. The current
Windows implementation is distributed through this GitHub repository instead
of a multiline Sheet cell.

Use **File → Share → Publish to web** in Google Sheets. Publish the workbook.
No OAuth or Google sign-in is used by this prototype.

## 2. Install

Copy `autocomplete.lua` into `~/.hammerspoon/`, then add the contents of
`init.lua.example` to `~/.hammerspoon/init.lua` and reload Hammerspoon.

On first launch, Trigger Search displays a native setup window. Paste the
complete Google Sheet link and choose **Connect**. It extracts the spreadsheet
ID, verifies the public workbook, and saves the choice locally in Hammerspoon's
settings. You do not need to edit Lua. Existing installations automatically
keep their current Sheet.

A small **TS** item in the Mac menu bar provides **Open Trigger Search**,
**Refresh Now**, **Open Google Sheet**, and **Change Google Sheet…**. A new
Sheet is saved only after it passes validation; otherwise the previous Sheet
and offline data remain available. The local choice survives code updates and
can differ from the Sheet selected on a Windows computer.

On the first run, macOS may ask for Accessibility permission
so Hammerspoon can observe and intercept keystrokes.

The opening character is configured in the Google Sheet's `Settings & Help`
tab. It defaults to a semicolon:

| Setting | Value |
|---|---|
| Trigger | ; |

Replace `;` with another single printable character whenever you prefer. The
local `trigger` value in `init.lua` remains an offline fallback.

## 3. Use

Type the configured trigger at the start of a typing run or directly after a
space, tab, or newline. The trigger is swallowed and the chooser opens. Continue typing to filter,
use the arrow keys to navigate, press Return to paste, or Escape to cancel.
Rows use Hammerspoon's native circular action icon. Nested items additionally
retain the `›` marker beside their labels.
Highlight a result and press Command-E to open its exact row or detail cell in
Google Sheets for editing. The chooser refreshes from the Sheet whenever it
opens, while still appearing immediately from its local cache.

Every search includes every visible tab. Tabs organize the Google Sheet and
appear beneath results as source labels, but they are not separate searchable
containers. The search field uses the placeholder **Search**. When viewing
nested details, press Left Arrow to return to the parent item.
`hello;` types a normal semicolon. `hello ;` opens the chooser.

The prototype checks the focused text field through Accessibility when possible,
so the boundary rule also works after mouse clicks and cursor movement.

## Notes

- A valid network response replaces the in-memory list and the local cache.
- The Sheet refreshes at startup, whenever the chooser opens, and once per
  minute while Hammerspoon is running.
- A failed refresh leaves the previous list and cache untouched.
- `Content` may contain commas, quotes, and line breaks.
- Paste temporarily uses the system clipboard and restores plain-text clipboard
  content after a short delay if nothing else changed it.
- Keep the published Sheet free of secrets: anyone with the published link can
  read it.
