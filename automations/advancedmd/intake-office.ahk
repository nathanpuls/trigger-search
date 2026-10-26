#Requires AutoHotkey v2.0
#SingleInstance Off
; Dell baseline: AutoHotkey.zip, intake-office.ahk. No Sheet code is executed.
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

    SafeSend "{Tab 11}{Right}{Left}" ; Informed consent
    SafeSleep 300

    SafeSend "{Tab 5}{Right}{Left}" ; Outcome measures reviewed
    SafeSleep 300

    SafeSend "{Tab 3}{Right}" ; Psychotherapy
    SafeSleep 300

    SafeSend "{Tab 3}{Right 2}" ; Medication side effects
    SafeSleep 300

    SafeSend "{Tab 1}{Right 2}" ; Medication Adherence
    SafeSleep 300

    SafeSend "+{Tab 28}{Enter}" ; Assessment/Plan
    SafeSleep 300

    SafeSend "{Tab 30}{Right}" ; Supervisory protocol
    SafeSleep 300

    SafeSend "{Tab 8}{Right}{Left}" ; Office visit
    SafeSleep 300

    SafeSend "{Tab 1}{Right 3}" ; E&M/Eval Only
    SafeSleep 300

    SafeSend "{Tab 6}{Space}" ; 99205
    SafeSleep 300

    SafeSend "{Tab 3}{Right}{Left}" ; Billing based on time
    SafeSleep 300

    SafeSend "{Tab 1}" ; Total time spent on Day of Encounter
    SafeSleep 300

    SafeSendEvent "60"
    SafeSleep 300

    SafeSend "+{Tab 52}{Enter}" ; Start
    SafeSleep 300
}
