# Raycast

Keep Nathan's selected Raycast snippets/shortcuts, including `.SR`, until their
actual configuration is inspected. No Raycast export was present in the Dell ZIP.
Do not add another global launcher or change Wispr Flow bindings based only on
this source audit. No Raycast changes have been made in this Windows update.

For the Dell Windows **Join Zoom** command, use [join-zoom.ps1](join-zoom.ps1).
It calls the managed AutoHotkey action and contains no personal meeting link.

As of Trigger Search 0.16.16, remove the Dell Raycast **Alt+Z** assignment:
Trigger Search owns that direct shortcut. The wrapper can stay as an unbound
command, or be removed. Other Raycast snippets and bindings are unchanged.

The supplied End Zoom and Teams Call from Clipboard PowerShell scripts are
preserved in `originals/` as reference copies. Version 0.16.18 adds maintained
AutoHotkey equivalents to Trigger Search. Remove their Raycast Alt+1 / Alt+P
assignments before transferring ownership. Alt+1 force-closes Zoom; Zoom view
sizes are now Alt+2–6. Teams calling uses the original `tel:` routing and requires
Teams as the Windows TEL default.
