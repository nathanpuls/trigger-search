# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Join Zoom
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📹

# Uses the same locally installed AutoHotkey action as Trigger Search.
# No personal meeting URL, WinAPI class, or separate resident script is needed.
$ErrorActionPreference = 'Stop'
$root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Trigger Search'
$command = Join-Path $root 'Join-Zoom.cmd'
if (-not (Test-Path -LiteralPath $command -PathType Leaf)) {
    throw 'Run Refresh all scripts in Trigger Search 0.16.13 or later first.'
}
Start-Process -FilePath $command -WindowStyle Hidden
