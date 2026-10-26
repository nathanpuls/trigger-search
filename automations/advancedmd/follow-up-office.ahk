#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
; Dell baseline: AutoHotkey.zip, follow-up-office.ahk. No Sheet code is executed.
; The managed launcher passes only the original window handle.
global TargetHwnd := 0
global DryRun := A_Args.Length = 1 && A_Args[1] = "--self-test"
global Steps := []

if DryRun {
    PerformWorkflow()
    if Steps.Length < 10
        ExitApp 1
    ExitApp 0
}
if A_Args.Length != 1 || !RegExMatch(A_Args[1], "^\d+$")
    ExitApp 2
TargetHwnd := Integer(A_Args[1])
; One clinical macro at a time, including across installed releases.
mutex := DllCall("CreateMutexW", "ptr", 0, "int", 1,
    "str", "Local\TriggerSearchAdvancedMD", "ptr")
lastError := A_LastError
if !mutex || lastError = 183 {
    if mutex
        DllCall("CloseHandle", "ptr", mutex)
    TrayTip "Another AdvancedMD automation is already running.", "Trigger Search"
    ExitApp 3
}
try {
    CheckTarget()
    PerformWorkflow()
} catch {
    ; Do not log clipboard, field values, or window titles.
    MsgBox "Automation stopped because its AdvancedMD window lost focus or was unavailable. Review the form before running it again.", "Trigger Search"
} finally {
    DllCall("CloseHandle", "ptr", mutex)
}
ExitApp

; Exists only for the lifetime of this deliberately invoked worker.
Esc::ExitApp

CheckTarget() {
    global TargetHwnd, DryRun
    if DryRun
        return
    expected := IniRead(A_AppData "\SheetAutocomplete\settings.ini", "advancedmd", "WindowTitle", "AdvancedMD")
    if expected = "" || !WinActive("ahk_id " TargetHwnd)
        || !InStr(WinGetTitle("ahk_id " TargetHwnd), expected)
        throw Error("Target unavailable")
}
SafeSend(value) {
    global DryRun, Steps
    CheckTarget()
    if DryRun
        Steps.Push(["Send", value])
    else
        Send value
}
SafeSendText(value) {
    global DryRun, Steps
    CheckTarget()
    if DryRun
        Steps.Push(["SendText", value])
    else
        SendText value
}
SafeSendEvent(value) {
    global DryRun, Steps
    CheckTarget()
    if DryRun
        Steps.Push(["SendEvent", value])
    else
        SendEvent value
}
SafeSleep(value) {
    global DryRun, Steps
    if DryRun
        Steps.Push(["Sleep", value])
    else
        Sleep value
}
PerformWorkflow() {
    SafeSend "{Tab 8}{Right}{Right}" ; Location Office
    SafeSleep 300

    SafeSend "{Tab 15}{Right}{Left}" ; Reviewed
    SafeSleep 300

    SafeSend "{Tab 3}{Right}" ; Psychotherapy
    SafeSleep 300

    SafeSend "+{Tab 24}{Enter}" ; MSE/Risk
    SafeSleep 300

    SafeSend "{Tab 5}{Right}{Left}" ; Patient Denies
    SafeSleep 300

    SafeSend "{Tab 28}" ; Mood
    SafeSleep 300

    SafeSendEvent "Euthymic"
    SafeSleep 500

    SafeSend "{Tab 4}" ; Affect
    SafeSleep 300

    SafeSendEvent "Appropriate"
    SafeSleep 500

    SafeSend "+{Tab 36}{Enter}" ; Assessment/Plan
    SafeSleep 300

    SafeSend "^f"
    SafeSleep 200
    SafeSendText "Followup Appointment"
    SafeSleep 200
    SafeSend "{Tab 3}"
    SafeSleep 200
    SafeSend "{Enter}"
    SafeSleep 200
    SafeSend "{Tab}"
    SafeSleep 200
    SafeSendEvent "See Scheduler or Timeline"
    SafeSleep 500

    SafeSend "{Tab 3}{Right}" ; Supervisory Protocol
    SafeSleep 500

    SafeSend "{Tab 8}{Right}{Left}" ; Office Visit
    SafeSleep 500

    SafeSend "{Tab 1}{Right 2}" ; E&M Only
    SafeSleep 500

    SafeSend "{Tab 4}{Space}" ; 99214
    SafeSleep 500

    SafeSend "{Tab 3}{Right}" ; Complexity-Based Billing

    SafeSend "+{Tab 11}{Space}" ; Fill From Problem List

    SafeSend "+{Tab 36}{Enter}" ; PFSH
    SafeSleep 1500

    SafeSend "{Tab 11}{Right}{Left}" ; Medical History: Adult

    SafeSend "+{Tab 9}{Enter}" ; Assessment / Plans
    SafeSleep 1500
}
