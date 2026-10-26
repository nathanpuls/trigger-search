# Dell source audit, 2026-10-26

Source: Nathan's Downloads/AutoHotkey.zip, containing 31 top-level `.ahk` files,
a previous launcher backup, two `.ahkoff` archives, a launcher shortcut, and an
AdvancedMD browser profile. Only script text was inspected; nothing was executed.

## Migrated in this increment

- `autocomplete.ahk`: baseline matches the GitHub root compatibility copy.
- `follow-up-office.ahk`: Alt+O; newer Dell form navigation.
- `follow-up-tele.ahk`: Alt+T; newer Dell form navigation.
- `intake-office.ahk`: Alt+0.

The three macros are wrapped with focus checks/cancellation while their active
input commands and delays remain identical. Their existing resident scripts must
be exited before enabling the new launcher's corresponding hotkeys.

## Preserved locally; not yet migrated

| Files | Triggers / behavior |
|---|---|
| `blueprint.ahk` | Alt+B |
| `clipboard-special.ahk` | Ctrl+Alt+5 saves / Alt+5 pastes an in-memory value |
| `copilot.ahk` | No enabled hotkey (commented out) |
| `copy back.ahk` | `;cc` |
| `copy paste cut etc.ahk` | Insert copy; Home paste; Delete cut; Win+End save; PgUp select all; PgDn undo; NumpadEnd close tab; F10 find |
| `F2-nat-enter.ahk`, `F3-charge slip.ahk`, `F4-timestamp for note.ahk` | F2, F3, F4 |
| `F8-send-schedule-for-next-day.ahk` | F8; fixed coordinates and email recipients need review |
| `Follow Up MSE.ahk`, `MSE.ahk`, `MSE2.ahk` | `'fum`, `'mse`, Ctrl+Alt+M; test `;hi`/`;go` also exist |
| `sid.ahk` | `;sid` |
| `open_espanso.ahk` | Right Shift sends Ctrl+Space |
| `pageDwn.ahk` | Alt+4; conflicts with telehealth debug |
| `launch AMD.ahk` | Alt+A; site-specific login configuration, global Escape |
| `window.ahk` | Alt+Q |
| `HPI.ahk`, `Morning Start Up.ahk`, `IT ticket.ahk` | Act at startup; site-specific values/coordinates; IT ticket captures Escape/F12 |

## Exclude from managed startup

`follow up tele debug.ahk`, `follow-up-office-old.ahk`,
`follow-up-tele-old.ahk`, `fu-test - Copy.ahk`, `IT ticket-old.ahk`,
`test-esc.ahk`, and the two `.ahkoff` archives are reference/test variants.
Some old/test files have commented-out hotkey openings but active bodies and
closing braces; they require syntax review, not automatic reuse.

`Start_All_My_Scripts.ahk` scans the entire original folder and invokes every
`.ahk`. Its shortcut targets the Dell OneDrive AutoHotkey directory, but the ZIP
does not prove the shortcut is currently in Startup. Multiple global Escape
bindings and semicolon-prefixed hotstrings can compete with Trigger Search.

Actual Dell process list, Startup/Task Scheduler entries, Wispr Flow bindings,
and Raycast `.SR` configuration remain unverified. Do not treat this static file
audit as confirmation that each script is running. The historical GitHub macros
must not replace the newer Dell macros. Browser profile contents and local
clipboard/settings/error caches must not be uploaded to GitHub.
