#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
SendMode "Input"
SetTitleMatchMode 2
global DryRun := A_Args.Length = 1 && A_Args[1] = "--self-test"
global TargetHwnd := 0
global Steps := []
global HelperActions := Map(
    "initials", Initials, "charge-slip", ChargeSlip, "timestamp", Timestamp,
    "mse", Mse, "mse-fast", MseFast, "follow-up-mse", FollowUpMse,
    "sid", Sid, "plan-navigation", PlanNavigation, "mse-navigation", MseNavigation,
    "hpi", Hpi, "launch-advancedmd", LaunchAdvancedMD, "morning-startup", MorningStartup,
    "blueprint", Blueprint, "it-ticket", ItTicket, "schedule-email", ScheduleEmail,
    "copilot", Copilot, "espanso", Espanso, "copy-back", CopyBack, "join-zoom", JoinZoom,
    "end-zoom", EndZoom, "teams-call-clipboard", TeamsCallClipboard)
if DryRun {
    TestZoomPlacement()
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
if A_Args.Length != 2 || !RegExMatch(A_Args[1], "^\d+$") || !HelperActions.Has(A_Args[2])
    ExitApp 2
TargetHwnd := Integer(A_Args[1])
mutex := DllCall("CreateMutexW", "ptr", 0, "int", 1,
    "str", "Local\TriggerSearchAdvancedMD", "ptr")
if !mutex || A_LastError = 183 {
    if mutex
        DllCall("CloseHandle", "ptr", mutex)
    TrayTip "Another automation is running.", "Trigger Search"
    ExitApp 3
}
try {
    if RequiresOriginWindow(A_Args[2])
        CheckTarget()
    HelperActions[A_Args[2]].Call()
} catch as problem {
    ; Fixed error messages only; no window titles or clipboard contents are logged.
    MsgBox problem.Message, "Trigger Search 0.16.22 — " A_Args[2]
} finally {
    DllCall("CloseHandle", "ptr", mutex)
}
ExitApp
Esc::ExitApp

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
    ; Focusing an open EHR must not type an office key, repeat login, or move it.
    if !DryRun && (ehr := ExistingAdvancedMDEhrWindow()) {
        WinActivate ehr
        if !WinWaitActive(ehr, , 5)
            throw Error("Could not activate the existing AdvancedMD EHR window.")
        TargetHwnd := ehr
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
    MoveToLeftDisplay()
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
Copilot() {
    OpenUrl "https://m365.cloud.microsoft/chat"
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

MoveToLeftDisplay() {
    global DryRun, Steps, TargetHwnd
    if DryRun {
        Steps.Push(["MoveToLeftDisplay"])
        return
    }
    RequireAMDWindowExists()
    areas := []
    Loop MonitorGetCount() {
        MonitorGetWorkArea A_Index, &left, &top, &right, &bottom
        areas.Push({Left: left, Top: top, Right: right, Bottom: bottom})
    }
    destination := LeftmostDisplay(areas)
    window := "ahk_id " TargetHwnd
    WinRestore window
    PauseFor 150
    RequireAMDWindowExists()
    ; Put the restored window fully inside the destination before maximizing.
    ; This also works when the left display has negative coordinates.
    width := Max(100, Min(1000, destination.Right - destination.Left - 40))
    height := Max(100, Min(700, destination.Bottom - destination.Top - 40))
    WinMove destination.Left + 20, destination.Top + 20, width, height, window
    PauseFor 500
    RequireAMDWindowExists()
    WinMaximize window
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
        && action != "end-zoom" && action != "teams-call-clipboard"
}

JoinZoom() {
    global DryRun, Steps
    if DryRun {
        Steps.Push(["Zoom", "JoinAndPosition"])
        return
    }
    ; Do not terminate a live call just to resize it or start another meeting.
    meeting := FindZoomMeeting()
    if meeting {
        ; Focusing an existing call must preserve its geometry and maximized state.
        window := "ahk_id " meeting
        if !DllCall("IsWindowVisible", "ptr", meeting)
            WinShow meeting
        if WinGetMinMax(meeting) = -1
            WinRestore meeting
        WinActivate meeting
        return
    }
    url := LocalZoomMeetingUrl()
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
LocalZoomMeetingUrl() {
    path := A_AppData "\SheetAutocomplete\settings.ini"
    value := Trim(IniRead(path, "workflow-config", "ZoomMeetingUrl", ""))
    if ValidZoomMeetingUrl(value)
        return value
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
ZoomTopCenterBounds(area) {
    width := Max(100, Min(640, area.Right - area.Left - 48))
    height := Max(100, Min(480, area.Bottom - area.Top - 48))
    return {X: area.Left + Floor((area.Right - area.Left - width) / 2),
        Y: area.Top + 24, Width: width, Height: height}
}
PositionZoomMeeting(hwnd) {
    window := "ahk_id " hwnd
    if !WinExist(window) || WinGetProcessName(window) != "Zoom.exe"
        throw Error("The Zoom meeting window is no longer available.")
    WinGetPos &x, &y, &width, &height, window
    monitor := MonitorGetPrimary()
    Loop MonitorGetCount() {
        MonitorGet A_Index, &left, &top, &right, &bottom
        if x + width / 2 >= left && x + width / 2 < right && y + height / 2 >= top && y + height / 2 < bottom {
            monitor := A_Index
            break
        }
    }
    MonitorGetWorkArea monitor, &left, &top, &right, &bottom
    bounds := ZoomTopCenterBounds({Left: left, Top: top, Right: right, Bottom: bottom})
    WinRestore window
    Sleep 150
    WinMove bounds.X, bounds.Y, bounds.Width, bounds.Height, window
    Sleep 300
    ; Zoom can enforce a minimum size. Center that actual width as well.
    WinGetPos , , &actualWidth, , window
    WinMove left + Floor((right - left - actualWidth) / 2), bounds.Y, , , window
    WinActivate window
}
TestZoomPlacement() {
    if RequiresOriginWindow("join-zoom")
        throw Error("Join Zoom must not depend on the launcher's previous window.")
    bounds := ZoomTopCenterBounds({Left: -1920, Top: 0, Right: 0, Bottom: 1040})
    if bounds.X != -1280 || bounds.Y != 24 || bounds.Width != 640 || bounds.Height != 480
        throw Error("Zoom must center near the top of its own monitor, including negative coordinates.")
    bounds := ZoomTopCenterBounds({Left: 0, Top: 40, Right: 600, Bottom: 440})
    if bounds.Width != 552 || bounds.Height != 352 || bounds.X != 24 || bounds.Y != 64
        throw Error("Zoom placement must fit a small monitor work area.")
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
