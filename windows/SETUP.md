# Try the unified Windows launcher

Version **0.16.4** includes Trigger Search and all 24 current workflow/helper
actions in the Automations catalog. Old/debug copies stay excluded from startup. Nothing installs or runs on the Mac.

## Install on the Dell

AutoHotkey **v2** must already be installed. Open **Windows PowerShell** normally
(no administrator mode), then paste:

```powershell
$setup = Join-Path $env:TEMP 'trigger-search-install.ps1'
Invoke-WebRequest 'https://raw.githubusercontent.com/nathanpuls/trigger-search/codex/unified-windows-20261026/windows/refresh-all.ps1' -OutFile $setup -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setup -Ref 'codex/unified-windows-20261026' -NoStart
```

The installer downloads one pinned GitHub commit, verifies every bundled file,
validates AutoHotkey v2 syntax, and runs tests without touching AdvancedMD. It
creates **Documents → Trigger Search**, with three double-click commands:

- **Start-Trigger-Search.cmd** — start the installed release.
- **Refresh-All.cmd** — manually update, validate, and reload the managed scripts.
- **Rollback.cmd** — switch to the previous installed release.

If AutoHotkey isn't found, rerun the final command with
`-AutoHotkeyPath 'C:\full\path\to\AutoHotkey64.exe'`.

Before starting the new launcher, exit the **original** AutoHotkey scripts from
this Dell folder, including autocomplete, form macros, MSE, clipboard, and remap
listeners. The managed launcher now owns their action shortcuts. Old/debug
follow-up scripts and `test-esc.ahk` also have competing Escape/Alt+4 bindings. Do not run `Start_All_My_Scripts.ahk` alongside this setup.
Keep the original files unchanged so returning to them remains possible.
Keyboard remaps are enabled by default in managed installs. Search for the remap toggle or use the tray menu to turn them off/on; that choice survives restarts and code refreshes. Espanso remains available
as an action; Right Shift is left to normal typing in the managed launcher.

Double-click **Start-Trigger-Search.cmd**. The existing local Google Sheet and
cache settings under `%APPDATA%\SheetAutocomplete` are reused.

## Use it

| Shortcut | Result |
|---|---|
| Semicolon | Existing boundary-sensitive Trigger Search behavior |
| Tap Right Ctrl | Hardware scan-code handler; Ctrl combinations and long holds retain normal behavior |
| Ctrl+Alt+Space | Additional launcher shortcut for troubleshooting |
| Type `of`, `tf`, or `oi`, then Enter | Office follow-up, telehealth follow-up, or office intake |
| Alt+O / Alt+T / Alt+0 | The same three macros, preserving Dell shortcuts |
| Escape during a macro | Cancel that macro; review the partially filled form |
| Ctrl+R in the launcher | Refresh Sheet results in place; keep the launcher and search open |
| Ctrl+Shift+I in the launcher | Fetch Inbox now and copy its first usable item |
| Tray → Copy latest Inbox now | Same direct Inbox action without a full refresh |
| Tray → Update script from GitHub / Refresh all scripts | Run the manual bundle updater |

In the **Automations** Sheet tab, edit Name, Alias, and Description freely.
Script ID must match a local allowlisted key. Unknown IDs are skipped; Sheet
text never becomes a filename, process argument, or executable command.
Mac/web safely ignore this Windows automation tab because it has no Content
column. Their existing snippets keep working.

## First test

1. In a blank local text editor, test `;`, typing a normal semicolon inside a
   word, Escape, snippet paste, nested choices, URLs, and Ctrl+R.
2. Tap Right Ctrl. Then test Right-Ctrl+C/V and Ctrl-click; those combinations
   must not open the launcher. In the tray, **Keyboard and installation status**
   must show **0.16.4** and its Right Ctrl event count should increase. This status
   records a count only, never typed text.
3. Copy a non-sensitive Inbox test value from the phone; use Ctrl+Shift+I and
   paste in the text editor. No clipboard contents are logged.
4. In the correct AdvancedMD **test/training form**, position the cursor exactly
   as for the original Dell macro. Run one automation and compare its fields.
   Test Escape cancellation and changing focus to another application.
5. Run Refresh-All twice. The second refresh should leave the same commit
   active and should not create another rollback version.

Macros retain the original field choices and timings, including clinical/billing
values. They do not assess those choices. Their starting cursor position and
AdvancedMD form layout still need your verification on the Dell.

The target must be the original window and its title must contain `AdvancedMD`.
If your EHR uses a different title, add this local section to the existing
`%APPDATA%\SheetAutocomplete\settings.ini` using the stable EHR title fragment
(no patient text):

```ini
[advancedmd]
WindowTitle=AdvancedEHR
```

## Startup and rollback

Update to **0.16.9**, then use the tray menu **Install Original Scripts ON/OFF...**
once. Setup automatically uses `C:\Users\NathanPuls\OneDrive - LifeStance Health\Documents\AutoHotkey`
when it exists; otherwise it asks for the current folder. An existing saved
folder is retained. Review the live process and Startup audit. This creates exactly two shortcuts in that folder:
**Original Scripts ON.lnk** and **Original Scripts OFF.lnk** (Windows normally
hides `.lnk`). The support code and startup backups live in the managed install
folder, not in the original scripts folder. Neither button depends on Trigger
Search running or contacts GitHub/the Sheet. No additional resident script exists.

- **OFF** backs up matching original Startup shortcuts, disables them, and stops
  only known original AutoHotkey processes from that exact folder. It rechecks
  process identity before stopping. Unknown scripts, other folders, every
  `autocomplete.ahk` launcher, and Trigger Search's own startup stay untouched.
- **ON** warns about duplicate hotkeys, validates syntax without executing scripts,
  restores backed-up production shortcuts, adds individual production shortcuts
  where the old wildcard launcher used to supply startup, and starts missing
  production scripts now. Running copies are not started again.
- Both modes keep old/debug/test, the wildcard launcher, and startup-only helpers
  disabled. No original `.ahk` file is edited, moved, or deleted.

ON's explicit production list (only files present in the selected folder run):
`blueprint.ahk`, `clipboard-special.ahk`, `copy back.ahk`,
`copy paste cut etc.ahk`, `F2-nat-enter.ahk`, `F3-charge slip.ahk`,
`F4-timestamp for note.ahk`, `F8-send-schedule-for-next-day.ahk`,
`Follow Up MSE.ahk`, `follow-up-office.ahk`, `follow-up-tele.ahk`,
`intake-office.ahk`, `launch AMD.ahk`, `MSE.ahk`, `MSE2.ahk`,
`open_espanso.ahk`, `pageDwn.ahk`, `sid.ahk`, and `window.ahk`.

ON excludes `autocomplete.ahk` (Trigger Search), `Start_All_My_Scripts.ahk`, all
known old/debug/test copies, `copilot.ahk` (commented-out listener), and
`HPI.ahk`, `Morning Start Up.ahk`, and `IT ticket.ahk` (run-on-open helpers).
Those helpers remain available on demand through Trigger Search.

The former 0.16.7 startup menu is replaced by this install action. Existing
`startup-backup/state.json` snapshots are imported by copying only recognized
legacy shortcuts. The former journal, backup files, and managed Trigger Search
startup link stay unchanged. Never delete `original-scripts/` while relying on
these controls. It contains `state.json` and byte-for-byte shortcut backups.
Unsafe wildcard/debug shortcuts stay backed up; ON deliberately restores only
production startup rather than reinstating the wildcard launcher.

The controls inspect actual processes and user/all-users Startup, Run/RunOnce
registry entries and scheduled tasks on the Dell. Confirmed additional legacy
launch paths block both buttons and are named in the error; they require local
inspection/approval. Those paths are never modified by these buttons. No Sheet
toggle, cloud polling, service, or change to Trigger Search startup is added.
If a process or startup entry uses a relative script path or another wrapper,
it may require manual inspection; the controls never guess which process to stop.

Test on Dell after finishing any original automation: double-click OFF twice;
verify originals stay absent, Trigger Search still opens with F6, and its startup
link is unchanged. Sign out/in to check persistent startup. Double-click ON,
accept the hotkey warning, check original shortcuts, then ON again to check that
no duplicate processes appear. Finish with OFF for normal Trigger Search use.
These live Dell checks are pending; Windows CI tests use isolated directories
and dummy AutoHotkey scripts, never live EHR forms. Original local files are not
available to validate on CI; ON validates them on the Dell before launching any.

Rollback switches between previously installed managed releases. On the very
first install there is no previous managed release: exit the new launcher and
restart the original Dell scripts to revert. Rollback does not revert Google
Sheet edits or local settings. Retained releases are not deleted automatically.
Local edits to a managed release cause refresh to stop rather than overwrite
those files. A running managed clinical macro also blocks refresh.

For this upgrade, run the installer command above once, even if 0.15.0 was
already installed: the earlier updater knows only the initial five bundle files.
Future Refresh-All invocations use the expanded bundle. The tray updater on
0.16.4 also offers bundle installation from a standalone script.

The initial install deliberately follows the feature branch for testing. After
it is merged, switch the source once with:

```powershell
& "$([Environment]::GetFolderPath('MyDocuments'))\Trigger Search\refresh-all.ps1" -Ref main
```

No background **code** updates are enabled. The existing 60-second Sheet refresh
remains. Refresh/rollback errors appear in the PowerShell window; screenshots
of errors should exclude patient data.

## Complete action catalog

The Automations tab now contains the three core form macros plus full/fast/short
MSE, SID, charge-slip, initials, note date, plan/MSE/HPI navigation, AdvancedMD
login and morning startup, Blueprint, IT ticket, schedule email composition,
Copilot, Espanso, copy to previous window, the two special-clipboard actions,
and a keyboard-remap toggle. Name, Alias, and Description remain editable.

Alt+A/B/Q/4, F2/F3/F4/F8, Ctrl+Alt+M, Ctrl+Alt+5, Alt+5, and the apostrophe MSE
hotstrings are provided by the managed launcher. Semicolon hotstrings still
compete with the existing printable trigger at a word boundary; using the `sid`
or `cc` search alias is dependable without changing semicolon behavior.

Open AMD and morning startup always use office key `136732`, without a setup
prompt. IT ticket and schedule email still ask for their local values if missing.
Those prompted values are saved only in the Dell settings.ini;
they never belong in the public Sheet or repository. Browser-navigation helpers
retain fixed timing/coordinates and need testing against your current layout.
The schedule helper composes a draft and does not send it. The IT-ticket source
had a commented-out function opening; it is now an explicitly invoked function.
All web helpers stop if their expected window cannot be activated.

The configured launcher key (F6 when selected in Settings & Help) toggles the
launcher open and closed. Escape closes it from the search, Actions, or Preview.

## Shortcut reference

Standalone Dell shortcuts are appended to the existing Description values in
the Automations tab. No extra column is needed. This is reference text; editing
it does not rebind keys. Typed hotstrings and standalone-only bindings are
labelled accordingly. Entries without a binding say so.

0.16.4 also accepts the four specific AMD Script ID aliases already in the Sheet
and tolerates additional reference columns if users add them later.

Open AMD reuses the existing login window when available, uses office key
136732, and moves that window directly to the leftmost display before maximizing.
It no longer relies on the Windows+Shift+Left keyboard shortcut.

Open AMD does not require the original pre-launch window to retain focus. It
activates the identified login window before typing and uses explicit AMD window
handles for placement after login, including redirects/popups. Other form-filling
actions retain their strict focus checks.

### Version 0.16.5 corrections

Exact aliases rank first across snippets and automations. Matching alias prefixes then sort by shortest alias before name and description matches (T, TA, TAP). Display names such as AMD are independent of trusted Script IDs. Keep the canonical advancedmd.* IDs in the Sheet; the explicit AMD.* compatibility IDs remain supported.

Open AMD reacquires and activates the identified Chrome login window before each login input, uses the original SendEvent for office key 136732, and places the identified AMD window on the right display’s left half (as of 0.16.23). It does not require the window from which the launcher was opened to stay focused. Error dialog titles include the worker version and action so an old running copy can be identified. Actual Dell login and monitor behavior still require a device check.

## Send Dell clipboard to Inbox

In 0.16.11, **Alt+I** works globally, including when the launcher is closed.
It sends the current plain-text clipboard to the existing Google Apps Script
Inbox API. That endpoint inserts the entry at row 2, immediately below the header,
with a Dell timestamp label. It never appends at the bottom. Clipboard contents
are not changed or written to request/error logs. No browser opens during use.

Run **Refresh all scripts**, then copy some text and press Alt+I.
If the setup file is not already in Downloads, the first press opens its private
Google Drive page. Download **Trigger-Search-Inbox-Setup.ini** to any folder,
then select it when asked. ChatGPT is not required on the Dell. The tray menu
also offers **Open private Inbox setup (Google Drive)**. Only the file owner
can access it; no public sharing was enabled. Configuration stays in
`%APPDATA%\SheetAutocomplete\inbox-api.ini`, outside GitHub and the public Sheet.
The file must match the active Sheet ID and use an HTTPS script.google.com
Apps Script endpoint. Keep its token private. No API token belongs in this repo.

The shortcut reports success only after the API confirms the write, then fetches
the latest Inbox directly to update the launcher's pin. A timeout never retries
automatically: check Inbox before pressing again, since the server may already
have saved the row. Empty clipboards and text over 45,000 characters are rejected.
Images/files are not uploaded. The existing API controls whitespace handling.

Ctrl+Shift+I **inside the launcher** remains the reverse direction: copy the
latest Inbox cell to the Windows clipboard. Ctrl+R refreshes Sheet data in place.

Endpoint health was verified in the connected Google session. Windows CI covers
JSON/Unicode, success/rejection handling, clipboard preservation, and destination
validation with mock requests. Sending from the actual Dell still needs a device
check. The existing server code/deployment was not changed.

### Single-key Dell remaps (0.16.11)

Trigger Search supplies these itself while the original scripts are OFF. They
are enabled by default and stay inactive inside the launcher so its text fields
and navigation work normally. The Sheet's existing `keyboard.remaps` automation
and the tray toggle both save an explicit ON/OFF preference locally.

As of 0.16.20, these essential keys work immediately at startup and offline;
they do not wait for the Google Sheet formatting check. A verified strikethrough
of `keyboard.remaps` is still honored, including from the last saved cache.
An explicitly saved local OFF preference is also preserved.

| Key | Action |
| --- | --- |
| Insert | Copy |
| Home | Paste |
| Delete | Cut |
| Page Up | Select all |
| Page Down | Undo |
| Windows + End | Save |
| Numpad End | Close tab |
| F10 | Find |

No additional resident AutoHotkey process is needed. Physical key delivery on
the Dell remains a device check; Windows tests cover default enablement, the
saved toggle, and keeping remaps inactive inside the launcher.

In 0.16.12, the typed automation hotstrings use executable blocks instead of
AutoHotkey replacement text: `'fum` runs follow-up MSE, `'mse` runs full MSE,
`;sid` runs SID, and `;cc` runs copy-back. Type them outside the launcher in the
intended target field; no ending space is required. Existing focus checks apply.

## Join Zoom (0.16.13)

Search **Join Zoom** or **zoom** in Trigger Search. The trusted ID is `zoom.join`
and the implementation is `JoinZoom()` in `automations/dell/helpers.ahk`. It
uses the same existing six-file release bundle and exits after positioning.
First use asks for your Zoom PMI link; it stays only in local settings under
`[workflow-config] ZoomMeetingUrl`, never in GitHub or the public Sheet.

With no meeting open, the action opens that URL in the default browser and waits
up to 60 seconds for a Zoom meeting window; complete any Open Zoom or join prompt
yourself. As of 0.16.23, the regular meeting is restored and placed on the
**leftmost display, right half, full work-area height**. Negative monitor
coordinates and taskbars are respected. Zoom may enforce a larger minimum size.
If Zoom is in fullscreen, exit fullscreen if it refuses to resize.

If a regular meeting is already open, Alt+Z reapplies this half-screen layout
and focuses it. An existing tiny/floating view still uses the launcher's focus-only
path; Alt+2 restores it, then Alt+Z reapplies the regular layout. It does not close
a live call. After
a new meeting is detected it closes only exactly named Zoom home windows, not
arbitrary Zoom windows. English meeting titles / the Zoom meeting window class
are used; actual Dell Zoom recognition and final size require a device check.

The optional Raycast wrapper is `integrations/raycast/join-zoom.ps1`. Replace
the old Windows Raycast script contents with that wrapper if you want to keep
Raycast's Join Zoom command. It calls the stable `Join-Zoom.cmd` in the managed
installation, which invokes the same allowlisted local action. A custom install
root needs the wrapper's `$root` adjusted. Alt+Z is provided by Trigger Search as of 0.16.16.

The original PowerShell error was `:MoveWindow(...)`; calling the supplied C#
static method would require `[WinAPI]::MoveWindow(...)`. The wrapper eliminates
that duplicate implementation rather than storing a personal meeting URL in
source. CI validates script syntax, bounds, safe URL validation, home/meeting
classification, and dry runs without starting Zoom or joining a meeting.

Version 0.16.14 also accepts Zoom personal links using `/my/<name>` (with an
optional trailing slash and query), alongside numeric `/j/` and `/s/` links.
The configured meeting URL still stays only in local Dell settings.

In **0.16.15**, **Refresh all scripts** is a searchable Automations command
(alias **refresh**, trusted ID `trigger-search.refresh-all`). It calls the same
manual updater as the tray item, including validation, worker-running protection,
restart, and rollback support. It refreshes code; Ctrl+R still refreshes Sheet
data in place. Sheet rows cannot supply arbitrary update commands.


## Zoom keyboard controls (0.16.18)

Remove **Alt+Z** from the Dell Raycast Join Zoom command before using it here.
Trigger Search cannot edit the Dell's Raycast settings remotely. Keep Raycast's
other snippets and shortcuts. Its optional Join Zoom wrapper can remain unbound.

**Alt+Z** focuses the existing meeting or its floating video, keeping its current
size and position. If no meeting exists, it opens the saved link. The searchable
Join Zoom action uses the same behavior. The main window is also detected while
hidden behind Zoom's floating thumbnail, preventing a second call from opening.

With the Zoom meeting or its floating video focused, hold Alt and use:

| Keys | Action |
|---|---|
| Left / Right | One horizontal step: left, center, right |
| Up / Down | One vertical step: top, middle, bottom |
| Left+Up / Right+Up / Left+Down / Right+Down | Snap directly to that corner |
| 2 | Zoom's native tiny floating video thumbnail |
| 3 | Small regular window: request 640 x 480 |
| 4 | Medium: request 960 x 720 |
| 5 | Large: request 1280 x 960 |
| 6 | Maximize (not Zoom fullscreen) |

Alt+2 invokes Zoom's own accessible Minimize button. If that exact button is
not exposed, it sends the native title-bar minimize system command, allowing
Zoom to handle its thumbnail mode. It positively identifies the resulting
thumbnail by its **Show full meeting window** button (also accepts Exit minimized
video / Exit mini window / Restore full meeting window). Windows UI Automation checks that button through an on-demand PowerShell
bridge with an eight-second timeout. If no supported thumbnail is confirmed,
it restores the main meeting and reports the issue. It never substitutes a small regular window or silently leaves the
meeting hidden. Repeating Alt+2 while in thumbnail mode leaves it there.

Arrows move the thumbnail itself without resizing it. Alt+3–6 invoke its expansion
button first, then size the full meeting window. After the first successful Alt+2, its class and size limits are learned locally
so Alt+Z and arrow hotkeys can identify it immediately, including after refresh.
Alt+Z focuses that thumbnail without expanding it. If thumbnail mode was entered
manually before the first Alt+2, Alt+Z may restore the full meeting instead. **Alt+M is no longer intercepted** and retains
Zoom's native behavior. The on-demand UI bridge exits after each lookup/action and adds no tray icon.
No UI labels or phone numbers are saved; only thumbnail class/size limits are
stored locally. The controls require English accessibility button names;
actual Zoom/Dell compatibility must be checked locally.

Hold Alt and press two perpendicular arrows together to snap directly to a corner
(either key-down order is accepted, with a 45-millisecond chord window). Single
arrows still move through the center positions. Movement retains size; resizing
retains the nearest grid anchor. Repeated arrows
stop at the current monitor's edge with a 24-pixel margin. Zoom may enforce larger
minimum sizes. From top center, Left goes top left; Right returns to center,
then another Right goes top right. Ordinary arrows, numbers and typing are
unaffected. The Alt shortcuts intentionally override matching native Zoom uses
in the meeting, including while its embedded chat field is focused. Separate
Zoom home/settings/chat windows are excluded. **Outside Zoom, Alt+4 keeps AMD
plan navigation and Alt+5 keeps stored-clipboard paste.** Exit Zoom fullscreen
before arranging it if needed.

Dell check: refresh and confirm tray version **0.16.18**. During a test meeting,
try Alt+2: video must remain visible in Zoom's native tiny window. Then focus it
with Alt+Z, move it with arrows, and test Alt+3–6 to expand it. Repeat after a
Trigger Search refresh while already in thumbnail mode. Confirm ordinary chat
typing, Alt+4 in AMD, and Alt+5 clipboard paste outside Zoom still work. Test both
monitors. Automated Windows checks cover geometry, accessibility button lookup
and invocation on a harmless fixture, syntax, and the existing updater/rollback
suite; they cannot verify Zoom's actual accessible control names on your Dell.
Use **Rollback.cmd** to return to the previous release. Restore Raycast's Alt+Z
assignment too if reverting ownership.


## End Zoom and clipboard calls (0.16.18)

Remove the Dell Raycast assignments **Alt+1** (End Zoom), **Alt+P** (Teams Call
from Clipboard), and **Alt+Z** (Join Zoom) before using the Trigger Search
versions. Raycast's other commands and snippets are unchanged.

- **Alt+1**, or searchable **End Zoom** (`zoom.end`), immediately force-closes
  processes whose executable is exactly `Zoom.exe`, ending any active Zoom call
  without an End/Leave confirmation. This preserves the supplied script's
  behavior but excludes unrelated processes whose name merely contains Zoom.
  Process identity is checked using the same native handle used to stop it.
- **Alt+P**, or searchable **Teams Call from Clipboard**
  (`teams.call-clipboard`), takes one formatted 10–15 digit phone number from the
  clipboard and opens `tel:<digits>`, matching the supplied Raycast script.
  **Teams must be the Windows default for TEL links.** This does not force Teams
  if Windows has a different default. The clipboard remains unchanged, and no
  number or clipboard contents are saved or logged. Notes, letters, extensions,
  multiple numbers, and empty/short/long input are rejected before opening a
  link. Review the number in the calling app before placing the call.

The supplied Raycast PowerShell versions are retained under
`integrations/raycast/originals/`. Their existing behavior is documented; they
are reference copies and are not launched by the updater or installed into
Raycast. Trigger Search dispatches the maintained AutoHotkey implementations in
`automations/dell/helpers.ahk`. Both commands run on demand, without another
resident script or tray icon. No real Zoom call was ended or phone number dialed
in automated tests.


## Strikethrough disables an automation (0.16.19)

Strike through the **Name** cell (or the entire row) in Automations to disable
that action. Striking its **Script ID** cell also disables it. The disabled action
is removed from launcher search and cannot dispatch; its managed keyboard
shortcut/hotstring is released. Remove the strikethrough to enable it again.
Striking only a description or alias is treated as an editorial edit. Partially
struck rich-text names stay enabled unless the entire name is struck.

Use **Ctrl+R** with the launcher open to apply edits immediately, or wait for
the normal idle refresh (about 60 seconds). This is a data/formatting refresh,
not a code update. A small read-only XLSX export supplies formatting omitted by
CSV; the Windows built-in ZIP/XML libraries read it without Excel, credentials,
an API key, another app, or a new Sheet column. Temporary exports are deleted.
The last verified disabled state is cached for offline restarts. Network/export
failure retains that state; before the first verified formatting read, managed
automation shortcuts remain inactive. Snippets remain cache-first. Existing
Original Scripts ON listeners and Raycast bindings are independent; this rule
controls Trigger Search's own shortcuts and dispatch, not those backup files. An already executing worker is allowed to finish;
strikethrough prevents subsequent launches.

For the struck Plan navigation row, Alt+4 no longer starts the AMD helper.
Zoom's size-key context also recognizes its native tiny windows, preventing
fall-through into another automation while a Zoom view changes.

## Zoom recovery (0.16.19)

**Alt+2 is now a toggle:** enter the tiny view, or return to the previous regular
window, keeping the tiny view's current screen/corner anchor. **Alt+3–6** expand the tiny view before selecting a larger size. Recovery
tries Zoom's accessible expansion action and then the recorded main meeting
window's native Restore action. It no longer depends solely on one English
button label or on having learned a mini-window class in this session.

The main meeting handle is remembered before entering the tiny view. While
that tiny view is visible, only that known underlying meeting/black-room window
is hidden; it is shown again on restoration. No meeting window is closed to
clean up the background. Repeated floating-video confirmation notifications
have been removed; an unsupported mini transition quietly restores the main
window. Exact behavior still needs a Dell/Zoom test.

As of 0.16.22, automatic **Reclaim Host** attempts are removed. Alt+Z focuses or
opens Zoom without clicking host controls or triggering their follow-up prompts.
Use Zoom's own host controls when needed.

Dell check: update to 0.16.19, use Ctrl+R, confirm struck actions are absent and
their shortcuts are released, then remove/reapply strikethrough and repeat.
Restart offline to verify the cached state. In a test meeting, toggle Alt+2
repeatedly, try Alt+3–6 from the tiny view, use diagonal arrows, and confirm the
underlying room window stays out of the way. CI validates cache behavior, native OOXML formatting, control
invocation, worker syntax, install, startup isolation, and rollback; it does not
join or end a real meeting or change host privileges.


## Local patient directory (0.16.21)

On Windows, the launcher reads the existing local UTF-8 CSV-formatted text file
at `%USERPROFILE%\OneDrive - LifeStance Health\Desktop\Patients\patient-directory.txt`.
It also recognizes `Patients\patient-directory.txt` under the Windows Desktop
location. No download or Sheet tab is needed. Required headers are exactly
`MRN,Last Name,First Name` (column order can vary). Identifiers stay text,
including leading zeroes; CSV quoting, Unicode names, BOM and CRLF are supported.
Duplicate identical records collapse. Conflicting duplicate MRNs, incomplete
records, malformed CSV and files larger than 8 MB fail closed with a generic
local status; no record contents are included in diagnostics.

Open F6 and type at least two characters of a first name, last name, either
name order, or an MRN. Up to 50 matching patients appear alongside snippets and
automations; type more to narrow them. Exact snippet/automation aliases retain
priority. Patients never appear in the empty home view or one-letter searches.
Their visible MRNs distinguish patients who share a name. Enter, Right Arrow
or Ctrl+K opens the patient's menu. Left Arrow returns; Escape closes.

This release implements **local search and the patient menu**, with an explicit
**Copy MRN** action. The AdvancedMD search, Blueprint recording and call menu
entries are visibly unavailable: patient-specific browser workers have not yet
been connected, and the supplied directory has no phone column. Opening a
website is not treated as selecting a patient or starting a recording. Do not
rely on these entries to perform clinical actions yet. A future AdvancedMD
worker must match the exact MRN field in exactly one result, ignore matching
phone digits, and verify the opened chart before continuing.

Patient records remain in a separate in-memory collection. They are not added
to the Google Sheet, Sheet CSV cache, saved recents, or updater bundle. The
launcher reloads the file on opening and Ctrl+R; a missing/unreadable file
clears stale records. Copy MRN rechecks the selected record before touching the
clipboard. Copying is explicit and uses the workstation's existing clipboard
settings, including any clipboard sync policy.

Local patient mode disables the root Google fallback and Ctrl+G, including for
unmatched names, and removes generic snippet/AI/Sheet-edit actions from patient
records. Known Sheet snippets and deliberately selected search services keep
their existing behavior: do not use those external services for patient data.
Error reports in this mode omit message, extra-data and stack values. The
existing Inbox shortcut still sends the clipboard when explicitly invoked;
it does not receive patient records automatically.

The file's location is in the employer's OneDrive folder and may already sync
through OneDrive. The launcher introduces no additional directory upload.
Local-only settings can override `[patients] directoryPath` in
`%APPDATA%\SheetAutocomplete\settings.ini`. `[patients] enabled=0` disables
this feature and restores the ordinary web-search behavior. The default is ON,
so a missing patient file still cannot cause a typed name to fall through to
Google. No patient data belongs in this settings file or in GitHub.

Windows CI uses invented records only and tests parsing, identifiers, ranking,
privacy guards, stale selections and the real chooser's patient-menu path.
The actual Dell directory and live Chrome/AdvancedMD/Blueprint interactions
remain unverified. On the Dell, refresh all scripts, open F6, check the local
patient count, search a known name and press Enter to inspect the menu.


## General Chrome and AdvancedMD focus (0.16.22)

- **Alt+X** focuses the most recently used eligible Chrome browsing window.
  AdvancedMD titles are excluded case-insensitively, including `AdvancedMD - EHR`,
  `AdvancedMD-EHR` and AMD login pages. A window identified as AMD stays excluded
  during this launcher session if its title later changes. If none is eligible,
  open a separate blank Chrome window with `--new-window`, rather than reusing
  the EHR window. Minimized browsing windows are restored by activation.
- Windows foreground events track Chrome usage locally using HWNDs/process IDs
  and a sequence number; no titles, URLs or patient values are saved. Before any
  history has been observed (or if Windows denies the hook), desktop Z-order is
  the fallback. This keeps ordinary, minimized and pinned windows usable without
  another resident script. Only Chrome browser-class windows are candidates.
- The same action is searchable as **General Chrome**, aliases `x, chrome, browser`,
  Script ID `chrome.general`. Strikethrough disables its managed Alt+X binding.
- **Alt+A / Open AMD** first looks for a Chrome EHR window with either spelling
  above. As of 0.16.23 it focuses and places the EHR on the right display's left
  half. It does not repeat login or type office key 136732 into an open EHR.
  If no EHR window exists, the existing login flow is preserved, followed by
  the same half-screen placement.
- Disable Raycast's **Alt+X** binding on the Dell before trying the new binding.
  This update cannot inspect or change that device's Raycast configuration.
- The optional complete, standalone script is
  [focus-general-chrome.ahk](standalone/focus-general-chrome.ahk). It has no includes
  or external dependencies and has the same tested focus code as the launcher.
  It is a reference/alternative, is not installed by Refresh all scripts, and
  must not run alongside the launcher's Alt+X binding. The normal setup keeps
  Trigger Search as the only resident AutoHotkey script.

Patient search results already show the MRN in their details column; the patient
action menu now also keeps it visible in its footer. Live Dell Chrome/Raycast,
AMD login and actual monitor placement still require a device check.


## Half-screen desk layout and Chrome sharing notice (0.16.23)

Alt+A / Open AMD places a new or already-open EHR on the **rightmost monitor's
left 50%**, at the full usable height. Alt+Z / Join Zoom places a new or existing
regular meeting on the **leftmost monitor's right 50%**, at the full usable
height. Monitor selection uses actual work-area coordinates, independent of
which monitor is primary or the monitor number Windows assigned. On a single
monitor the applications use opposite halves. Taskbars are excluded; odd widths
are split without a missing pixel. The bounded second placement handles normal
cross-monitor DPI resizing. No maximize-to-whole-monitor step follows placement.

The Alt+X filter now rejects Chrome's screen-sharing notification window,
non-resizable frames, owned dialogs and tool windows, in addition to AdvancedMD.
Both candidate selection and activation apply the filter. A notification titled
“Clinician Blueprint AI is sharing your screen and audio” can no longer become
the browsing candidate. Hide on that notification minimizes it; Alt+X must not
restore it as though it were a browser. The shortcut neither clicks Stop sharing
nor changes the shared screen, microphone, permissions or recording state.
The optional standalone Chrome script uses the same updated filter.

The form workflows' existing focus guard is retained. They check the exact target
HWND and its AdvancedMD title before sending each input. Switching applications,
a missing window or a title mismatch can stop a partly completed workflow; review
the form before retrying. The generic catch message does not identify the exact
failed check, and other worker exceptions can also reach that message. No form
inputs, titles or patient data are logged to diagnose it.

Windows checks cover a real synthetic window's restore/resize behavior, monitor
selection, negative coordinates, taskbars, odd widths and sharing-toolbar
exclusion. Actual Dell DPI/window constraints and Chrome/Zoom versions still
need a device check. After Refresh all scripts, test Alt+A, Alt+Z, then Alt+X
followed by Ctrl+T. Keep Raycast Alt+X unbound. The proposed whole-morning command
remains future work; this change only places applications when their action is
invoked.


## Start my day — Alt+L (0.16.24)

After Refresh all scripts, unbind **Alt+C** and **Alt+S** in Dell Raycast. Trigger
Search now supplies those shortcuts as well as **Alt+L**, searchable as **Start
my day** (`workspace.start-day`). No extra download, resident service or startup
entry is required. A single temporary `#NoTrayIcon` worker runs the job and exits;
the existing launcher remains responsive. A named workspace lock rejects repeat
invocations while setup is already running.

| Application | Individual shortcut | Alt+L placement |
| --- | --- | --- |
| AdvancedMD | Alt+A | Rightmost monitor, left half, full work-area height |
| Copilot | Alt+C | Leftmost monitor, left half, full work-area height |
| General Chrome | Alt+X | Rightmost monitor, top-right quarter |
| Microsoft Teams | Alt+S | Rightmost monitor, bottom-right quarter |
| Zoom | Alt+Z | Leftmost monitor, right half, full work-area height |

Alt+L runs AMD, Copilot, Teams, Chrome, then Zoom. Each stage reuses an identified
existing window, or opens the application. A stage failure is caught so the
remaining applications can proceed. Zoom is last so its browser/join prompt
does not hold up opening the other apps. One final notification lists any apps
needing attention. Sign-in and browser Open Zoom prompts remain manual; complete
them and rerun Alt+L if necessary. Escape cancels the temporary worker. Placement
uses actual monitor work areas and excludes taskbars. App minimum sizes or
fullscreen modes can prevent the requested rectangle on the real device.

Copilot reuses an identified native/PWA/browser Copilot main window. Otherwise
it opens the existing Microsoft 365 business URL, `https://m365.cloud.microsoft/chat`,
in a dedicated Chrome app window. It does not send prompts or clipboard text.
Teams reuses an identified Teams desktop main window or launches the installed
`msteams:` handler; it does not initiate a call. These recognizers use an allowlist
of process names, title markers and normal-frame checks, excluding toolbars,
notifications and identified call windows. Exact recognition still needs a Dell
check. Microsoft sign-in pages and identified Copilot windows are excluded from
general Chrome selection, alongside AMD and sharing notices.

Alt+C and Alt+S alone focus/open their applications without rearranging an
already-open window. Alt+X keeps its existing focus-only behavior. Alt+A and
regular-window Alt+Z retain their previously requested half-screen placement.
Alt+L reapplies all five positions. It opens your saved Zoom meeting link;
there is no Admit/Admit all action, no waiting-room change and no automatic host
reclaim. Existing regular meeting windows are reused without starting a second
call. If a floating/tiny view remains visible, restore it with Alt+2.

The new Teams and workspace actions have fixed local registry mappings. Copilot
reuses `dell.copilot`. The disabled legacy `dell.morning-startup` action is
unchanged. A struck application row is omitted from the workspace's enabled
mask when the job starts; an already-running job is allowed to finish with that
snapshot. Strike **Start my day** itself to disable Alt+L. The existing Open AMD
`l` search alias is preserved; the keyboard shortcut Alt+L is independent of it.

Checks cover exact shared Chrome code, masks and strikethrough, fixed-stage
ordering, failure continuation, quarter geometry, main-window recognition,
clinical/workspace lock separation, worker dry runs and install/rollback. These
checks use invented window data and synthetic windows. They do not sign into
Microsoft/AdvancedMD, join Zoom, admit a patient or verify the actual Dell's apps.
