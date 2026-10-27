#Requires AutoHotkey v2.0
#SingleInstance Force
; Optional standalone Alt+X script. Trigger Search already supplies this shortcut:
; do not run both bindings or keep Raycast Alt+X enabled at the same time.
; No includes, extension, configuration file, or other dependency is required.
if A_Args.Length && A_Args[1] = "--self-test" {
    TestGeneralChromeSelection()
    ExitApp 0
}
StartChromeFocusTracking()
!x::FocusGeneralChrome()

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
    if ChromeIsEhrTitle(title) || Trim(title) = ""
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
        if ChromeIsEhrTitle(WinGetTitle(hwnd))
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
            if ChromeIsEhrTitle(title) {
                state.Excluded[hwnd] := pid
                continue
            }
            ; Keep a known EHR window excluded if its active tab/title changes.
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

FocusGeneralChrome(*) {
    static busy := false
    if busy
        return
    busy := true
    try {
        state := ChromeFocusState()
        hwnd := SelectGeneralChrome(GeneralChromeCandidates(), state.Used)
        if hwnd && ActivateGeneralChrome(hwnd)
            return
        ; A separate blank window prevents Chrome from reusing the EHR window
        ; when it is the only Chrome window. No clinical URL or data is supplied.
        Run 'chrome.exe --new-window "about:blank"'
        deadline := A_TickCount + 7000
        while A_TickCount < deadline {
            Sleep 100
            hwnd := SelectGeneralChrome(GeneralChromeCandidates(), state.Used)
            if hwnd && ActivateGeneralChrome(hwnd)
                return
        }
        TrayTip "Chrome was started, but its browsing window could not be focused yet.", "Trigger Search"
    } catch {
        TrayTip "Could not focus or open Chrome. Check that Google Chrome is installed.", "Trigger Search"
    } finally {
        busy := false
    }
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

Assert(condition, message) {
    if !condition
        throw Error(message)
}
