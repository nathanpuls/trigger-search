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
- Every search includes every visible Sheet tab. Tabs remain visible as source
  labels but are not separate searchable containers.
- The search field uses the placeholder **Search**.
- Press `Ctrl+1` through `Ctrl+9` to choose one of the first nine visible items.
- Aliases rank above ordinary label matches.
- A `›` means an item has nested details. Press Right to open them and Left to
  return to the same result.
- Press Ctrl+E to open the selected item’s exact Google Sheets cell.
- Dates, times, clipboard text, and cursor position can be calculated with the
  same dynamic placeholders as the Mac version.
- The Sheet is refreshed at startup, whenever the chooser opens, and every 60
  seconds. The last successful data is cached under `%APPDATA%\SheetAutocomplete`
  for offline use.
- The trigger comes from `Settings & Help`, just like the Mac version.

## Change the Google Sheet

Right-click the green AutoHotkey **H** tray icon and choose **Change Google
Sheet...**. Paste the new workbook's complete link. Trigger Search tests the
new Sheet before saving it; if validation fails, the previous Sheet and cache
remain in use. **Open Google Sheet** opens the currently connected workbook.

The selected ID is stored in `%APPDATA%\SheetAutocomplete\settings.ini`, not
inside the script, so it survives GitHub updates. It is local to that Windows
computer and may differ from the Sheet used on a Mac or another PC.

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
