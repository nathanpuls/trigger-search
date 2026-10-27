#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
SendMode "Input"
SetTitleMatchMode 2
global DryRun := A_Args.Length = 1 && (A_Args[1] = "--self-test" || A_Args[1] = "--integration-test")
global IntegrationTest := A_Args.Length = 1 && A_Args[1] = "--integration-test"
global TargetHwnd := 0
global Steps := []
global WorkspaceMask := 31
global WorkspaceTestCalls := []
global HelperActions := Map(
    "initials", Initials, "charge-slip", ChargeSlip, "timestamp", Timestamp,
    "mse", Mse, "mse-fast", MseFast, "follow-up-mse", FollowUpMse,
    "sid", Sid, "plan-navigation", PlanNavigation, "mse-navigation", MseNavigation,
    "hpi", Hpi, "launch-advancedmd", LaunchAdvancedMD, "morning-startup", MorningStartup,
    "blueprint", Blueprint, "it-ticket", ItTicket, "schedule-email", ScheduleEmail,
    "copilot", Copilot, "espanso", Espanso, "copy-back", CopyBack, "join-zoom", JoinZoom,
    "end-zoom", EndZoom, "teams-call-clipboard", TeamsCallClipboard,
    "workspace-start", StartDayWorkspace, "open-teams", OpenTeams, "close-apps", CloseApplications)
if DryRun {
    TestZoomPlacement()
    TestWorkspaceBounds(IntegrationTest)
    TestCloseApplicationPolicy()
    if IntegrationTest
        TestCloseApplicationsUI()
    TestGeneralChromeSelection()
    TestWorkspaceAutomation()
    TestClipboardPhoneNumber()
    if !IsAdvancedMDEhrTitle("AdvancedMD-EHR - Google Chrome")
        || !IsAdvancedMDEhrTitle("AdvancedMD - EHR")
        || !IsAdvancedMDEhrTitle("advancedmd – ehr")
        || IsAdvancedMDEhrTitle("Login | AdvancedMD")
        || IsAdvancedMDEhrTitle("General Chrome")
        ExitApp 1
    if RequiresOriginWindow("launch-advancedmd") || !RequiresOriginWindow("mse")
        ExitApp 1
    left := LeftmostDisplay([{Left: 1920, Top: 0, Right: 3840, Bottom: 1080},
        {Left: 0, Top: 0, Right: 1920, Bottom: 1080}])
    if left.Left != 0
        ExitApp 1
    left := LeftmostDisplay([{Left: 0, Top: 0, Right: 1920, Bottom: 1080},
        {Left: -1920, Top: 0, Right: 0, Bottom: 1080}])
    if left.Left != -1920
        ExitApp 1
    for action, fn in HelperActions {
        Steps := []
        fn.Call()
        if Steps.Length = 0
            ExitApp 1
        if action = "launch-advancedmd" && (Steps[2][1] != "SendEvent"
            || Steps[2][2] != "136732" || Steps[3][2] != "{Enter}")
            ExitApp 1
    }
    ExitApp 0
}
if A_Args.Length < 2 || !RegExMatch(A_Args[1], "^\d+$") || !HelperActions.Has(A_Args[2])
    ExitApp 2
if A_Args[2] = "workspace-start" {
    if A_Args.Length != 3 || !RegExMatch(A_Args[3], "^\d{1,2}$") || Integer(A_Args[3]) > 31
        ExitApp 2
    WorkspaceMask := Integer(A_Args[3])
} else if A_Args.Length != 2
    ExitApp 2
TargetHwnd := Integer(A_Args[1])
mutex := DllCall("CreateMutexW", "ptr", 0, "int", 1,
    "str", HelperMutexName(A_Args[2]), "ptr")
if !mutex || A_LastError = 183 {
    if mutex
        DllCall("CloseHandle", "ptr", mutex)
    TrayTip A_Args[2] = "workspace-start" ? "Start my day is already running." : "Another automation is running.", "Trigger Search"
    ExitApp 3
}
try {
    if RequiresOriginWindow(A_Args[2])
        CheckTarget()
    HelperActions[A_Args[2]].Call()
} catch as problem {
    ; Fixed error messages only; no window titles or clipboard contents are logged.
    MsgBox problem.Message, "Trigger Search 0.16.25 — " A_Args[2]
} finally {
    DllCall("CloseHandle", "ptr", mutex)
}
ExitApp
#HotIf !DryRun
Esc::ExitApp
#HotIf

CheckTarget() {
    global DryRun, TargetHwnd
    if !DryRun && (!TargetHwnd || !WinActive("ahk_id " TargetHwnd))
        throw Error("Automation stopped because its target window lost focus. Review the form before retrying.")
}
RequireEhr() {
    global DryRun, TargetHwnd
    CheckTarget()
    if DryRun
        return
    title := IniRead(A_AppData "\SheetAutocomplete\settings.ini", "advancedmd", "WindowTitle", "AdvancedMD")
    if title = "" || !InStr(WinGetTitle("ahk_id " TargetHwnd), title)
        throw Error("Activate the AdvancedMD form before running this action.")
}
S(value, mode := "Send") {
    global DryRun, Steps
    CheckTarget()
    if DryRun {
        Steps.Push([mode, value])
        return
    }
    if mode = "SendText"
        SendText value
    else if mode = "SendEvent"
        SendEvent value
    else
        Send value
}
PauseFor(value) {
    global DryRun
    if !DryRun
        Sleep value
}
ClickAt(x, y, mode := "Client") {
    global DryRun, Steps
    CheckTarget()
    if DryRun {
        Steps.Push(["Click", x, y])
        return
    }
    CoordMode "Mouse", mode
    Click x, y
}
OpenUrl(url, title := "", chrome := false) {
    global DryRun, Steps, TargetHwnd
    if DryRun {
        Steps.Push(["Open", url])
        return
    }
    Run chrome ? 'chrome.exe "' url '"' : url
    if title != "" {
        if !WinWait(title, , 20)
            throw Error("The requested application did not open.")
        WinActivate title
        if !WinWaitActive(title, , 5)
            throw Error("Could not activate the requested application.")
        TargetHwnd := WinExist("A")
    }
}
ConfigValue(key, prompt) {
    global DryRun
    if DryRun
        return "TEST"
    path := A_AppData "\SheetAutocomplete\settings.ini"
    value := IniRead(path, "workflow-config", key, "")
    if value = "" {
        result := InputBox(prompt "`nSaved only on this Dell.", "Trigger Search setup")
        if result.Result != "OK" || Trim(result.Value) = ""
            throw Error("Setup cancelled. No workflow was run.")
        value := result.Value
        IniWrite value, path, "workflow-config", key
    }
    return value
}
Initials() {
    S "nat"
    S "{Enter}"
}
ChargeSlip() {
    RequireEhr()
    S "{Tab 11}"
    PauseFor 300
    S "{Enter}"
    PauseFor 300
    S "nat"
    PauseFor 300
    S "{Tab 2}"
    PauseFor 300
    S "{Enter}"
}
Timestamp() {
    S "{Enter 2}"
    PauseFor 80
    S "{Up 2}"
    PauseFor 80
    S FormatTime(, "dd MMM yyyy")
    S "{Enter}"
}
MseEntries() {
    return ["Euthymic", "Appropriate", "Well-groomed, neat", "Normal, steady",
        "Alert and oriented x4", "Normal rate, volume, and rhythm", "Fluent, intact",
        "Intact", "Linear, logical, goal-oriented", "Grossly intact", "None endorsed",
        "Average, consistent with educational level", "Sufficient for conversation", "Fair to Good"]
}
Mse() {
    RequireEhr()
    entries := MseEntries()
    for index, text in entries {
        S text, "SendEvent"
        if index < entries.Length {
            PauseFor 150
            S "{Tab 2}", "SendEvent"
            PauseFor 150
        }
    }
}
MseFast() {
    RequireEhr()
    entries := MseEntries()
    for index, text in entries
        S text (index < entries.Length ? "{Tab 2}" : ""), "SendEvent"
}
FollowUpMse() {
    RequireEhr()
    S "Euthymic", "SendText"
    PauseFor 150
    S "{Tab 4}"
    PauseFor 150
    S "Appropriate", "SendText"
}
Sid() {
    RequireEhr()
    S "{Tab 21}"
    PauseFor 150
    S "{Enter}"
    PauseFor 150
    S "{Tab 9}"
    PauseFor 150
    S "SID", "SendText"
    PauseFor 150
    S "{Up}"
    PauseFor 100
    S "{Enter}"
}
PlanNavigation() {
    RequireEhr()
    S "{Tab 17}"
    PauseFor 100
    S "^{Home}"
}
MseNavigation() {
    RequireEhr()
    ClickAt 100, 150
    PauseFor 500
    Loop 31 {
        S "{Tab}", "SendEvent"
        PauseFor 150
    }
    PauseFor 300
    S "euthymic"
}
Hpi() {
    RequireEhr()
    ClickAt 0, 0
    ClickAt 506, 367
}
LaunchAdvancedMD() {
    key := "136732"
    global DryRun, TargetHwnd
    ; Focus and place an open EHR without typing an office key or repeating login.
    if !DryRun && (ehr := ExistingAdvancedMDEhrWindow()) {
        WinActivate ehr
        if !WinWaitActive(ehr, , 5)
            throw Error("Could not activate the existing AdvancedMD EHR window.")
        TargetHwnd := ehr
        PositionAdvancedMD()
        return
    }
    if !DryRun && (login := WinExist("Login | AdvancedMD ahk_exe chrome.exe")) {
        WinActivate "ahk_id " login
        if !WinWaitActive("ahk_id " login, , 10)
            throw Error("Could not activate the AdvancedMD login window.")
        TargetHwnd := login
    } else
        OpenUrl "https://login.advancedmd.com/?sso=1", "Login | AdvancedMD", true
    PauseFor 1800
    SendAMDLogin key, "SendEvent"
    PauseFor 300
    SendAMDLogin "{Enter}"
    PauseFor 10000
    AdoptActiveAdvancedMDWindow()
    PositionAdvancedMD()
}
IsAdvancedMDEhrTitle(title) {
    return !!RegExMatch(title, "i)AdvancedMD\s*[-–—]?\s*EHR\b")
}
ExistingAdvancedMDEhrWindow() {
    ; Only an actual EHR title counts; a login page still needs the login flow.
    for hwnd in WinGetList("ahk_exe chrome.exe") {
        try {
            if IsAdvancedMDEhrTitle(WinGetTitle(hwnd))
                return hwnd
        }
    }
    return 0
}
SendAMDLogin(value, mode := "Send") {
    global DryRun, TargetHwnd, Steps
    if DryRun {
        Steps.Push([mode, value])
        return
    }
    ; Login is a self-opening action, not a macro bound to the launcher's old HWND.
    ; Reacquire the exact login window before each input as Chrome settles.
    login := WinExist("Login | AdvancedMD ahk_exe chrome.exe")
    if !login
        throw Error("Open AMD could not find its login window before input.")
    TargetHwnd := login
    WinActivate "ahk_id " login
    if !WinWaitActive("ahk_id " login, , 5)
        throw Error("Open AMD could not activate its login window before input.")
    if mode = "SendEvent"
        SendEvent value
    else
        Send value
}

MorningStartup() {
    key := "136732"
    OpenUrl "https://login.advancedmd.com/?sso=1", "AdvancedMD", true
    global DryRun
    if !DryRun
        WinRestore "A"
    PauseFor 500
    S key, "SendText"
    S "{Enter}"
    PauseFor 5000
    CheckTarget()
    if !DryRun
        WinMaximize "A"
}
Blueprint() {
    OpenUrl "https://clinician.blueprint.ai/sessions", "Blueprint"
    PauseFor 4000
    S "{Tab 2}"
    PauseFor 300
    S "{Enter}"
    PauseFor 1000
    S "^v"
    PauseFor 1000
    S "{Down}"
    PauseFor 300
    S "{Enter}"
    PauseFor 1000
    S "{Tab 4}"
    PauseFor 500
    S "{Enter}"
    PauseFor 500
    S "{Enter}"
}
ItTicket() {
    key := ConfigValue("TicketOfficeKey", "Enter the office key label used on IT tickets.")
    OpenUrl "https://sdpondemand.manageengine.com/app/itdesk/ui/requests/add?reqTemplate=151650000001347089", "ManageEngine"
    PauseFor 4000
    S "{Tab 6}"
    PauseFor 600
    S "^a{Backspace}IT Help"
    PauseFor 600
    S "{Tab}"
    S "AdvancedMD"
    PauseFor 1000
    S "{Enter}"
    PauseFor 500
    S "{Tab}"
    S "EHR"
    PauseFor 1000
    S "{Enter}"
    PauseFor 500
    S "{Tab 3}"
    S key, "SendText"
    PauseFor 1000
    S "{Enter}"
    PauseFor 500
    S "{Esc}"
    PauseFor 300
    S "{Tab}"
    PauseFor 500
    S "Central"
    PauseFor 1200
    S "{Down}{Enter}"
    S "{Tab 2}"
    PauseFor 100
    S "+{Tab}"
}
ScheduleEmail() {
    global DryRun
    if !DryRun && !DllCall("IsClipboardFormatAvailable", "UInt", 2)
        throw Error("No clipboard image is available. Take the schedule snip first.")
    recipient := ConfigValue("ScheduleRecipients", "Enter schedule email recipients, separated by commas.")
    OpenUrl "https://mail.google.com/mail/u/0/#inbox", "Gmail", true
    PauseFor 5000
    ClickAt 2050, 170, "Screen"
    PauseFor 3000
    ClickAt 2550, 405, "Screen"
    PauseFor 800
    S recipient, "SendText"
    PauseFor 1000
    S "{Tab 2}"
    PauseFor 700
    S "Next Day of Work", "SendText"
    PauseFor 1000
    S "{Tab}"
    PauseFor 1200
    S "^v"
    ; Compose only. The original script does not send the message.
}
Espanso() {
    S "^{Space}"
}
CopyBack() {
    global DryRun, TargetHwnd
    S "^a"
    PauseFor 100
    S "^c"
    if !DryRun {
        if !ClipWait(1)
            throw Error("Copy did not complete.")
    }
    S "!{Tab}"
    PauseFor 600
    if !DryRun
        TargetHwnd := WinExist("A")
    S "/"
    PauseFor 100
    S "{Backspace}"
    PauseFor 150
    S "^v"
}

LeftmostDisplay(areas) {
    destination := areas[1]
    for area in areas {
        if area.Left < destination.Left
            destination := area
    }
    return destination
}

RightmostDisplay(areas) {
    destination := areas[1]
    for area in areas
        if area.Left > destination.Left
            destination := area
    return destination
}
DisplayWorkAreas() {
    areas := []
    Loop MonitorGetCount() {
        MonitorGetWorkArea A_Index, &left, &top, &right, &bottom
        areas.Push({Left: left, Top: top, Right: right, Bottom: bottom})
    }
    return areas
}
HalfDisplayBounds(area, side) {
    ; Use work areas, not monitor numbers or primary-display assumptions.
    leftWidth := Floor((area.Right - area.Left) / 2)
    x := side = "left" ? area.Left : area.Left + leftWidth
    return {X: x, Y: area.Top,
        Width: side = "left" ? leftWidth : area.Right - x,
        Height: area.Bottom - area.Top}
}
PlaceWindowInBounds(hwnd, bounds) {
    if !WinExist(hwnd)
        throw Error("The application window is no longer available for placement.")
    if !DllCall("IsWindowVisible", "ptr", hwnd)
        WinShow hwnd
    if WinGetMinMax(hwnd) != 0
        WinRestore hwnd
    Sleep 120
    WinMove bounds.X, bounds.Y, bounds.Width, bounds.Height, hwnd
    ; A cross-monitor DPI change may resize the window once during transfer.
    ; Apply the same rectangle again after that change settles; no polling loop.
    Sleep 150
    WinMove bounds.X, bounds.Y, bounds.Width, bounds.Height, hwnd
}
PositionAdvancedMD() {
    global DryRun, Steps, TargetHwnd
    if DryRun {
        Steps.Push(["PlaceAdvancedMD", "right display, left half"])
        return
    }
    RequireAMDWindowExists()
    area := RightmostDisplay(DisplayWorkAreas())
    PlaceWindowInBounds TargetHwnd, HalfDisplayBounds(area, "left")
}
TestWorkspaceBounds(includeGui := false) {
    areas := [{Left: 0, Top: 40, Right: 2560, Bottom: 1400},
        {Left: -1920, Top: -100, Right: 0, Bottom: 940}]
    amd := HalfDisplayBounds(RightmostDisplay(areas), "left")
    zoom := HalfDisplayBounds(LeftmostDisplay(areas), "right")
    if amd.X != 0 || amd.Y != 40 || amd.Width != 1280 || amd.Height != 1360
        throw Error("AMD must occupy the left half of the rightmost work area.")
    if zoom.X != -960 || zoom.Y != -100 || zoom.Width != 960 || zoom.Height != 1040
        throw Error("Zoom must occupy the right half of the leftmost work area.")
    odd := {Left: -1001, Top: 0, Right: 0, Bottom: 800}
    left := HalfDisplayBounds(odd, "left"), right := HalfDisplayBounds(odd, "right")
    if left.Width + right.Width != 1001 || left.X + left.Width != right.X
        || right.X + right.Width != odd.Right
        throw Error("Odd monitor widths must leave no gap or lost pixel.")
    single := [{Left: 0, Top: 0, Right: 1920, Bottom: 1040}]
    if LeftmostDisplay(single) != RightmostDisplay(single)
        throw Error("A single display must safely provide both halves.")
    if !includeGui
        return
    ; A synthetic native window tests restore/placement without opening an app.
    fixture := Gui("+Resize", "Workspace geometry fixture")
    try {
        fixture.Show("w300 h200 NoActivate")
        MonitorGetWorkArea MonitorGetPrimary(), &l, &t, &r, &b
        bounds := HalfDisplayBounds({Left: l, Top: t, Right: r, Bottom: b}, "left")
        WinMaximize fixture.Hwnd
        PlaceWindowInBounds fixture.Hwnd, bounds
        WinGetPos &x, &y, &w, &h, fixture.Hwnd
        if WinGetMinMax(fixture.Hwnd) != 0 || x != bounds.X || y != bounds.Y
            || w != bounds.Width || h != bounds.Height
            throw Error("Native half-window placement must restore maximized windows and apply exact bounds.")
    } finally {
        fixture.Destroy()
    }
}

AdoptActiveAdvancedMDWindow() {
    global DryRun, TargetHwnd
    if DryRun
        return
    ; Login can redirect or open a popup. Prefer an identified active AMD window,
    ; then the original window, then an identified AMD Chrome window in Z-order.
    ; The screen move targets its HWND and does not need to steal keyboard focus.
    active := WinExist("A")
    if IsAdvancedMDWindow(active) {
        TargetHwnd := active
        return
    }
    if IsAdvancedMDWindow(TargetHwnd)
        return
    for hwnd in WinGetList("ahk_exe chrome.exe") {
        if IsAdvancedMDWindow(hwnd) {
            TargetHwnd := hwnd
            return
        }
    }
    throw Error("The AdvancedMD window could not be found after login.")
}

IsAdvancedMDWindow(hwnd) {
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false
    expected := IniRead(A_AppData "\SheetAutocomplete\settings.ini", "advancedmd", "WindowTitle", "AdvancedMD")
    try return expected != "" && WinGetProcessName("ahk_id " hwnd) = "chrome.exe"
        && InStr(WinGetTitle("ahk_id " hwnd), expected)
    catch
        return false
}

RequireAMDWindowExists() {
    global TargetHwnd
    if !IsAdvancedMDWindow(TargetHwnd)
        throw Error("The AdvancedMD window is no longer available for the screen move.")
}

RequiresOriginWindow(action) {
    ; Opening AMD activates its own identified login window. The launcher may
    ; have started it from any application. Form-filling actions retain focus checks.
    return action != "launch-advancedmd" && action != "join-zoom"
        && action != "copilot" && action != "open-teams" && action != "workspace-start" && action != "close-apps"
        && action != "end-zoom" && action != "teams-call-clipboard"
}

JoinZoom(allowSetup := true) {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["Zoom", "JoinAndPosition"])
        return
    }
    ; Do not terminate a live call just to resize it or start another meeting.
    meeting := FindZoomMeeting()
    if meeting {
        ; Alt+Z reapplies the chosen desk layout to an existing regular meeting.
        PositionZoomMeeting meeting
        return
    }
    url := LocalZoomMeetingUrl(allowSetup)
    Run url
    deadline := A_TickCount + 60000
    while A_TickCount < deadline {
        meeting := FindZoomMeeting()
        if meeting {
            PositionZoomMeeting meeting
            ; Close only identified home windows after the meeting exists.
            for hwnd in WinGetList("ahk_exe Zoom.exe") {
                if hwnd != meeting && RegExMatch(WinGetTitle("ahk_id " hwnd), "i)^(Zoom Workplace|Zoom Cloud Meetings)$")
                    try WinClose "ahk_id " hwnd
            }
            return
        }
        Sleep 300
    }
    throw Error("Zoom meeting window was not found within 60 seconds. Complete any browser Open Zoom or join prompt, then run Join Zoom again.")
}
LocalZoomMeetingUrl(allowSetup := true) {
    path := A_AppData "\SheetAutocomplete\settings.ini"
    value := Trim(IniRead(path, "workflow-config", "ZoomMeetingUrl", ""))
    if ValidZoomMeetingUrl(value)
        return value
    if !allowSetup
        throw Error("Configure the Zoom meeting link with Alt+Z before using Start my day.")
    result := InputBox("Paste your Zoom personal meeting link. It is saved only on this Dell, outside GitHub and the Sheet.",
        "Join Zoom - one-time setup", "w600 h160", value)
    if result.Result != "OK"
        throw Error("Zoom setup cancelled. No meeting was opened.")
    value := Trim(result.Value)
    if !ValidZoomMeetingUrl(value)
        throw Error("Use an HTTPS zoom.us /my/, /s/, or /j/ meeting link. Run Join Zoom again to correct it.")
    IniWrite value, path, "workflow-config", "ZoomMeetingUrl"
    return value
}
ValidZoomMeetingUrl(url) {
    return RegExMatch(url, 'i)^https://(?:[a-z0-9-]+\.)?zoom\.us/(?:[js]/[0-9]+|my/[a-z0-9._-]+)/?(?:\?[^" <>\r\n]*)?$') != 0
}
ZoomMeetingCandidate(title, className) {
    return className = "ZPContentViewWndClass" || RegExMatch(title, "i)Zoom (Meeting|Webinar)") != 0
}
FindZoomMeeting() {
    ; Zoom can hide the main meeting while its floating thumbnail is visible.
    ; Include that hidden main window so a refresh never starts a second call.
    previous := DetectHiddenWindows(true)
    try {
        for hwnd in WinGetList("ahk_exe Zoom.exe") {
            try {
                if ZoomMeetingCandidate(WinGetTitle(hwnd), WinGetClass(hwnd))
                    return hwnd
            }
        }
    } finally {
        DetectHiddenWindows previous
    }
    return 0
}
PositionZoomMeeting(hwnd) {
    if !WinExist(hwnd) || WinGetProcessName(hwnd) != "Zoom.exe"
        throw Error("The Zoom meeting window is no longer available.")
    area := LeftmostDisplay(DisplayWorkAreas())
    PlaceWindowInBounds hwnd, HalfDisplayBounds(area, "right")
    WinActivate hwnd
}
TestZoomPlacement() {
    if RequiresOriginWindow("join-zoom")
        throw Error("Join Zoom must not depend on the launcher's previous window.")
    if ZoomMeetingCandidate("Zoom Workplace", "HomeWindow") || !ZoomMeetingCandidate("Zoom Meeting", "MeetingWindow")
        throw Error("Zoom home must not be selected as the meeting window.")
    if !ValidZoomMeetingUrl("https://example.zoom.us/j/1234567890")
        || !ValidZoomMeetingUrl("https://example.zoom.us/my/example.user")
        || !ValidZoomMeetingUrl("https://zoom.us/my/example.user/?pwd=example")
        || ValidZoomMeetingUrl("https://example.com/j/123")
        || ValidZoomMeetingUrl("https://zoom.us.example.com/my/example.user")
        throw Error("Only Zoom meeting links may be launched.")
}


EndZoom() {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["Close", "Zoom.exe only"])
        return
    }
    ; Preserve Nathan's original force-close behavior, but never the broad
    ; *Zoom* wildcard. Verify executable name on the SAME process handle used
    ; for termination so PID reuse cannot target an unrelated application.
    failures := 0
    service := ComObjGet("winmgmts:")
    for process in service.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='Zoom.exe'") {
        handle := DllCall("OpenProcess", "uint", 0x1001, "int", 0, "uint", process.ProcessId, "ptr")
        if !handle {
            if ProcessExist(process.ProcessId)
                failures += 1
            continue
        }
        try {
            capacity := 32768
            path := Buffer(capacity * 2)
            if !DllCall("QueryFullProcessImageNameW", "ptr", handle, "uint", 0, "ptr", path, "uint*", &capacity)
                failures += 1
            else if RegExMatch(StrGet(path, capacity, "UTF-16"), "i)\\Zoom\.exe$") {
                if !DllCall("TerminateProcess", "ptr", handle, "uint", 0)
                    failures += 1
            }
        } finally {
            DllCall("CloseHandle", "ptr", handle)
        }
    }
    if failures
        throw Error("Some Zoom processes could not be closed. Close Zoom normally; no other applications were stopped.")
}
ClipboardPhoneNumber(text) {
    ; Accept one phone number, not a note containing several numbers. Preserve
    ; the original script's 10-15 digit range and tel: default-app routing.
    text := Trim(text)
    if !RegExMatch(text, "^\+?[0-9() .-]+$")
        return ""
    digits := RegExReplace(text, "\D")
    return RegExMatch(digits, "^[0-9]{10,15}$") ? digits : ""
}
TeamsCallClipboard() {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["Dial", "tel: validated clipboard number"])
        return
    }
    number := ClipboardPhoneNumber(A_Clipboard)
    if number = ""
        throw Error("Copy one phone number first (10-15 digits). Letters, extensions, and multiple numbers are not accepted.")
    ; Teams must be the Dell's default TEL handler, matching the working Raycast
    ; script. Do not log or save the clipboard or number, or launch a browser URL.
    Run "tel:" number
}
TestClipboardPhoneNumber() {
    if ClipboardPhoneNumber("(202) 555-0123") != "2025550123"
        || ClipboardPhoneNumber("+44 20 7946 0123") != "442079460123"
        || ClipboardPhoneNumber("123") != ""
        || ClipboardPhoneNumber("2025550123 2025550124") != ""
        || ClipboardPhoneNumber("Call patient 2025550123") != ""
        || ClipboardPhoneNumber("2025550123 ext 42") != ""
        throw Error("Clipboard calling must accept a single formatted number and reject notes, extensions, or multiple numbers.")
}

; Start my day reuses the individual app actions in a single temporary worker.
; The bitmask contains fixed local action flags, never executable Sheet content.
WorkspaceSteps() {
    return [
        {Id: "dell.launch-advancedmd", Name: "AdvancedMD", Flag: 1, Run: LaunchAdvancedMD},
        {Id: "dell.copilot", Name: "Copilot", Flag: 4, Run: Copilot.Bind(true)},
        {Id: "teams.open", Name: "Teams", Flag: 16, Run: OpenTeams.Bind(true)},
        {Id: "chrome.general", Name: "Chrome", Flag: 8, Run: WorkspaceChrome},
        {Id: "zoom.join", Name: "Zoom", Flag: 2, Run: JoinZoom.Bind(false)}
    ]
}
ExecuteWorkspaceSteps(mask, runner := 0) {
    results := {Completed: [], Failed: [], Skipped: []}
    for step in WorkspaceSteps() {
        if !(mask & step.Flag) {
            results.Skipped.Push(step.Name)
            continue
        }
        try {
            if runner
                runner.Call(step)
            else
                RunWorkspaceStep(step)
            results.Completed.Push(step.Name)
        } catch {
            ; Fixed application names only. Never log titles, URLs, credentials,
            ; clipboard contents or an exception that could contain private data.
            results.Failed.Push(step.Name)
        }
    }
    return results
}
RunWorkspaceStep(step) {
    global DryRun
    guard := 0, owned := false
    try {
        ; Take the clinical lock only during the AMD stage, so morning setup
        ; cannot overlap an active form macro and does not hold that lock for Zoom.
        if !DryRun && step.Id = "dell.launch-advancedmd" {
            guard := DllCall("CreateMutexW", "ptr", 0, "int", 1,
                "str", "Local\TriggerSearchAdvancedMD", "ptr")
            if !guard || A_LastError = 183
                throw Error("AdvancedMD is busy.")
            owned := true
        }
        step.Run.Call()
    } finally {
        if guard {
            if owned
                DllCall("ReleaseMutex", "ptr", guard)
            DllCall("CloseHandle", "ptr", guard)
        }
    }
}
StartDayWorkspace() {
    global WorkspaceMask, DryRun
    results := ExecuteWorkspaceSteps(WorkspaceMask)
    if DryRun
        return
    if !WorkspaceMask {
        TrayTip "No workspace applications are enabled in Automations.", "Trigger Search"
        return
    }
    message := "Workspace setup finished."
    if results.Failed.Length {
        names := ""
        for name in results.Failed
            names .= (names = "" ? "" : ", ") name
        message .= " Needs attention: " names ". Complete sign-in/join prompts, then retry Alt+L."
    } else
        message .= " Check any sign-in or Zoom join prompts."
    TrayTip message, "Trigger Search"
}
WorkspaceChrome() {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["PlaceChrome", "right monitor, top-right quarter"])
        return
    }
    hwnd := FocusGeneralChrome(true)
    if !hwnd || !ChromeIsBrowsingHwnd(hwnd)
        throw Error("A general Chrome window was unavailable.")
    area := RightmostDisplay(DisplayWorkAreas())
    PlaceWindowInBounds hwnd, WorkspaceQuarterBounds(area, "top")
    WinActivate hwnd
}
WorkspaceQuarterBounds(area, side) {
    half := HalfDisplayBounds(area, "right")
    topHeight := Floor(half.Height / 2)
    y := side = "top" ? half.Y : half.Y + topHeight
    return {X: half.X, Y: y, Width: half.Width,
        Height: side = "top" ? topHeight : area.Bottom - y}
}
WorkspaceAppCandidate(application, process, title, style, owner, extendedStyle := 0) {
    if owner || (extendedStyle & 0x80) || !(style & 0x00040000) || !(style & 0x00080000)
        return false
    process := StrLower(process)
    if application = "copilot" {
        allowed := Map("chrome.exe", true, "msedge.exe", true, "msedgewebview2.exe", true,
            "copilot.exe", true, "m365copilot.exe", true, "microsoft.copilot.exe", true,
            "applicationframehost.exe", true)
        return allowed.Has(process) && !!RegExMatch(title, "i)\bCopilot\b")
            && !ChromeIsEhrTitle(title)
            && !RegExMatch(title, "i)(sharing (?:your |the )?(screen|window|tab|audio)|screen sharing)")
    }
    return application = "teams" && (process = "ms-teams.exe" || process = "teams.exe")
        && !!RegExMatch(title, "i)\bMicrosoft Teams\b")
        && !RegExMatch(title, "i)\b(?:meeting|call in progress|incoming call)\b")
}
FindWorkspaceApp(application) {
    processes := application = "copilot"
        ? ["M365Copilot.exe", "Microsoft.Copilot.exe", "Copilot.exe", "ApplicationFrameHost.exe",
            "chrome.exe", "msedge.exe", "msedgewebview2.exe"]
        : ["ms-teams.exe", "Teams.exe"]
    for process in processes {
        for hwnd in WinGetList("ahk_exe " process) {
            try {
                if WorkspaceAppCandidate(application, process, WinGetTitle(hwnd), WinGetStyle(hwnd),
                    DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr"), WinGetExStyle(hwnd))
                    return hwnd
            }
        }
    }
    return 0
}
WaitWorkspaceApp(application, seconds := 15) {
    deadline := A_TickCount + seconds * 1000
    while A_TickCount < deadline {
        if hwnd := FindWorkspaceApp(application)
            return hwnd
        Sleep 250
    }
    throw Error("The application needs sign-in or did not expose its main window in time.")
}
Copilot(arrange := false) {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["Copilot", arrange ? "left monitor, left half" : "focus or open"])
        return
    }
    hwnd := FindWorkspaceApp("copilot")
    if !hwnd {
        ; Use the existing business Copilot URL, not a consumer account or a
        ; new installation. App mode gives it a separate, reusable Chrome window.
        Run 'chrome.exe --app="https://m365.cloud.microsoft/chat"'
        hwnd := WaitWorkspaceApp("copilot")
    }
    if arrange
        PlaceWindowInBounds hwnd, HalfDisplayBounds(LeftmostDisplay(DisplayWorkAreas()), "left")
    WinActivate hwnd
}
OpenTeams(arrange := false) {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["Teams", arrange ? "right monitor, bottom-right quarter" : "focus or open"])
        return
    }
    hwnd := FindWorkspaceApp("teams")
    if !hwnd {
        ; Windows resolves the installed Teams desktop app; do not hard-code a
        ; versioned WindowsApps path or initiate a call/meeting.
        Run "msteams:"
        hwnd := WaitWorkspaceApp("teams")
    }
    if arrange
        PlaceWindowInBounds hwnd, WorkspaceQuarterBounds(RightmostDisplay(DisplayWorkAreas()), "bottom")
    WinActivate hwnd
}
HelperMutexName(action) {
    if action = "workspace-start"
        return "Local\TriggerSearchWorkspace"
    if action = "close-apps"
        return "Local\TriggerSearchCloseApps"
    if action = "copilot" || action = "open-teams" || action = "join-zoom"
        return "Local\TriggerSearchApp-" action
    return "Local\TriggerSearchAdvancedMD"
}
TestWorkspaceAutomation() {
    global WorkspaceTestCalls
    WorkspaceTestCalls := []
    result := ExecuteWorkspaceSteps(31, WorkspaceFixtureStep)
    Assert WorkspaceTestCalls.Length = 5 && WorkspaceTestCalls[1] = "AdvancedMD"
        && WorkspaceTestCalls[5] = "Zoom" && result.Completed.Length = 4
        && result.Failed.Length = 1 && result.Failed[1] = "Copilot",
        "A failed stage must not prevent later applications from opening; Zoom runs last."
    WorkspaceTestCalls := []
    result := ExecuteWorkspaceSteps(1 | 8, WorkspaceFixtureStep)
    Assert WorkspaceTestCalls.Length = 2 && WorkspaceTestCalls[1] = "AdvancedMD"
        && WorkspaceTestCalls[2] = "Chrome" && result.Skipped.Length = 3,
        "Disabled application flags must be skipped without running their code."
    result := ExecuteWorkspaceSteps(0, WorkspaceFixtureStep)
    Assert result.Completed.Length = 0 && result.Failed.Length = 0 && result.Skipped.Length = 5,
        "A workspace with all applications disabled must launch nothing."
    area := {Left: 0, Top: 40, Right: 2561, Bottom: 1401}
    chrome := WorkspaceQuarterBounds(area, "top"), teams := WorkspaceQuarterBounds(area, "bottom")
    Assert chrome.X = 1280 && chrome.Width = 1281 && chrome.Y = 40
        && chrome.Height = 680 && teams.Y = 720 && teams.Height = 681,
        "Chrome and Teams must partition the right half, including taskbars and odd dimensions."
    style := 0x00CF0000
    Assert WorkspaceAppCandidate("copilot", "chrome.exe", "Microsoft 365 Copilot", style, 0)
        && WorkspaceAppCandidate("teams", "ms-teams.exe", "Chat | Microsoft Teams", style, 0),
        "Recognized main Copilot/Teams windows must be reusable."
    Assert !WorkspaceAppCandidate("copilot", "chrome.exe", "AdvancedMD - EHR", style, 0)
        && !WorkspaceAppCandidate("copilot", "notepad.exe", "Copilot", style, 0)
        && !WorkspaceAppCandidate("teams", "chrome.exe", "Microsoft Teams", style, 0)
        && !WorkspaceAppCandidate("teams", "ms-teams.exe", "Incoming call | Microsoft Teams", style, 0)
        && !WorkspaceAppCandidate("copilot", "chrome.exe", "Copilot is sharing your screen", style, 0),
        "Other apps, EHR windows, sharing notices and call windows must not be reused as workspace apps."
    Assert HelperMutexName("workspace-start") != HelperMutexName("launch-advancedmd")
        && HelperMutexName("launch-advancedmd") = HelperMutexName("mse"),
        "Workspace execution must be exclusive while preserving the clinical lock for AMD input."
    WorkspaceTestCalls := []
}
WorkspaceFixtureStep(step) {
    global WorkspaceTestCalls
    WorkspaceTestCalls.Push(step.Name)
    if step.Name = "Copilot"
        throw Error("Invented fixture failure")
}
Assert(condition, message) {
    if !condition
        throw Error(message)
}


; BEGIN SHARED CHROME FOCUS
; Only HWNDs, process IDs and usage order are remembered, never page titles.
ChromeFocusState() {
    static state := {Used: Map(), Excluded: Map(), Sequence: 0, Callback: 0, Hook: 0}
    return state
}

ChromeIsEhrTitle(title) {
    ; Exclude both AdvancedMD - EHR and AdvancedMD-EHR, plus AMD login pages.
    return InStr(StrLower(title), "advancedmd") != 0
}

ChromeIsBrowsingFrame(title, style, owner, extendedStyle := 0) {
    if ChromeIsEhrTitle(title) || Trim(title) = "" || RegExMatch(title, "i)\bCopilot\b")
        return false
    if RegExMatch(title, "i)^(?:Sign in(?: to your account)?|Microsoft account)(?:\s*[-|–—].*)?$")
        return false
    ; The screen-capture notice is its own Chrome_WidgetWin_1 window. Its
    ; "Hide" action minimizes it, so process/class checks alone can resurrect it.
    if RegExMatch(title, "i)(?:is sharing (?:your |the )?(?:screen|window|tab|audio)|sharing your screen|screen sharing|screen capture notification|ScreenCaptureNotificationUIViews)")
        return false
    ; Normal browsing windows are unowned, resizable frames with a system menu.
    ; Skip owned dialogs, WS_EX_TOOLWINDOW, and the non-resizable capture toolbar.
    return !owner && !(extendedStyle & 0x80)
        && (style & 0x00040000) && (style & 0x00080000)
}
ChromeIsBrowsingHwnd(hwnd) {
    try return WinGetProcessName(hwnd) = "chrome.exe"
        && ChromeIsBrowsingFrame(WinGetTitle(hwnd), WinGetStyle(hwnd),
            DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr"), WinGetExStyle(hwnd))
    catch
        return false
}

StartChromeFocusTracking() {
    state := ChromeFocusState()
    if state.Hook
        return
    state.Callback := CallbackCreate(ChromeForegroundChanged, , 7)
    ; EVENT_SYSTEM_FOREGROUND, out-of-context, skipping this AHK process.
    state.Hook := DllCall("SetWinEventHook", "uint", 3, "uint", 3, "ptr", 0,
        "ptr", state.Callback, "uint", 0, "uint", 0, "uint", 2, "ptr")
    if !state.Hook {
        CallbackFree state.Callback
        state.Callback := 0
        return ; Normal desktop Z-order is the fallback if tracking is unavailable.
    }
    OnExit StopChromeFocusTracking
    ChromeForegroundChanged(0, 3, WinExist("A"), 0, 0, 0, 0)
}

StopChromeFocusTracking(*) {
    state := ChromeFocusState()
    if state.Hook
        DllCall("UnhookWinEvent", "ptr", state.Hook)
    if state.Callback
        CallbackFree state.Callback
    state.Hook := 0, state.Callback := 0
}

ChromeForegroundChanged(hook, event, hwnd, objectId, childId, threadId, eventTime) {
    try {
        if !hwnd || objectId || childId || WinGetProcessName(hwnd) != "chrome.exe"
            return
        state := ChromeFocusState()
        pid := WinGetPID(hwnd)
        if ChromeIsEhrTitle(WinGetTitle(hwnd)) || RegExMatch(WinGetTitle(hwnd), "i)\bCopilot\b")
            state.Excluded[hwnd] := pid
        state.Sequence += 1
        state.Used[hwnd] := {Pid: pid, Order: state.Sequence}
    }
}

GeneralChromeCandidates() {
    state := ChromeFocusState()
    candidates := []
    ; Windows enumerates in desktop Z-order. This seeds selection before any
    ; foreground history is observed; tracked use takes priority afterwards.
    for hwnd in WinGetList("ahk_exe chrome.exe ahk_class Chrome_WidgetWin_1") {
        try {
            title := WinGetTitle(hwnd)
            pid := WinGetPID(hwnd)
            if ChromeIsEhrTitle(title) || RegExMatch(title, "i)\bCopilot\b") {
                state.Excluded[hwnd] := pid
                continue
            }
            ; Keep known EHR/Copilot windows excluded if their active tab/title changes.
            if !ChromeIsBrowsingHwnd(hwnd)
                || (state.Excluded.Has(hwnd) && state.Excluded[hwnd] = pid)
                continue
            candidates.Push({Hwnd: hwnd, Pid: pid})
        }
    }
    return candidates
}

SelectGeneralChrome(candidates, used) {
    selected := 0, bestOrder := -1
    for window in candidates {
        order := used.Has(window.Hwnd) && used[window.Hwnd].Pid = window.Pid
            ? used[window.Hwnd].Order : 0
        if order > bestOrder
            selected := window.Hwnd, bestOrder := order
    }
    return selected
}

ActivateGeneralChrome(hwnd) {
    ; Recheck the live title immediately before activating this exact HWND.
    if !WinExist(hwnd) || !ChromeIsBrowsingHwnd(hwnd)
        return false
    WinActivate hwnd ; Automatically restores a minimized window; keeps normal placement.
    return !!WinWaitActive(hwnd, , 2)
}

FocusGeneralChrome(quiet := false, *) {
    static busy := false
    if busy
        return 0
    busy := true
    try {
        state := ChromeFocusState()
        hwnd := SelectGeneralChrome(GeneralChromeCandidates(), state.Used)
        if hwnd && ActivateGeneralChrome(hwnd)
            return hwnd
        ; A separate blank window prevents Chrome from reusing the EHR window
        ; when it is the only Chrome window. No clinical URL or data is supplied.
        Run 'chrome.exe --new-window "about:blank"'
        deadline := A_TickCount + 7000
        while A_TickCount < deadline {
            Sleep 100
            hwnd := SelectGeneralChrome(GeneralChromeCandidates(), state.Used)
            if hwnd && ActivateGeneralChrome(hwnd)
                return hwnd
        }
        if !quiet
            TrayTip "Chrome was started, but its browsing window could not be focused yet.", "Trigger Search"
    } catch {
        if !quiet
            TrayTip "Could not focus or open Chrome. Check that Google Chrome is installed.", "Trigger Search"
    } finally {
        busy := false
    }
    return 0
}

TestGeneralChromeSelection() {
    for title in ["AdvancedMD - EHR - Google Chrome", "AdvancedMD-EHR", "advancedmd – ehr",
        "Login | AdvancedMD", "AdvancedMD — EHR"]
        Assert ChromeIsEhrTitle(title), "All known AdvancedMD title variants must be excluded from general Chrome."
    Assert !ChromeIsEhrTitle("General browsing - Google Chrome"), "General browsing titles must remain eligible."
    frameStyle := 0x00CF0000
    Assert ChromeIsBrowsingFrame("General browsing - Google Chrome", frameStyle, 0),
        "Normal resizable browsing frames must be eligible."
    for notice in ["Clinician Blueprint AI is sharing your screen and audio",
        "example.test is sharing your screen.", "Screen sharing", "ScreenCaptureNotificationUIViews"]
        Assert !ChromeIsBrowsingFrame(notice, frameStyle, 0),
            "Sharing notices must never be candidates even if they have ordinary window styles."
    Assert !ChromeIsBrowsingFrame("Sign in to your account - Google Chrome", frameStyle, 0),
        "A Microsoft sign-in prompt must not become the general browsing workspace window."
    Assert !ChromeIsBrowsingFrame("Microsoft 365 Copilot", frameStyle, 0),
        "The dedicated Copilot window must never become general browsing Chrome."
    Assert !ChromeIsBrowsingFrame("Google Chrome", 0x80000000, 0)
        && !ChromeIsBrowsingFrame("General browsing", frameStyle, 10)
        && !ChromeIsBrowsingFrame("General browsing", frameStyle, 0, 0x80),
        "Popup frames, owned dialogs and tool windows must never steal Alt+X."
    windows := [{Hwnd: 100, Pid: 1}, {Hwnd: 200, Pid: 2}]
    Assert SelectGeneralChrome(windows, Map()) = 100,
        "Initial selection must follow desktop Z-order when no usage history exists."
    usage := Map(100, {Pid: 1, Order: 10}, 200, {Pid: 2, Order: 20})
    Assert SelectGeneralChrome(windows, usage) = 200,
        "Observed most-recent usage must override desktop Z-order."
    usage[200].Pid := 99
    Assert SelectGeneralChrome(windows, usage) = 100,
        "Reused window handles must not inherit a different process's usage history."
    Assert SelectGeneralChrome([], usage) = 0, "No eligible window must request a new Chrome window."
}
; END SHARED CHROME FOCUS

; Close application windows gracefully. No taskkill, app-process termination,
; automatic save/discard choice, session logoff or Windows shutdown is used.
CloseApplicationCandidate(process, className, title, style, extendedStyle, owner, zoomMain := false) {
    process := StrLower(process)
    if RegExMatch(process, "i)^autohotkey.*\.exe$")
        || process = "trigger-search.exe" || process = "triggersearch.exe"
        return false
    if className = "Progman" || className = "WorkerW" || className = "Shell_TrayWnd"
        || className = "Shell_SecondaryTrayWnd" || className = "#32770"
        return false
    shell := Map("shellexperiencehost.exe", true, "startmenuexperiencehost.exe", true,
        "searchhost.exe", true, "textinputhost.exe", true, "lockapp.exe", true,
        "dwm.exe", true, "winlogon.exe", true)
    if shell.Has(process)
        return false
    if process = "explorer.exe" && className != "CabinetWClass" && className != "ExploreWClass"
        return false
    ; A known hidden main Zoom meeting can exist while its mini view is visible.
    if zoomMain && process = "zoom.exe"
        return true
    if owner || (extendedStyle & 0x80) || Trim(title) = ""
        return false
    return !!(style & 0x00080000)
        && (((style & 0x00C00000) = 0x00C00000) || (style & 0x00040000))
}
CloseApplicationEntry(hwnd, zoomMain := false) {
    try {
        process := WinGetProcessName(hwnd)
        className := WinGetClass(hwnd)
        title := WinGetTitle(hwnd)
        verifiedZoom := zoomMain && process = "Zoom.exe" && ZoomMeetingCandidate(title, className)
        if CloseApplicationCandidate(process, className, title, WinGetStyle(hwnd),
            WinGetExStyle(hwnd), DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr"), verifiedZoom)
            return {Hwnd: hwnd, Pid: WinGetPID(hwnd), ZoomMain: verifiedZoom}
    }
    return 0
}
CaptureCloseApplications() {
    entries := [], seen := Map()
    for hwnd in WinGetList() {
        if entry := CloseApplicationEntry(hwnd) {
            entries.Push(entry)
            seen[hwnd] := true
        }
    }
    previous := DetectHiddenWindows(true)
    try {
        for hwnd in WinGetList("ahk_exe Zoom.exe") {
            if !seen.Has(hwnd) && (entry := CloseApplicationEntry(hwnd, true)) && entry.ZoomMain {
                entries.Push(entry)
                seen[hwnd] := true
            }
        }
    } finally {
        DetectHiddenWindows previous
    }
    return entries
}
RequestApplicationClose(entry) {
    ; Verify the same PID and current eligibility immediately before posting.
    if !WinExist(entry.Hwnd) || WinGetPID(entry.Hwnd) != entry.Pid
        return 0
    if !CloseApplicationEntry(entry.Hwnd, entry.ZoomMain)
        return 0
    return DllCall("PostMessageW", "ptr", entry.Hwnd, "uint", 0x0010,
        "ptr", 0, "ptr", 0, "int") ? 1 : -1
}
DispatchApplicationCloses(entries, sender := 0) {
    result := {Requested: 0, Skipped: 0, Failed: 0}
    ; A single initial snapshot: never enumerate or act on new Save/Discard or
    ; End Meeting dialogs that appear in response to these close requests.
    for entry in entries {
        try {
            status := sender ? sender.Call(entry) : RequestApplicationClose(entry)
            if status > 0
                result.Requested += 1
            else if status = 0
                result.Skipped += 1
            else
                result.Failed += 1
        } catch {
            result.Failed += 1
        }
    }
    return result
}
CloseApplications() {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["Close applications", "normal WM_CLOSE requests only"])
        return
    }
    result := DispatchApplicationCloses(CaptureCloseApplications())
    message := "Close requests sent to " result.Requested " application windows."
    message .= " Finish any save or meeting prompts."
    if result.Failed
        message .= " Some windows could not be asked to close."
    TrayTip message, "Trigger Search"
}
TestCloseApplicationPolicy() {
    style := 0x00CF0000
    Assert CloseApplicationCandidate("chrome.exe", "Chrome_WidgetWin_1", "Browser", style, 0, 0)
        && CloseApplicationCandidate("explorer.exe", "CabinetWClass", "Folder", style, 0, 0),
        "Normal application and File Explorer windows must receive close requests."
    for process in ["AutoHotkey64.exe", "AutoHotkey.exe", "TriggerSearch.exe", "dwm.exe", "StartMenuExperienceHost.exe"]
        Assert !CloseApplicationCandidate(process, "AppWindow", "Application", style, 0, 0),
            "AHK launchers, keyboard listeners and Windows shell processes must be protected."
    Assert !CloseApplicationCandidate("explorer.exe", "Shell_TrayWnd", "Taskbar", style, 0, 0)
        && !CloseApplicationCandidate("explorer.exe", "WorkerW", "Desktop", style, 0, 0)
        && !CloseApplicationCandidate("notepad.exe", "#32770", "Save changes", style, 0, 0)
        && !CloseApplicationCandidate("chrome.exe", "Chrome_WidgetWin_1", "Dialog", style, 0, 123)
        && !CloseApplicationCandidate("chrome.exe", "Chrome_WidgetWin_1", "Toolbar", style, 0x80, 0),
        "Shells, save prompts, owned dialogs and tool windows must never be close targets."
    Assert CloseApplicationCandidate("Zoom.exe", "ZPContentViewWndClass", "", 0, 0, 0, true)
        && !CloseApplicationCandidate("notepad.exe", "ZPContentViewWndClass", "", 0, 0, 0, true),
        "Only an identified Zoom main window may bypass ordinary visibility/frame checks."
    captured := [{Hwnd: 1}, {Hwnd: 2}]
    sent := []
    result := DispatchApplicationCloses(captured, (entry) => ClosePolicyFixtureSend(entry, sent))
    Assert result.Requested = 1 && result.Skipped = 1 && sent.Length = 2,
        "The dispatcher must use the supplied snapshot and count requests without force-killing apps."
}
ClosePolicyFixtureSend(entry, sent) {
    sent.Push(entry.Hwnd)
    return entry.Hwnd = 1 ? 1 : 0
}
TestCloseApplicationsUI() {
    ; Only explicitly created test HWNDs are sent a close request. Never call the
    ; production capture-all function from automated tests on a real workstation.
    fixture := Gui("+Resize", "Close request fixture")
    state := {Requests: 0, Prompt: 0}
    fixture.OnEvent("Close", (*) => ClosePromptFixture(fixture, state))
    try {
        fixture.Show("NA w300 h150")
        result := DispatchApplicationCloses([{Hwnd: fixture.Hwnd}],
            (entry) => DllCall("PostMessageW", "ptr", entry.Hwnd, "uint", 0x0010, "ptr", 0, "ptr", 0, "int"))
        deadline := A_TickCount + 1500
        while !state.Requests && A_TickCount < deadline
            Sleep 30
        Assert result.Requested = 1 && state.Requests = 1 && WinExist(fixture.Hwnd)
            && IsObject(state.Prompt) && WinExist(state.Prompt.Hwnd),
            "Graceful close must leave an application's save prompt available, without killing it or choosing a button."
    } finally {
        if IsObject(state.Prompt)
            state.Prompt.Destroy()
        fixture.Destroy()
    }
}
ClosePromptFixture(owner, state) {
    state.Requests += 1
    state.Prompt := Gui("+Owner" owner.Hwnd, "Save fixture")
    state.Prompt.AddText(, "Invented unsaved document: waiting for the user.")
    state.Prompt.Show("NA w340 h100")
    return true ; Model an app refusing to close until the user chooses.
}
