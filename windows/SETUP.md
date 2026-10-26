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

Open AMD reacquires and activates the identified Chrome login window before each login input, uses the original SendEvent for office key 136732, and moves the identified AMD window to the left display. It does not require the window from which the launcher was opened to stay focused. Error dialog titles include the worker version and action so an old running copy can be identified. Actual Dell login and monitor behavior still require a device check.

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
