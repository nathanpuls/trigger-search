# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Teams Call from Clipboard
# @raycast.mode silent
# @raycast.packageName LifeStance
# @raycast.icon 📞
# Original supplied by Nathan; reference only, not installed or run by Trigger Search.
# Teams must be the Windows default app for TEL links.
$clipboardContent = Get-Clipboard
$cleanNumber = $clipboardContent -replace '\D', ''
if ($cleanNumber -match '^\d{10,15}$') {
    Start-Process "tel:$cleanNumber"
} else {
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.Interaction]::MsgBox("No valid phone number found in clipboard.", "OKOnly", "Raycast Error")
}
