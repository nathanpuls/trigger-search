# Try the unified Windows launcher

Version **0.16.3** includes Trigger Search and all 24 current workflow/helper
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
Keyboard remaps are available as a searchable toggle. Espanso remains available
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
| Ctrl+R in the launcher | Refresh Sheet snippets and reopen |
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
   must show **0.16.3** and its Right Ctrl event count should increase. This status
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

Once the tests pass, open `shell:startup`. Replace only the shortcut that starts
**Start_All_My_Scripts.ahk** with a shortcut to **Start-Trigger-Search.cmd**.
Do not delete the old launcher or its scripts. Do not reinstate the wildcard launcher. No startup entries are changed automatically.

Rollback switches between previously installed managed releases. On the very
first install there is no previous managed release: exit the new launcher and
restart the original Dell scripts to revert. Rollback does not revert Google
Sheet edits or local settings. Retained releases are not deleted automatically.
Local edits to a managed release cause refresh to stop rather than overwrite
those files. A running managed clinical macro also blocks refresh.

For this upgrade, run the installer command above once, even if 0.15.0 was
already installed: the earlier updater knows only the initial five bundle files.
Future Refresh-All invocations use the expanded bundle. The tray updater on
0.16.3 also offers bundle installation from a standalone script.

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

0.16.3 also accepts the four specific AMD Script ID aliases already in the Sheet
and tolerates additional reference columns if users add them later.

Open AMD reuses the existing login window when available, uses office key
136732, and moves that window directly to the leftmost display before maximizing.
It no longer relies on the Windows+Shift+Left keyboard shortcut.
