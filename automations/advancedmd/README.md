# AdvancedMD workflows

These three workers were derived from Nathan's current Dell `AutoHotkey.zip`,
not the historical `autohotkey` repository. `provenance.json` records each source
file's SHA-256. `tests/check-dell-provenance.py <path-to-zip>` verifies that the
active Send/SendText/SendEvent/Sleep sequence, values, and timings are unchanged.

The launcher owns Alt+O, Alt+T, and Alt+0 and dispatches fixed Script IDs to fixed
local worker paths. A worker accepts only an integer original-window handle.
It checks focus and the configured EHR title before each input action. A named
Windows mutex prevents overlapping managed macros. Escape exits only the running
worker. No patient field or clipboard values are logged.

`--self-test` records actions in memory without sending input, reading clipboard,
opening AdvancedMD, or creating the mutex. CI validates and dry-runs each worker;
this is not evidence of correctness against the live AdvancedMD layout.

Old/debug variants and `AdvancedMD_Profile` are intentionally not imported.
