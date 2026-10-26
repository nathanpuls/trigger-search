# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title End Zoom
# @raycast.mode silent
# @raycast.icon 🏎️
# Original supplied by Nathan; reference only, not installed or run by Trigger Search.
# WARNING: force-closes every process whose name contains Zoom, ending active calls.
Get-Process | Where-Object { $_.ProcessName -like "*Zoom*" } | Stop-Process -Force
