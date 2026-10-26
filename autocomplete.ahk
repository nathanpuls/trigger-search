#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Trigger Search Windows client
global AppVersion := "0.16.17"

SendMode "Input"
SetTitleMatchMode 2

; Existing installs migrate this legacy example ID into their local settings.
; New installs ask for a public Google Sheet link on first launch.
global LegacySheetId := "15JTaedzH2ZfT2FAb7FduyMg37aBCHTKborM7E0y8nts"
global SheetId := ""
global RefreshIntervalMs := 60000
global CacheDir := A_AppData "\SheetAutocomplete"
global ManifestPath := CacheDir "\cache.ini"
global SettingsPath := CacheDir "\settings.ini"
global ErrorPath := CacheDir "\last-error.txt"
global UpdateUrl := "https://api.github.com/repos/nathanpuls/trigger-search/contents/windows/autocomplete.ahk"

global Trigger := ";"
global TriggerHotkey := ""
global LauncherModifier := "None"
global LauncherKey := "None"
global LauncherHotkey := ""
global RightControlUsed := false
global RightControlDown := 0
global AutomationRegistry := Map(
    "advancedmd.follow-up-office", {File: "advancedmd/follow-up-office.ahk", Action: ""},
    "advancedmd.follow-up-tele", {File: "advancedmd/follow-up-tele.ahk", Action: ""},
    "advancedmd.intake-office", {File: "advancedmd/intake-office.ahk", Action: ""},
    "dell.initials", {File: "dell/helpers.ahk", Action: "initials"},
    "dell.charge-slip", {File: "dell/helpers.ahk", Action: "charge-slip"},
    "dell.timestamp", {File: "dell/helpers.ahk", Action: "timestamp"},
    "dell.mse", {File: "dell/helpers.ahk", Action: "mse"},
    "dell.mse-fast", {File: "dell/helpers.ahk", Action: "mse-fast"},
    "dell.follow-up-mse", {File: "dell/helpers.ahk", Action: "follow-up-mse"},
    "dell.sid", {File: "dell/helpers.ahk", Action: "sid"},
    "dell.plan-navigation", {File: "dell/helpers.ahk", Action: "plan-navigation"},
    "dell.mse-navigation", {File: "dell/helpers.ahk", Action: "mse-navigation"},
    "dell.hpi", {File: "dell/helpers.ahk", Action: "hpi"},
    "dell.launch-advancedmd", {File: "dell/helpers.ahk", Action: "launch-advancedmd"},
    "dell.morning-startup", {File: "dell/helpers.ahk", Action: "morning-startup"},
    "dell.blueprint", {File: "dell/helpers.ahk", Action: "blueprint"},
    "dell.it-ticket", {File: "dell/helpers.ahk", Action: "it-ticket"},
    "dell.schedule-email", {File: "dell/helpers.ahk", Action: "schedule-email"},
    "dell.copilot", {File: "dell/helpers.ahk", Action: "copilot"},
    "dell.espanso", {File: "dell/helpers.ahk", Action: "espanso"},
    "dell.copy-back", {File: "dell/helpers.ahk", Action: "copy-back"},
    "zoom.join", {File: "dell/helpers.ahk", Action: "join-zoom"},
    "clipboard.store", {File: "", Action: "builtin:clipboard-store"},
    "clipboard.paste", {File: "", Action: "builtin:clipboard-paste"},
    "keyboard.remaps", {File: "", Action: "builtin:remaps"},
    "trigger-search.refresh-all", {File: "", Action: "builtin:refresh-all"}
)
global SpecialClipboard := ""
global SpecialClipboardSet := false
global RemapsEnabled := false
global RightControlEventCount := 0
global KeyboardTestMode := A_Args.Length > 0 && A_Args[1] = "--keyboard-test"
global KeyboardTestLaunchCount := 0


global AiEngine := "ChatGPT"
global InboxSheet := "Inbox"
global Refreshing := false
global RefreshPending := false
global LastRefreshTick := 0
global LastRefreshError := ""
global LastShownRefreshError := ""
global RefreshFailureCount := 0
global AtBoundary := true
global LastActiveWindow := 0
global TargetWindow := 0
global ChooserOpen := false
global PreviewOpen := false
global SheetInfos := []
global Snippets := []
global RecentItems := []
global RecentLimit := 9
global VisibleChoices := []
global DetailParent := 0
global SearchServiceParent := 0
global CategoryParent := ""
global RootQuery := ""
global ReturnParentKey := ""
global KeyboardWatcher := 0
global ActionsForChoice := 0
global ActionsReturnQuery := ""
global ActionsReturnKey := ""

global ChooserGui := 0
global SearchBox := 0
global ResultsView := 0
global FooterText := 0
global PreviewGui := 0
global PreviewChoiceValue := 0
global PreviewExpanded := 0
global ModifierHud := 0

if A_Args.Length > 0 && A_Args[1] = "--self-test"
    RunSelfTestsAndExit()

if KeyboardTestMode {
    SetTimer RunKeyboardIntegrationTest, -50
} else {
    OnError HandleUnexpectedError
    Initialize()
}

; Right Ctrl is a tap-only parallel launcher. Combinations retain Ctrl behavior.
~*SC11D::BeginRightControlTap()
~*SC11D Up::EndRightControlTap()
^!Space::ShowChooser()
!i::SendClipboardToInbox()

; Keep this variant before the general Alt+4 AMD binding: Zoom owns it only
; while an actual meeting is focused. Alt+5 also overrides clipboard paste only
; in a focused meeting. Ordinary typing and arrows are untouched.
#HotIf ManagedAutomationsAvailable() && !IsTriggerSearchOpen() && ActiveZoomMeeting()
!Left::ZoomWindowCommand("left")
!Right::ZoomWindowCommand("right")
!Up::ZoomWindowCommand("up")
!Down::ZoomWindowCommand("down")
!1::ZoomWindowCommand("1")
!2::ZoomWindowCommand("2")
!3::ZoomWindowCommand("3")
!4::ZoomWindowCommand("4")
!5::ZoomWindowCommand("5")
#HotIf

; These shortcuts replace the corresponding Dell listeners only in managed installs.
#HotIf ManagedAutomationsAvailable() && !IsTriggerSearchOpen()
!z::RunAutomation("zoom.join")
!o::RunAutomation("advancedmd.follow-up-office")
!t::RunAutomation("advancedmd.follow-up-tele")
!0::RunAutomation("advancedmd.intake-office")
!a::RunAutomation("dell.launch-advancedmd")
!b::RunAutomation("dell.blueprint")
!q::RunAutomation("dell.mse-navigation")
!4::RunAutomation("dell.plan-navigation")
F2::RunAutomation("dell.initials")
F3::RunAutomation("dell.charge-slip")
F4::RunAutomation("dell.timestamp")
F8::RunAutomation("dell.schedule-email")
^!m::RunAutomation("dell.mse-fast")
^!5::RunAutomation("clipboard.store")
!5::RunAutomation("clipboard.paste")
:*:'mse:: {
    RunAutomation("dell.mse")
}
:*:'fum:: {
    RunAutomation("dell.follow-up-mse")
}
:*:;sid:: {
    RunAutomation("dell.sid")
}
:*:;cc:: {
    RunAutomation("dell.copy-back")
}
#HotIf

#HotIf IsTriggerSearchOpen()
$*Escape::HandleEscape()
#HotIf

#HotIf IsChooserOpen()
Up::MoveSelection(-1)
Down::MoveSelection(1)
Enter::ChooseSelected()
Right::OpenSelectedAction()
Left::CloseDetails()
^e::EditSelected()
^c::CopySelected()
^o::OpenSelectedLink()
^g::SearchGoogleQuery()
^p::PreviewSelected()
^r::RefreshInPlace()
^+i::CopyLatestInboxNow()
^Enter::LaunchSelectedAi()
^k::ShowActionsMenu()
^1::ChooseVisibleByNumber(1)
^2::ChooseVisibleByNumber(2)
^3::ChooseVisibleByNumber(3)
^4::ChooseVisibleByNumber(4)
^5::ChooseVisibleByNumber(5)
^6::ChooseVisibleByNumber(6)
^7::ChooseVisibleByNumber(7)
^8::ChooseVisibleByNumber(8)
^9::ChooseVisibleByNumber(9)
~*Ctrl::StartModifierHud()
~*Ctrl Up::HideModifierHud()
#HotIf

#HotIf IsPreviewOpen()
p::PastePreview()
c::CopyPreview()
#HotIf

~LButton::ResetBoundary()
~RButton::ResetBoundary()
~MButton::ResetBoundary()

Initialize() {
    global CacheDir, RefreshIntervalMs, Trigger, SheetId
    global LauncherModifier, LauncherKey
    global Snippets, AppVersion

    OnMessage 0x0100, HandleGuiKeyDown
    OnMessage 0x0104, HandleGuiKeyDown
    OnMessage 0x004E, DrawSelectedResult
    DirCreate CacheDir
    A_IconTip := "Trigger Search v" AppVersion
    LoadSheetConfiguration()
    LoadRecentItems()
    LoadCache()
    BuildChooser()
    InstallTrigger(Trigger)
    InstallLauncherHotkey(LauncherModifier, LauncherKey)
    StartKeyboardWatcher()
    InitializeKeyboardRemaps()

    A_TrayMenu.Add()
    A_TrayMenu.Add("Trigger Search v" AppVersion, (*) => 0)
    A_TrayMenu.Disable("Trigger Search v" AppVersion)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Open autocomplete", (*) => ShowChooser())
    A_TrayMenu.Add("Refresh snippets", ManualRefresh)
    A_TrayMenu.Add("Copy latest Inbox now", CopyLatestInboxNow)
    A_TrayMenu.Add("Send clipboard to Inbox (Alt+I)", SendClipboardToInbox)
    A_TrayMenu.Add("Open private Inbox setup (Google Drive)", OpenInboxSetupDrive)
    A_TrayMenu.Add("Toggle Dell keyboard remaps", (*) => RunBuiltinAutomation("builtin:remaps"))
    A_TrayMenu.Add("Open Google Sheet", (*) => OpenWorkbook())
    A_TrayMenu.Add("Change Google Sheet...", (*) => PromptForGoogleSheet(false))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Update script from GitHub", UpdateScriptFromGitHub)
    A_TrayMenu.Add("Refresh all scripts", UpdateScriptFromGitHub)
    A_TrayMenu.Add("Install Original Scripts ON/OFF...", InstallOriginalScriptsControls)
    A_TrayMenu.Add("Show last error report", ShowLastErrorReport)
    A_TrayMenu.Add("Keyboard and installation status", ShowKeyboardStatus)

    SetTimer CheckActiveWindow, 400
    SetTimer RefreshData, RefreshIntervalMs
    if SheetId = ""
        SetTimer () => PromptForGoogleSheet(true), -100
    else if Snippets.Length = 0
        RefreshData(true)
    else
        SetTimer RefreshData, -25
}

BuildChooser() {
    global ChooserGui, SearchBox, ResultsView, FooterText

    ChooserGui := Gui("+AlwaysOnTop +ToolWindow", "Trigger Search")
    ChooserGui.MarginX := 14
    ChooserGui.MarginY := 12
    ChooserGui.SetFont("s10", "Segoe UI")

    SearchBox := ChooserGui.Add("Edit", "xm w730 h30 vQuery")
    ResultsView := ChooserGui.Add(
        "ListView",
        "xm y+8 w730 r9 -Multi -Hdr",
        ["Shortcut", "Label", "Details"]
    )
    ResultsView.ModifyCol(1, 65)
    ResultsView.ModifyCol(2, 225)
    ResultsView.ModifyCol(3, 400)
    ChooserGui.SetFont("s9 c666666", "Segoe UI")
    FooterText := ChooserGui.Add("Text", "xm y+6 w730 Right Hidden", "")

    SearchBox.OnEvent("Change", SearchChanged)
    ResultsView.OnEvent("Click", ResultClicked)
    ChooserGui.OnEvent("Close", (*) => CancelChooser())
    ChooserGui.OnEvent("Escape", CloseLauncher)

    SetSearchPlaceholder("Search")
}

DrawSelectedResult(wParam, lParam, msg, hwnd) {
    global ResultsView

    if !IsObject(ResultsView) || NumGet(lParam, 0, "Ptr") != ResultsView.Hwnd
        return

    ; Keep focus in the search box for uninterrupted typing, but draw the
    ; current row with Windows' active selection colors instead of the faint
    ; inactive ListView highlight. System colors preserve high-contrast themes.
    notificationCode := NumGet(lParam, A_PtrSize * 2, "Int")
    if notificationCode != -12 ; NM_CUSTOMDRAW
        return

    drawStageOffset := A_PtrSize = 8 ? 24 : 12
    drawStage := NumGet(lParam, drawStageOffset, "UInt")
    if drawStage = 0x00000001 ; CDDS_PREPAINT
        return 0x00000020 ; CDRF_NOTIFYITEMDRAW
    if drawStage != 0x00010001 ; CDDS_ITEMPREPAINT
        return

    itemOffset := A_PtrSize = 8 ? 56 : 36
    row := NumGet(lParam, itemOffset, "UPtr") + 1
    selectedRow := ResultsView.GetNext(0, "F")
    ; With RowType omitted, GetNext returns the next selected row.
    if selectedRow = 0
        selectedRow := ResultsView.GetNext(0)
    if row != selectedRow
        return

    stateOffset := A_PtrSize = 8 ? 64 : 40
    itemState := NumGet(lParam, stateOffset, "UInt")
    NumPut("UInt", itemState & ~0x0001, lParam, stateOffset) ; Remove CDIS_SELECTED.

    textColorOffset := A_PtrSize = 8 ? 80 : 48
    backgroundColorOffset := A_PtrSize = 8 ? 84 : 52
    NumPut("UInt", DllCall("GetSysColor", "Int", 14, "UInt"), lParam, textColorOffset)
    NumPut("UInt", DllCall("GetSysColor", "Int", 13, "UInt"), lParam, backgroundColorOffset)
    return 0x00000002 ; CDRF_NEWFONT applies the supplied colors.
}

SetSearchPlaceholder(text) {
    global SearchBox

    ; Native Windows cue text inside the search box, also shown while focused.
    DllCall(
        "SendMessage",
        "Ptr", SearchBox.Hwnd,
        "UInt", 0x1501,
        "Ptr", true,
        "Str", text
    )
}

UpdateChooserContext() {
    global ChooserGui, DetailParent, SearchServiceParent, CategoryParent

    if DetailParent
        ChooserGui.Title := "Trigger Search — " DetailParent.GroupLabel
    else if SearchServiceParent
        ChooserGui.Title := "Trigger Search — " SearchServiceParent.GroupLabel
    else if CategoryParent != ""
        ChooserGui.Title := "Trigger Search — " CategoryParent
    else
        ChooserGui.Title := "Trigger Search"
    SetSearchPlaceholder(CategoryParent != "" ? "←  " CategoryParent : "Search")
}

StartKeyboardWatcher() {
    global KeyboardWatcher

    if IsObject(KeyboardWatcher) && KeyboardWatcher.InProgress
        return

    KeyboardWatcher := InputHook("V L0 I1")
    KeyboardWatcher.NotifyNonText := true
    KeyboardWatcher.KeyOpt("{All}", "N")
    KeyboardWatcher.OnChar := TrackTypedCharacter
    KeyboardWatcher.OnKeyDown := TrackNonTextKey
    KeyboardWatcher.Start()
}

TrackTypedCharacter(input, characters) {
    global AtBoundary, Trigger, ChooserOpen

    global RightControlUsed
    if GetKeyState("RControl", "P") || GetKeyState("RControl")
        RightControlUsed := true
    if ChooserOpen
        return
    lastCharacter := SubStr(characters, -1)
    if lastCharacter = Trigger
        return
    AtBoundary := RegExMatch(lastCharacter, "\s") != 0
}

TrackNonTextKey(input, vk, sc) {
    global AtBoundary, ChooserOpen

    global RightControlUsed
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if IsControlCombination(GetKeyState("RControl", "P") || GetKeyState("RControl"), vk, sc)
        RightControlUsed := true
    if ChooserOpen
        return

    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    if keyName = "Tab" || keyName = "Enter" || keyName = "NumpadEnter" {
        AtBoundary := true
    } else if keyName = "Left" || keyName = "Right" || keyName = "Up"
        || keyName = "Down" || keyName = "Home" || keyName = "End"
        || keyName = "PgUp" || keyName = "PgDn" || keyName = "Backspace"
        || keyName = "Delete" {
        AtBoundary := false
    }
}

ResetBoundary(*) {
    global AtBoundary
    global RightControlUsed
    if GetKeyState("RControl", "P") || GetKeyState("RControl")
        RightControlUsed := true
    AtBoundary := true
}

CheckActiveWindow(*) {
    global LastActiveWindow, AtBoundary, ChooserOpen, PreviewOpen, RefreshPending

    EnsureKeyboardWatcher()
    if !ChooserOpen && !PreviewOpen && RefreshPending
        && A_TimeIdlePhysical >= 1200
        SetTimer RefreshData, -10
    if ChooserOpen
        return
    current := WinExist("A")
    if current && current != LastActiveWindow {
        LastActiveWindow := current
        AtBoundary := true
    }
}

EnsureKeyboardWatcher(*) {
    global KeyboardWatcher

    if !IsObject(KeyboardWatcher) || !KeyboardWatcher.InProgress
        StartKeyboardWatcher()
}

InstallTrigger(newTrigger) {
    global Trigger, TriggerHotkey

    newTrigger := SubStr(Trim(newTrigger), 1, 1)
    if newTrigger = ""
        return

    if TriggerHotkey != "" {
        try Hotkey TriggerHotkey, "Off"
    }

    Trigger := newTrigger
    TriggerHotkey := "$" Trigger
    Hotkey TriggerHotkey, HandleTrigger, "On"
}

InstallLauncherHotkey(modifierValue, keyValue) {
    global LauncherModifier, LauncherKey, LauncherHotkey

    if LauncherHotkey != "" {
        try Hotkey LauncherHotkey, "Off"
        LauncherHotkey := ""
    }

    LauncherModifier := modifierValue = "" ? "None" : modifierValue
    LauncherKey := keyValue = "" ? "None" : keyValue
    modifierName := RegExReplace(StrLower(Trim(LauncherModifier)), "[\s_/-]+")
    keyName := RegExReplace(StrLower(Trim(LauncherKey)), "[\s_-]+")
    if keyName = "" || keyName = "none"
        return

    if modifierName = "" || modifierName = "none"
        modifierPrefix := ""
    else if modifierName = "altoption" || modifierName = "alt"
        || modifierName = "option"
        modifierPrefix := "!"
    else if modifierName = "control" || modifierName = "ctrl"
        modifierPrefix := "^"
    else if modifierName = "commandwindows" || modifierName = "command"
        || modifierName = "cmd" || modifierName = "windows"
        || modifierName = "win"
        modifierPrefix := "#"
    else if modifierName = "shift"
        modifierPrefix := "+"
    else {
        OutputDebug "Trigger Search: unsupported Launcher Modifier: " LauncherModifier "`n"
        return
    }

    if keyName = "return"
        keyName := "Enter"
    else if keyName = "space"
        keyName := "Space"
    else if keyName = "tab"
        keyName := "Tab"
    else if RegExMatch(keyName, "i)^f(?:[1-9]|1[0-2])$")
        keyName := StrUpper(keyName)
    else if RegExMatch(keyName, "i)^[a-z0-9]$")
        keyName := StrLower(keyName)
    else {
        OutputDebug "Trigger Search: unsupported Launcher Key: " LauncherKey "`n"
        return
    }

    if modifierPrefix = "" && !RegExMatch(keyName, "^F(?:[1-9]|1[0-2])$") {
        OutputDebug "Trigger Search: a launcher without a modifier must use F1-F12.`n"
        return
    }

    LauncherHotkey := "$" modifierPrefix keyName
    Hotkey LauncherHotkey, HandleLauncher, "On"
}

HandleLauncher(*) {
    if IsTriggerSearchOpen()
        CloseLauncher()
    else
        ShowChooser()
}

HandleTrigger(*) {
    global AtBoundary, ChooserOpen, Trigger, SearchBox

    if ChooserOpen {
        SearchBox.Value .= Trigger
        RenderChoices FilterChoices(SearchBox.Value)
        return
    }

    if AtBoundary {
        ShowChooser()
    } else {
        SendText Trigger
        AtBoundary := false
    }
}

ShowChooser(*) {
    global Snippets, TargetWindow, ChooserOpen, DetailParent, SearchServiceParent, CategoryParent, RootQuery
    global ReturnParentKey, SearchBox, ChooserGui
    global Refreshing, RefreshPending, LastRefreshTick
    global LastRefreshError, SheetId, ActionsForChoice, FooterText
    global PreviewOpen, PreviewGui

    ; A second open request must not capture our own window as the target or
    ; position relative to it. Keep the current search, selection, and location.
    if IsTriggerSearchOpen() {
        if PreviewOpen
            PreviewGui.Show()
        else {
            ChooserGui.Show()
            SearchBox.Focus()
        }
        return
    }

    if SheetId = "" {
        PromptForGoogleSheet(true)
        if SheetId = ""
            return
    }

    if Snippets.Length = 0 {
        if !Refreshing
            RefreshData(true)
        if Snippets.Length = 0 {
            message := Refreshing
                ? "Snippets are still loading. Try again in a few seconds."
                : (LastRefreshError != ""
                    ? "Could not load snippets: " LastRefreshError
                    : "No snippets are available. Check the public Sheet and internet connection.")
            TrayTip message, "Trigger Search"
            return
        }
    }

    TargetWindow := WinExist("A")
    ChooserOpen := true
    DetailParent := 0
    SearchServiceParent := 0
    CategoryParent := ""
    RootQuery := ""
    ReturnParentKey := ""
    ActionsForChoice := 0
    SearchBox.Enabled := true
    FooterText.Text := "Ctrl+R  Refresh now"
    FooterText.Visible := true
    UpdateChooserContext()
    SearchBox.Value := ""
    RenderChoices(FilterChoices(""))
    PositionChooser(TargetWindow)
    SearchBox.Focus()
    ; Keep synchronous workbook downloads away from the visible launcher so
    ; typing, Escape, and result actions remain responsive.
    if LastRefreshTick = 0 || A_TickCount - LastRefreshTick > 15000
        RefreshPending := true
}

PositionChooser(targetHwnd) {
    global ChooserGui

    try {
        WinGetPos &x, &y, &width, &height, "ahk_id " targetHwnd
        left := x + Floor((width - 760) / 2)
        top := y + Max(40, Floor((height - 405) / 3))
        ChooserGui.Show("w760 h405 x" left " y" top)
    } catch {
        ChooserGui.Show("w760 h405 Center")
    }
}

CancelChooser(*) {
    global ChooserOpen, ChooserGui, DetailParent, SearchServiceParent, CategoryParent, RootQuery, AtBoundary
    global ActionsForChoice

    HideModifierHud()
    if !ChooserOpen
        return
    ActionsForChoice := 0
    ChooserOpen := false
    try ChooserGui.Hide()
    DetailParent := 0
    SearchServiceParent := 0
    CategoryParent := ""
    RootQuery := ""
    AtBoundary := true
}

CloseLauncher(*) {
    global ChooserGui, PreviewGui, TargetWindow
    restoreTarget := (IsObject(ChooserGui) && WinActive("ahk_id " ChooserGui.Hwnd))
        || (IsObject(PreviewGui) && WinActive("ahk_id " PreviewGui.Hwnd))
    ClosePreview(false)
    CancelChooser()
    if restoreTarget && TargetWindow && WinExist("ahk_id " TargetWindow)
        try WinActivate "ahk_id " TargetWindow
}

HandleEscape(*) {
    CloseLauncher()
}

; Some Windows controls consume Escape before AutoHotkey's conditional hotkey
; runs. WM_KEYDOWN provides a GUI-local fallback for the search box, results,
; action list, and preview without intercepting Escape in other applications.
HandleGuiKeyDown(wParam, lParam, msg, hwnd) {
    global PreviewOpen, ChooserOpen

    if wParam != 0x1B || (!PreviewOpen && !ChooserOpen)
        return
    SetTimer HandleEscape, -1
    return 0
}

RefreshInPlace(*) {
    global Refreshing, ChooserOpen, FooterText, LastRefreshError
    if !ChooserOpen
        return
    if Refreshing
        return
    FooterText.Text := "Refreshing the Sheet…"
    ; RefreshData already updates the visible results through RefreshOpenChooser.
    ; Leave the GUI, query, target window, and position intact throughout.
    RefreshData(true)
    if ChooserOpen
        FooterText.Text := LastRefreshError = ""
            ? "Updated  •  Ctrl+R  Refresh now"
            : "Refresh failed; saved results kept  •  Ctrl+R  Retry"
}

ManualRefresh(*) {
    global ChooserOpen
    if ChooserOpen
        RefreshInPlace()
    else
        RefreshData(true)
}

IsTriggerSearchOpen(*) {
    global ChooserOpen, PreviewOpen
    return ChooserOpen || PreviewOpen
}

IsChooserOpen(*) {
    global ChooserOpen, PreviewOpen
    return ChooserOpen && !PreviewOpen
}

IsPreviewOpen(*) {
    global PreviewOpen
    return PreviewOpen
}

StartModifierHud(*) {
    SetTimer ShowModifierHud, 0
    SetTimer ShowModifierHud, -300
}

HideModifierHud(*) {
    global ModifierHud

    SetTimer ShowModifierHud, 0
    if IsObject(ModifierHud) {
        try ModifierHud.Destroy()
        ModifierHud := 0
    }
}

ShowModifierHud(*) {
    global ModifierHud, ChooserGui, ActionsForChoice, SearchBox

    if !IsChooserOpen() || ActionsForChoice || !GetKeyState("Ctrl", "P")
        return
    choice := SelectedChoice()
    query := Trim(SearchBox.Value)
    if query = "" && (!choice
        || (choice.HasOwnProp("IsUtilityError") && choice.IsUtilityError))
        return
    if choice && choice.HasOwnProp("IsUtilityError") && choice.IsUtilityError
        choice := 0

    hasSavedContent := choice && (!choice.HasOwnProp("HasSavedContent")
        || choice.HasSavedContent) && Trim(choice.Content) != ""
    actions := []
    if query != ""
        actions.Push("G       Search Google")
    if choice && choice.HasOwnProp("AiPrompt") && Trim(choice.AiPrompt) != ""
        actions.Push("Enter   Ask AI")
    if hasSavedContent
        actions.Push("C       Copy")
    if choice && choice.HasOwnProp("EditUrl") && choice.EditUrl != ""
        actions.Push("E       Edit")
    if choice && choice.HasOwnProp("Content") && ExtractLaunchUrl(choice.Content) != ""
        actions.Push("O       Open")
    if hasSavedContent
        actions.Push("P       Preview")
    if actions.Length = 0
        return

    HideModifierHud()
    ModifierHud := Gui("+AlwaysOnTop -Caption +ToolWindow +Border +E0x08000000")
    ModifierHud.BackColor := "F3F3F5"
    ModifierHud.MarginX := 18
    ModifierHud.MarginY := 14
    ModifierHud.SetFont("s10 c29292D", "Segoe UI")
    for index, label in actions
        ModifierHud.Add("Text", "xm " (index = 1 ? "" : "y+7 ") "w190", label)
    ChooserGui.GetPos(&chooserX, &chooserY, &chooserWidth, &chooserHeight)
    hudX := chooserX + chooserWidth - 230
    hudY := chooserY + 58
    ModifierHud.Show("NoActivate AutoSize x" hudX " y" hudY)
}

SearchChanged(control, info) {
    global DetailParent, SearchServiceParent, CategoryParent, RootQuery, ActionsForChoice

    if ActionsForChoice
        return

    query := control.Value
    if !DetailParent && !SearchServiceParent && CategoryParent = ""
        RootQuery := query
    RenderChoices(FilterChoices(query))
}

BuildUtilityChoice(query, timestamp := "") {
    cleaned := Trim(query)
    if timestamp = ""
        timestamp := A_Now

    if RegExMatch(cleaned, "i)^(\d+)\s*([DWMY])$", &match) {
        amount := Integer(match[1])
        unit := StrUpper(match[2])
        shifted := timestamp
        if unit = "D" {
            shifted := DateAdd(shifted, amount, "Days")
            unitName := amount = 1 ? "day" : "days"
        } else if unit = "W" {
            shifted := DateAdd(shifted, amount * 7, "Days")
            unitName := amount = 1 ? "week" : "weeks"
        } else if unit = "M" {
            shifted := AddCalendarMonths(shifted, amount)
            unitName := amount = 1 ? "month" : "months"
        } else {
            shifted := AddCalendarMonths(shifted, amount * 12)
            unitName := amount = 1 ? "year" : "years"
        }
        pasteValue := FormatDynamicDate(shifted, "MM/dd/yyyy")
        return {
            Type: "utility",
            Key: "date:" cleaned,
            Label: FormatDynamicDate(shifted, "MMMM d, yyyy"),
            DisplayText: FormatDynamicDate(shifted, "MMMM d, yyyy"),
            Content: pasteValue,
            Category: "Date calculator",
            Preview: amount " " unitName
                . " from today  •  Enter to paste " pasteValue,
            EditUrl: "",
            Details: [],
            IsUtilityError: false
        }
    }

    calculation := ParseArithmetic(cleaned)
    if !calculation.Recognized
        return 0
    if calculation.Error != "" {
        return {
            Type: "utility",
            Key: "calculator:error",
            Label: calculation.Error,
            DisplayText: calculation.Error,
            Content: "",
            Category: "Calculator",
            Preview: cleaned,
            EditUrl: "",
            Details: [],
            IsUtilityError: true
        }
    }

    result := FormatCalculationNumber(calculation.Value)
    return {
        Type: "utility",
        Key: "calculator:" cleaned,
        Label: result,
        DisplayText: result,
        Content: result,
        Category: "Calculator",
        Preview: RegExReplace(cleaned, "^=\s*")
            . "  •  Enter to paste result",
        EditUrl: "",
        Details: [],
        IsUtilityError: false
    }
}

ParseArithmetic(query) {
    expression := Trim(query)
    explicit := SubStr(expression, 1, 1) = "="
    if explicit
        expression := Trim(SubStr(expression, 2))
    if expression = ""
        return {Recognized: false, Error: "", Value: 0}
    if !RegExMatch(expression, "^[0-9.\s+\-*/()]+$")
        return {Recognized: false, Error: "", Value: 0}
    if !explicit && !RegExMatch(expression, "[+\-*/()]")
        return {Recognized: false, Error: "", Value: 0}

    state := {Text: expression, Position: 1}
    try {
        value := ParseArithmeticExpression(state)
        SkipArithmeticWhitespace(state)
        if state.Position <= StrLen(state.Text)
            throw Error("Invalid calculation")
        return {Recognized: true, Error: "", Value: value}
    } catch as problem {
        message := problem.Message = "Cannot divide by zero"
            ? problem.Message : "Invalid calculation"
        return {Recognized: true, Error: message, Value: 0}
    }
}

SkipArithmeticWhitespace(state) {
    while RegExMatch(SubStr(state.Text, state.Position, 1), "\s")
        state.Position += 1
}

ParseArithmeticExpression(state) {
    value := ParseArithmeticTerm(state)
    loop {
        SkipArithmeticWhitespace(state)
        operator := SubStr(state.Text, state.Position, 1)
        if operator != "+" && operator != "-"
            break
        state.Position += 1
        right := ParseArithmeticTerm(state)
        value := operator = "+" ? value + right : value - right
    }
    return value
}

ParseArithmeticTerm(state) {
    value := ParseArithmeticPrimary(state)
    loop {
        SkipArithmeticWhitespace(state)
        operator := SubStr(state.Text, state.Position, 1)
        if operator != "*" && operator != "/"
            break
        state.Position += 1
        right := ParseArithmeticPrimary(state)
        if operator = "/" && right = 0
            throw Error("Cannot divide by zero")
        value := operator = "*" ? value * right : value / right
    }
    return value
}

ParseArithmeticPrimary(state) {
    SkipArithmeticWhitespace(state)
    character := SubStr(state.Text, state.Position, 1)
    if character = "+" || character = "-" {
        state.Position += 1
        value := ParseArithmeticPrimary(state)
        return character = "-" ? -value : value
    }
    if character = "(" {
        state.Position += 1
        value := ParseArithmeticExpression(state)
        SkipArithmeticWhitespace(state)
        if SubStr(state.Text, state.Position, 1) != ")"
            throw Error("Missing closing parenthesis")
        state.Position += 1
        return value
    }

    start := state.Position
    dots := 0
    loop {
        character := SubStr(state.Text, state.Position, 1)
        if RegExMatch(character, "\d") {
            state.Position += 1
        } else if character = "." && dots = 0 {
            dots += 1
            state.Position += 1
        } else {
            break
        }
    }
    numberText := SubStr(state.Text, start, state.Position - start)
    if numberText = "" || numberText = "."
        throw Error("Expected a number")
    return numberText + 0
}

FormatCalculationNumber(value) {
    if Abs(value) < 0.000000000001
        value := 0
    formatted := Format("{:.10f}", value)
    formatted := RegExReplace(formatted, "(\.\d*?)0+$", "$1")
    return RegExReplace(formatted, "\.$")
}

FilterChoices(query) {
    global Snippets, DetailParent, SearchServiceParent, CategoryParent, SheetInfos, SheetId

    needle := StrLower(Trim(query))
    if !DetailParent && !SearchServiceParent && CategoryParent = ""
        && SubStr(needle, 1, 1) = "/" {
        filter := Trim(SubStr(needle, 2))
        choices := []
        for info in SheetInfos {
            if filter != "" && !InStr(StrLower(info.Name), filter)
                continue
            url := "https://docs.google.com/spreadsheets/d/" SheetId "/edit#gid=" info.Gid
            common := {Label: info.Name, GroupLabel: info.Name, Category: info.Name,
                Content: "", HasSavedContent: false, Aliases: [], Details: [],
                DetailSearch: "", Preview: "", EditUrl: url}
            browse := common.Clone()
            browse.Key := "tab:browse:" info.Name
            browse.DisplayText := info.Name
            browse.Preview := "Browse entries"
            browse.IsCategoryChoice := true
            choices.Push(browse)
            open := common.Clone()
            open.Key := "tab:open:" info.Name
            open.DisplayText := info.Name
            open.Preview := "Open in Google Sheets"
            open.IsCategoryOpenChoice := true
            choices.Push(open)
        }
        return choices
    }
    if SearchServiceParent {
        cleaned := Trim(query)
        if cleaned = ""
            return []
        return [{
            Type: "search-query",
            Key: "search-query:" SearchServiceParent.Key,
            Label: cleaned,
            GroupLabel: SearchServiceParent.GroupLabel,
            DisplayText: "Search " SearchServiceParent.GroupLabel " for “" cleaned "”",
            Content: "",
            HasSavedContent: false,
            Category: SearchServiceParent.Category,
            Aliases: [],
            Details: [],
            DetailSearch: "",
            Preview: "Enter to open in the default browser",
            SearchQuery: cleaned,
            SearchService: SearchServiceParent
        }]
    }
    ; The root view opens with locally remembered Sheet items. Typing searches
    ; the complete workbook; nested views reveal their saved details.
    if !DetailParent && CategoryParent = "" && needle = ""
        return HomeChoices()
    ranked := []
    source := DetailParent ? DetailParent.Details : Snippets

    for item in source {
        if CategoryParent != "" && (item.Category != CategoryParent
            || (item.HasOwnProp("DetailName") && item.DetailName != ""))
            continue
        label := StrLower(DetailParent ? item.DetailName : item.Label)
        category := StrLower(item.Category)
        directContent := StrLower(item.Content)
        nestedContent := StrLower(item.DetailSearch)
        aliasExact := false
        aliasPrefix := false
        aliasContains := false
        aliasLength := 2147483647

        if !DetailParent && needle != "" {
            for alias in item.Aliases {
                if alias = needle
                    aliasExact := true
                if SubStr(alias, 1, StrLen(needle)) = needle {
                    aliasPrefix := true
                    aliasLength := Min(aliasLength, StrLen(alias))
                }
                if InStr(alias, needle)
                    aliasContains := true
            }
        }

        rank := -1
        if needle = ""
            rank := 0
        else if aliasExact
            rank := 0
        else if aliasPrefix
            rank := 1
        else if label = needle
            rank := 2
        else if SubStr(label, 1, StrLen(needle)) = needle
            rank := 3
        else if aliasContains
            rank := 4
        else if InStr(label, needle)
            rank := 5
        else if !DetailParent && SubStr(category, 1, StrLen(needle)) = needle
            rank := 6
        else if !DetailParent && InStr(category, needle)
            rank := 7
        else if InStr(directContent, needle)
            rank := 8
        else if !DetailParent && InStr(nestedContent, needle)
            rank := 9

        if rank >= 0
            ranked.Push({Item: item, Rank: rank, AliasLength: aliasLength})
    }

    if needle != ""
        InsertionSort ranked, CompareRanked
    choices := []
    utility := !DetailParent && CategoryParent = "" ? BuildUtilityChoice(query) : 0
    if utility
        choices.Push(utility)
    ; Explicit aliases also precede calculated/search utility suggestions.
    if utility && ranked.Length && ranked[1].Rank = 0 {
        choices := []
        for entry in ranked {
            if entry.Rank = 0
                choices.Push(entry.Item)
        }
        choices.Push(utility)
        for entry in ranked {
            if entry.Rank != 0
                choices.Push(entry.Item)
        }
    } else {
        for entry in ranked
            choices.Push(entry.Item)
    }
    return choices
}

SameRecentItem(entry, choice) {
    detailName := choice.HasOwnProp("DetailName") ? choice.DetailName : ""
    return StrLower(Trim(entry.Category)) = StrLower(Trim(choice.Category))
        && StrLower(Trim(entry.GroupLabel)) = StrLower(Trim(choice.GroupLabel))
        && StrLower(Trim(entry.DetailName)) = StrLower(Trim(detailName))
}

RecordRecent(choice) {
    global RecentItems, RecentLimit

    if !choice || !choice.HasOwnProp("Category")
        || !choice.HasOwnProp("GroupLabel")
        || (choice.HasOwnProp("Type") && choice.Type = "utility")
        || Trim(choice.Category) = "" || Trim(choice.GroupLabel) = ""
        return

    detailName := choice.HasOwnProp("DetailName") ? choice.DetailName : ""
    updated := [{
        Category: choice.Category,
        GroupLabel: choice.GroupLabel,
        DetailName: detailName
    }]
    for entry in RecentItems {
        if !SameRecentItem(entry, choice) && updated.Length < RecentLimit
            updated.Push(entry)
    }
    RecentItems := updated
    SaveRecentItems()
}

RecentChoices() {
    global RecentItems, RecentLimit, Snippets

    choices := []
    for entry in RecentItems {
        found := false
        for root in Snippets {
            if StrLower(Trim(entry.Category)) != StrLower(Trim(root.Category))
                || StrLower(Trim(entry.GroupLabel)) != StrLower(Trim(root.GroupLabel))
                continue

            if Trim(entry.DetailName) = "" {
                choices.Push(root)
                found := true
            } else {
                for detail in root.Details {
                    if StrLower(Trim(entry.DetailName))
                        = StrLower(Trim(detail.DetailName)) {
                        recent := detail.Clone()
                        recent.DisplayText := recent.GroupLabel " — " recent.DetailName
                        recent.Label := recent.DisplayText
                        choices.Push(recent)
                        found := true
                        break
                    }
                }
            }
            if found
                break
        }
        if choices.Length >= RecentLimit
            break
    }
    return choices
}

IsInboxCategory(category) {
    global InboxSheet
    target := NormalizeSheetName(InboxSheet != "" ? InboxSheet : "Inbox")
    if NormalizeSheetName(category) = target
        return true
    parts := StrSplit(category, " · ")
    return parts.Length > 1 && NormalizeSheetName(parts[parts.Length]) = target
}

LatestInboxChoice() {
    global Snippets
    for item in Snippets {
        isDetail := item.HasOwnProp("DetailName") && Trim(item.DetailName) != ""
        if IsInboxCategory(item.Category) && !isDetail {
            pinned := item.Clone()
            pinned.IsPinnedInbox := true
            pinned.Preview := "Pinned latest"
                . (Trim(pinned.Preview) != "" ? "  •  " pinned.Preview : "")
            return pinned
        }
    }
    return 0
}

HomeChoices() {
    global RecentLimit
    choices := []
    pinned := LatestInboxChoice()
    if pinned
        choices.Push(pinned)
    for choice in RecentChoices() {
        if pinned && choice.Key = pinned.Key
            continue
        if choices.Length >= RecentLimit
            break
        choices.Push(choice)
    }
    return choices
}

CompareRanked(a, b) {
    if a.Rank != b.Rank
        return a.Rank < b.Rank ? -1 : 1
    if a.Rank = 1 && a.AliasLength != b.AliasLength
        return a.AliasLength < b.AliasLength ? -1 : 1
    return 0
}

InsertionSort(items, compare) {
    index := 2
    while index <= items.Length {
        current := index
        while current > 1 && compare(items[current], items[current - 1]) < 0 {
            temporary := items[current - 1]
            items[current - 1] := items[current]
            items[current] := temporary
            current -= 1
        }
        index += 1
    }
}

RenderChoices(choices) {
    global ResultsView, VisibleChoices

    VisibleChoices := choices
    ResultsView.Opt("-Redraw")
    ResultsView.Delete()

    for index, choice in choices {
        shortcut := index <= 9 ? "Ctrl+" index : ""
        label := choice.HasOwnProp("DisplayText") ? choice.DisplayText : choice.Label
        supporting := choice.Category
            . (choice.Preview != "" ? "  •  " choice.Preview : "")
        ResultsView.Add("", shortcut, label, supporting)
    }

    ResultsView.Opt("+Redraw")
    if choices.Length > 0
        ResultsView.Modify(1, "Select Focus Vis")
}

ChooseVisibleByNumber(number) {
    global VisibleChoices

    if number >= 1 && number <= VisibleChoices.Length
        ChooseChoice VisibleChoices[number]
}

MoveSelection(direction) {
    global ResultsView

    count := ResultsView.GetCount()
    if count = 0
        return
    row := ResultsView.GetNext(0, "F")
    if row = 0
        row := 1
    else
        row := Max(1, Min(count, row + direction))
    ResultsView.Modify(0, "-Select -Focus")
    ResultsView.Modify(row, "Select Focus Vis")
}

SelectedChoice() {
    global ResultsView, VisibleChoices

    row := ResultsView.GetNext(0, "F")
    ; With RowType omitted, GetNext returns the next selected row.
    if row = 0
        row := ResultsView.GetNext(0)
    if row < 1 || row > VisibleChoices.Length
        return 0
    return VisibleChoices[row]
}

ChooseSelected(*) {
    global SearchBox, DetailParent, SearchServiceParent, CategoryParent

    choice := SelectedChoice()
    if !choice {
        if !DetailParent && !SearchServiceParent && CategoryParent = ""
            && Trim(SearchBox.Value) != "" && SubStr(Trim(SearchBox.Value), 1, 1) != "/"
            SearchGoogleQuery()
        return
    }
    ChooseChoice choice
}

ResultClicked(control, row) {
    global VisibleChoices

    if row < 1 || row > VisibleChoices.Length
        return

    choice := VisibleChoices[row]
    if choice.HasOwnProp("IsUtilityError") && choice.IsUtilityError
        return

    control.Modify(0, "-Select -Focus")
    control.Modify(row, "Select Focus Vis")
    ChooseChoice choice
}

ChooseChoice(choice) {
    if IsAutomationChoice(choice) {
        RunAutomation choice.ScriptId, choice
        return
    }
    if choice.HasOwnProp("IsCategoryChoice") && choice.IsCategoryChoice {
        OpenCategory choice
        return
    }
    if choice.HasOwnProp("IsCategoryOpenChoice") && choice.IsCategoryOpenChoice {
        EditSelectedChoice choice
        return
    }
    if choice.HasOwnProp("Type") && choice.Type = "search-query" {
        LaunchSearchQuery choice
        return
    }
    if choice.HasOwnProp("IsSearchService") && choice.IsSearchService {
        OpenSearchService choice
        return
    }
    if choice.HasOwnProp("Type") && choice.Type = "action" {
        if choice.HasOwnProp("Available") && !choice.Available
            return
        PerformAction choice.ActionId
        return
    }
    if choice.HasOwnProp("IsUtilityError") && choice.IsUtilityError
        return
    if OpenChoiceLink(choice, true)
        return
    PasteChoice choice
}

PasteChoice(choice) {
    if choice.HasOwnProp("HasSavedContent") && !choice.HasSavedContent {
        if choice.HasOwnProp("AiPrompt") && Trim(choice.AiPrompt) != ""
            LaunchAiPrompt choice
        else
            TrayTip "No saved text or AI prompt is configured.", "Trigger Search"
        return
    }
    RecordRecent choice
    clipboardText := A_Clipboard
    expanded := ExpandDynamicContent(choice.Content, clipboardText)
    PasteExpanded expanded
}

PasteExpanded(expanded) {
    global TargetWindow, ChooserGui, ChooserOpen, AtBoundary

    try savedClipboard := ClipboardAll()
    catch
        savedClipboard := A_Clipboard
    ChooserGui.Hide()
    ChooserOpen := false
    A_Clipboard := expanded.Text
    if !ClipWait(1) {
        A_Clipboard := savedClipboard
        return
    }

    if !TargetWindow || !WinExist("ahk_id " TargetWindow) {
        A_Clipboard := savedClipboard
        TrayTip "The original window is no longer available.", "Trigger Search"
        return
    }
    try WinActivate "ahk_id " TargetWindow
    try targetActive := WinWaitActive("ahk_id " TargetWindow, , 0.5)
    catch
        targetActive := 0
    if !targetActive {
        A_Clipboard := savedClipboard
        TrayTip "Could not return to the original window.", "Trigger Search"
        return
    }
    Sleep 30
    Send "^v"
    if expanded.CursorLeft > 0 {
        Sleep 50
        Send "{Left " expanded.CursorLeft "}"
        Sleep 200
    } else {
        Sleep 250
    }
    A_Clipboard := savedClipboard
    AtBoundary := RegExMatch(expanded.Text, "\s$") != 0
}

ExtractLaunchUrl(text) {
    candidates := []
    seen := Map()
    position := 1
    pattern := "i)https?://[^\s<>" Chr(34) "']+"
    while found := RegExMatch(text, pattern, &match, position) {
        AddLaunchCandidate candidates, seen, match[0], false
        position := found + match.Len(0)
    }

    position := 1
    pattern := "i)(?:[a-z0-9-]+\.)+[a-z]{2,}(?:[/?#][^\s<>" Chr(34) "']*)?"
    while found := RegExMatch(text, pattern, &match, position) {
        previous := found > 1 ? SubStr(text, found - 1, 1) : ""
        if previous != "@" && !RegExMatch(previous, "[A-Za-z0-9_]")
            AddLaunchCandidate candidates, seen, match[0], true
        position := found + match.Len(0)
    }

    return candidates.Length = 1 ? candidates[1] : ""
}

ExtractStandaloneLaunchUrl(text) {
    original := Trim(text)
    launchUrl := ExtractLaunchUrl(original)
    if launchUrl = ""
        return ""
    if original = launchUrl || "https://" original = launchUrl
        return launchUrl
    return ""
}

AddLaunchCandidate(candidates, seen, candidate, needsProtocol) {
    candidate := RegExReplace(candidate, "[\)\]\}\.,;:!?]+$")
    if candidate = ""
        return
    normalized := needsProtocol ? "https://" candidate : candidate
    if !seen.Has(normalized) {
        candidates.Push(normalized)
        seen[normalized] := true
    }
}

ExpandDynamicContent(text, clipboardText := "", timestamp := "") {
    if timestamp = ""
        timestamp := A_Now

    output := ""
    searchAt := 1
    cursorPosition := 0
    hasCursor := false

    while foundAt := RegExMatch(text, "\{([^{}\r\n]+)\}", &match, searchAt) {
        output .= SubStr(text, searchAt, foundAt - searchAt)
        placeholder := ExpandDynamicPlaceholder(
            Trim(match[1]), clipboardText, timestamp)
        if placeholder.Recognized {
            if placeholder.IsCursor && !hasCursor {
                cursorPosition := StrLen(output)
                hasCursor := true
            }
            output .= placeholder.Value
        } else {
            output .= match[0]
        }
        searchAt := foundAt + StrLen(match[0])
    }
    output .= SubStr(text, searchAt)

    return {
        Text: output,
        CursorLeft: hasCursor ? StrLen(output) - cursorPosition : 0
    }
}

ExpandDynamicPlaceholder(body, clipboardText, timestamp) {
    if body = "clipboard"
        return {Recognized: true, IsCursor: false, Value: clipboardText}
    if body = "cursor"
        return {Recognized: true, IsCursor: true, Value: ""}

    if !RegExMatch(body, "i)^(date|time|datetime|day)(?:\s|$)", &match)
        return {Recognized: false, IsCursor: false, Value: ""}

    keyword := StrLower(match[1])
    defaultFormats := Map(
        "date", "MM/dd/yyyy",
        "time", "h:mm a",
        "datetime", "MM/dd/yyyy h:mm a",
        "day", "EEEE"
    )
    formatPattern := PlaceholderAttribute(body, "format")
    if formatPattern = ""
        formatPattern := defaultFormats[keyword]
    offset := PlaceholderAttribute(body, "offset")
    shifted := ApplyDateOffset(timestamp, offset)
    return {
        Recognized: true,
        IsCursor: false,
        Value: FormatDynamicDate(shifted, formatPattern)
    }
}

PlaceholderAttribute(body, name) {
    quote := Chr(34)
    quotedPattern := "i)\b" name "\s*=\s*" quote "([^" quote "]*)" quote
    if RegExMatch(body, quotedPattern, &match)
        return match[1]
    if RegExMatch(body, "i)\b" name "\s*=\s*([^\s]+)", &match)
        return match[1]
    return ""
}

ApplyDateOffset(timestamp, offsetText) {
    shifted := timestamp
    searchAt := 1
    while foundAt := RegExMatch(
        offsetText, "([+-])(\d+)([yMdhm])", &match, searchAt) {
        amount := Integer(match[2])
        if match[1] = "-"
            amount := -amount

        unit := match[3]
        if unit = "y"
            shifted := AddCalendarMonths(shifted, amount * 12)
        else if unit = "M"
            shifted := AddCalendarMonths(shifted, amount)
        else if unit = "d"
            shifted := DateAdd(shifted, amount, "Days")
        else if unit = "h"
            shifted := DateAdd(shifted, amount, "Hours")
        else if unit = "m"
            shifted := DateAdd(shifted, amount, "Minutes")

        searchAt := foundAt + StrLen(match[0])
    }
    return shifted
}

AddCalendarMonths(timestamp, amount) {
    year := Integer(SubStr(timestamp, 1, 4))
    month := Integer(SubStr(timestamp, 5, 2))
    day := Integer(SubStr(timestamp, 7, 2))
    zeroBasedMonth := year * 12 + month - 1 + amount
    newYear := Floor(zeroBasedMonth / 12)
    newMonth := Mod(zeroBasedMonth, 12) + 1
    if newMonth <= 0 {
        newMonth += 12
        newYear -= 1
    }
    newDay := Min(day, DaysInMonth(newYear, newMonth))
    return Format("{:04}{:02}{:02}", newYear, newMonth, newDay)
        . SubStr(timestamp, 9)
}

DaysInMonth(year, month) {
    if month = 2 {
        isLeapYear := Mod(year, 400) = 0
            || (Mod(year, 4) = 0 && Mod(year, 100) != 0)
        return isLeapYear ? 29 : 28
    }
    return InStr(",1,3,5,7,8,10,12,", "," month ",") ? 31 : 30
}

FormatDynamicDate(timestamp, formatPattern) {
    hour24 := Integer(FormatTime(timestamp, "HH"))
    hour12 := Mod(hour24, 12)
    if hour12 = 0
        hour12 := 12

    values := Map(
        "EEEE", FormatTime(timestamp, "dddd"),
        "MMMM", FormatTime(timestamp, "MMMM"),
        "yyyy", FormatTime(timestamp, "yyyy"),
        "EEE", FormatTime(timestamp, "ddd"),
        "MMM", FormatTime(timestamp, "MMM"),
        "SSS", "000",
        "yy", FormatTime(timestamp, "yy"),
        "MM", FormatTime(timestamp, "MM"),
        "dd", FormatTime(timestamp, "dd"),
        "HH", FormatTime(timestamp, "HH"),
        "hh", Format("{:02}", hour12),
        "mm", FormatTime(timestamp, "mm"),
        "ss", FormatTime(timestamp, "ss"),
        "M", Integer(FormatTime(timestamp, "MM")),
        "d", Integer(FormatTime(timestamp, "dd")),
        "H", hour24,
        "h", hour12,
        "m", Integer(FormatTime(timestamp, "mm")),
        "s", Integer(FormatTime(timestamp, "ss")),
        "a", FormatTime(timestamp, "tt")
    )
    tokenOrder := [
        "EEEE", "MMMM", "yyyy", "EEE", "MMM", "SSS",
        "yy", "MM", "dd", "HH", "hh", "mm", "ss",
        "M", "d", "H", "h", "m", "s", "a"
    ]

    output := ""
    index := 1
    literal := false
    while index <= StrLen(formatPattern) {
        character := SubStr(formatPattern, index, 1)
        if character = "'" {
            if SubStr(formatPattern, index + 1, 1) = "'" {
                output .= "'"
                index += 2
            } else {
                literal := !literal
                index += 1
            }
            continue
        }
        if literal {
            output .= character
            index += 1
            continue
        }

        matched := false
        for token in tokenOrder {
            if SubStr(formatPattern, index, StrLen(token)) = token {
                output .= values[token]
                index += StrLen(token)
                matched := true
                break
            }
        }
        if !matched {
            output .= character
            index += 1
        }
    }
    return output
}

OpenSelectedAction(*) {
    global DetailParent, SearchServiceParent, RootQuery, SearchBox, ReturnParentKey

    choice := SelectedChoice()
    if !choice
        return
    if IsAutomationChoice(choice) {
        RunAutomation choice.ScriptId, choice
        return
    }
    if choice.HasOwnProp("IsCategoryChoice") && choice.IsCategoryChoice {
        OpenCategory choice
        return
    }
    if choice.HasOwnProp("IsCategoryOpenChoice") && choice.IsCategoryOpenChoice {
        EditSelectedChoice choice
        return
    }

    if !DetailParent && !SearchServiceParent
        && choice.HasOwnProp("IsSearchService") && choice.IsSearchService {
        OpenSearchService choice
        return
    }

    if DetailParent || !choice.HasOwnProp("Details")
        || choice.Details.Length = 0 {
        OpenChoiceLink choice, true
        return
    }

    RootQuery := SearchBox.Value
    ReturnParentKey := choice.Key
    DetailParent := choice
    UpdateChooserContext()
    SearchBox.Value := ""
    RenderChoices(FilterChoices(""))
    SearchBox.Focus()
}

OpenCategory(choice) {
    global CategoryParent, RootQuery, SearchBox

    CategoryParent := choice.Category
    RootQuery := ""
    SetSearchPlaceholder("←  " choice.Category)
    SearchBox.Value := ""
    RenderChoices(FilterChoices(""))
    UpdateChooserContext()
    SetSearchPlaceholder("←  " choice.Category)
    SearchBox.Focus()
}

OpenSearchService(choice) {
    global SearchServiceParent, RootQuery, SearchBox, ReturnParentKey

    RootQuery := SearchBox.Value
    ReturnParentKey := choice.Key
    SearchServiceParent := choice
    UpdateChooserContext()
    SetSearchPlaceholder("←  " choice.GroupLabel)
    SearchBox.Value := ""
    RenderChoices([])
    SearchBox.Focus()
}

OpenSelectedLink(*) {
    global ActionsForChoice
    HideModifierHud()
    if ActionsForChoice {
        OpenChoiceLink ActionsForChoice, false
        ActionsForChoice := 0
        return
    }
    choice := SelectedChoice()
    if choice
        OpenChoiceLink choice, false
}

OpenChoiceLink(choice, standaloneOnly := false) {
    global ChooserGui, ChooserOpen, AtBoundary

    expanded := ExpandDynamicContent(choice.Content, A_Clipboard)
    launchUrl := standaloneOnly
        ? ExtractStandaloneLaunchUrl(expanded.Text)
        : ExtractLaunchUrl(expanded.Text)
    if launchUrl = ""
        return false
    RecordRecent choice
    ChooserGui.Hide()
    ChooserOpen := false
    AtBoundary := true
    Run launchUrl
    return true
}

CloseDetails(*) {
    global DetailParent, SearchServiceParent, CategoryParent, SearchBox, RootQuery, ReturnParentKey
    global ResultsView, VisibleChoices

    global ActionsForChoice
    if ActionsForChoice {
        CloseActions()
        return
    }
    if SearchServiceParent
        SearchServiceParent := 0
    else if DetailParent
        DetailParent := 0
    else if CategoryParent != "" {
        CategoryParent := ""
        RootQuery := ""
    }
    else
        return
    UpdateChooserContext()
    SearchBox.Value := RootQuery
    RenderChoices(FilterChoices(RootQuery))

    for index, choice in VisibleChoices {
        if choice.Key = ReturnParentKey {
            ResultsView.Modify(0, "-Select -Focus")
            ResultsView.Modify(index, "Select Focus Vis")
            break
        }
    }
    SearchBox.Focus()
}

EditSelected(*) {
    global ChooserGui, ChooserOpen, ActionsForChoice
    HideModifierHud()

    if ActionsForChoice {
        choice := ActionsForChoice
        ActionsForChoice := 0
        EditSelectedChoice choice
        return
    }

    choice := SelectedChoice()
    if !choice || !choice.EditUrl
        return
    RecordRecent choice
    ChooserGui.Hide()
    ChooserOpen := false
    Run choice.EditUrl
}

CopySelected(*) {
    global ChooserGui, ChooserOpen, AtBoundary, ActionsForChoice
    HideModifierHud()

    if ActionsForChoice {
        choice := ActionsForChoice
        ActionsForChoice := 0
        CopyChoice choice
        return
    }

    choice := SelectedChoice()
    if !choice || (choice.HasOwnProp("IsUtilityError") && choice.IsUtilityError)
        return
    if choice.HasOwnProp("HasSavedContent") && !choice.HasSavedContent {
        TrayTip "No saved text to copy.", "Trigger Search"
        return
    }
    RecordRecent choice
    expanded := ExpandDynamicContent(choice.Content, A_Clipboard)
    ChooserGui.Hide()
    ChooserOpen := false
    A_Clipboard := expanded.Text
    ClipWait(1)
    AtBoundary := true
}

BuildAiPrompt(choice) {
    if !choice || !choice.HasOwnProp("AiPrompt") || Trim(choice.AiPrompt) = ""
        return ""
    prompt := choice.AiPrompt
    item := choice.HasOwnProp("GroupLabel") ? choice.GroupLabel : choice.Label
    replaced := false
    for token in ["{medication}", "{item}", "{label}"] {
        before := prompt
        prompt := StrReplace(prompt, token, item, false)
        prompt := StrReplace(prompt, StrUpper(token), item, false)
        if prompt != before
            replaced := true
    }
    if !replaced && Trim(item) != "" {
        contextName := InStr(StrLower(choice.Category), "med") ? "Medication" : "Item"
        prompt .= "`n`n" contextName ": " item
    }
    return prompt
}

UrlEncode(value) {
    size := StrPut(value, "UTF-8")
    encodedBytes := Buffer(size)
    StrPut value, encodedBytes, "UTF-8"
    output := ""
    Loop size - 1 {
        byte := NumGet(encodedBytes, A_Index - 1, "UChar")
        if (byte >= 0x30 && byte <= 0x39)
            || (byte >= 0x41 && byte <= 0x5A)
            || (byte >= 0x61 && byte <= 0x7A)
            || byte = 0x2D || byte = 0x2E || byte = 0x5F || byte = 0x7E
            output .= Chr(byte)
        else
            output .= Format("%{:02X}", byte)
    }
    return output
}

LaunchSearchQuery(choice) {
    global ChooserGui, ChooserOpen, AtBoundary

    if !choice || !choice.HasOwnProp("SearchService")
        return false
    service := choice.SearchService
    template := service.HasOwnProp("SearchTemplate")
        ? Trim(service.SearchTemplate) : ""
    query := choice.HasOwnProp("SearchQuery") ? Trim(choice.SearchQuery) : ""
    if query = "" || !InStr(template, "$")
        return false
    url := StrReplace(template, "$", UrlEncode(query))
    if !RegExMatch(url, "i)^https?://")
        return false
    RecordRecent service
    HideModifierHud()
    ChooserGui.Hide()
    ChooserOpen := false
    AtBoundary := true
    Run url
    return true
}

SearchGoogleQuery(*) {
    global SearchBox, ChooserGui, ChooserOpen, AtBoundary

    phrase := Trim(SearchBox.Value)
    if phrase = "" {
        TrayTip "Type a Google search first.", "Trigger Search"
        return false
    }
    HideModifierHud()
    ChooserGui.Hide()
    ChooserOpen := false
    AtBoundary := true
    Run "https://www.google.com/search?q=" UrlEncode(phrase)
    return true
}

LaunchSelectedAi(*) {
    global ActionsForChoice
    HideModifierHud()
    if ActionsForChoice {
        choice := ActionsForChoice
        ActionsForChoice := 0
        LaunchAiPrompt choice
        return
    }
    choice := SelectedChoice()
    if choice
        LaunchAiPrompt choice
}

LaunchAiPrompt(choice) {
    global AiEngine, ChooserGui, ChooserOpen, AtBoundary
    prompt := BuildAiPrompt(choice)
    if prompt = "" {
        TrayTip "No AI prompt is configured for this item.", "Trigger Search"
        return
    }
    RecordRecent choice
    A_Clipboard := prompt
    ClipWait 1
    ChooserGui.Hide()
    ChooserOpen := false
    AtBoundary := true
    engine := RegExReplace(StrLower(Trim(AiEngine)), "[\s_-]+")
    if engine = "googleaimode" || engine = "googleai"
        Run "https://www.google.com/search?udm=50&q=" UrlEncode(prompt)
    else if engine = "microsoftcopilot" || engine = "copilot" {
        Run "https://copilot.microsoft.com/"
        TrayTip "AI prompt copied. Paste it into Copilot.", "Trigger Search"
    } else
        Run "https://chatgpt.com/?q=" UrlEncode(prompt)
}

CopyAiPrompt(choice) {
    global ChooserGui, ChooserOpen, AtBoundary
    prompt := BuildAiPrompt(choice)
    if prompt = "" {
        TrayTip "No AI prompt is configured for this item.", "Trigger Search"
        return
    }
    RecordRecent choice
    A_Clipboard := prompt
    ClipWait 1
    ChooserGui.Hide()
    ChooserOpen := false
    AtBoundary := true
}

ShowActionsMenu(*) {
    global ActionsForChoice, ActionsReturnQuery, ActionsReturnKey
    global SearchBox, VisibleChoices, ResultsView, FooterText, ChooserGui, AiEngine
    HideModifierHud()
    choice := SelectedChoice()
    if !choice || (choice.HasOwnProp("Type") && choice.Type = "action")
        return
    ActionsForChoice := choice
    ActionsReturnQuery := SearchBox.Value
    ActionsReturnKey := choice.Key
    actions := []
    hasSavedContent := (!choice.HasOwnProp("HasSavedContent")
        || choice.HasSavedContent) && Trim(choice.Content) != ""
    hasAi := choice.HasOwnProp("AiPrompt") && Trim(choice.AiPrompt) != ""
    hasLink := choice.HasOwnProp("Content") && ExtractLaunchUrl(choice.Content) != ""
    hasEdit := choice.HasOwnProp("EditUrl") && choice.EditUrl != ""
    if IsAutomationChoice(choice)
        actions.Push(ActionChoice("run", "Run automation", "Enter"))
    actions.Push(ActionChoice("paste", "Paste", "Return", hasSavedContent))
    actions.Push(ActionChoice("preview", "Preview", "Ctrl+P", hasSavedContent))
    actions.Push(ActionChoice("copy", "Copy", "Ctrl+C", hasSavedContent))
    aiShortcut := hasSavedContent ? "Ctrl+Enter  •  " AiEngine
        : "Enter or Ctrl+Enter  •  " AiEngine
    actions.Push(ActionChoice("ai", "Ask AI", aiShortcut, hasAi))
    actions.Push(ActionChoice("copyAi", "Copy AI prompt",
        "Copy the prepared prompt", hasAi))
    actions.Push(ActionChoice("open", "Open link", "Ctrl+O", hasLink))
    actions.Push(ActionChoice("edit", "Edit in Google Sheets", "Ctrl+E", hasEdit))
    SearchBox.Value := ""
    SearchBox.Enabled := false
    actionLabel := choice.HasOwnProp("GroupLabel")
        ? choice.GroupLabel : choice.DisplayText
    SetSearchPlaceholder("←  Actions for " actionLabel)
    ChooserGui.Title := "Trigger Search — ← Actions"
    FooterText.Text := "Left Arrow returns  •  Escape closes"
    FooterText.Visible := true
    VisibleChoices := actions
    ResultsView.Delete()
    for index, action in actions
        ResultsView.Add("", "Ctrl+" index, action.DisplayText, action.Preview)
    if actions.Length
        ResultsView.Modify(1, "Select Focus Vis")
}

ActionChoice(actionId, label, preview, available := true) {
    marker := available ? "●" : "○"
    return {Type: "action", ActionId: actionId, Key: "action:" actionId,
        Label: label, DisplayText: marker "  " label, Preview: preview, Content: "",
        Available: available}
}

PerformAction(actionId) {
    global ActionsForChoice
    choice := ActionsForChoice
    if actionId = "back" {
        CloseActions()
        return
    }
    if actionId = "run"
        RunAutomation choice.ScriptId, choice
    else if actionId = "paste"
        PasteChoice choice
    else if actionId = "preview" {
        CloseActions()
        PreviewChoice choice
        return
    }
    else if actionId = "copy"
        CopyChoice choice
    else if actionId = "ai"
        LaunchAiPrompt choice
    else if actionId = "copyAi"
        CopyAiPrompt choice
    else if actionId = "open"
        OpenChoiceLink choice, false
    else if actionId = "edit" {
        CloseActions()
        EditSelectedChoice choice
    }
    ActionsForChoice := 0
}

PreviewSelected(*) {
    global ActionsForChoice
    HideModifierHud()

    choice := ActionsForChoice ? ActionsForChoice : SelectedChoice()
    if !choice
        return
    if ActionsForChoice
        CloseActions()
    PreviewChoice choice
}

PreviewChoice(choice) {
    global PreviewGui, PreviewOpen, ChooserGui, PreviewChoiceValue
    global PreviewExpanded

    if !choice || (choice.HasOwnProp("HasSavedContent")
        && !choice.HasSavedContent) || Trim(choice.Content) = "" {
        TrayTip "No saved text is available to preview.", "Trigger Search"
        return
    }

    RecordRecent choice

    expanded := ExpandDynamicContent(choice.Content, A_Clipboard)
    title := choice.HasOwnProp("DetailName") && choice.DetailName != ""
        ? choice.GroupLabel " — " choice.DetailName
        : (choice.HasOwnProp("GroupLabel") ? choice.GroupLabel : choice.Label)

    if IsObject(PreviewGui)
        try PreviewGui.Destroy()
    PreviewGui := Gui("+AlwaysOnTop +ToolWindow", "")
    PreviewGui.BackColor := "F0F0F2"
    PreviewGui.MarginX := 24
    PreviewGui.MarginY := 20
    PreviewGui.SetFont("s16 c222222 Bold", "Segoe UI")
    PreviewGui.Add("Text", "xm w680", title)
    PreviewGui.SetFont("s10 c222222 Norm", "Segoe UI")
    PreviewGui.Add("Edit", "xm y+16 w680 r24 ReadOnly BackgroundF0F0F2", expanded.Text)
    PreviewGui.SetFont("s9 c888888", "Segoe UI")
    PreviewGui.Add("Text", "xm y+10 w680 Right", "P  Paste     C  Copy     Esc  Close")
    PreviewGui.OnEvent("Close", ClosePreview)
    PreviewGui.OnEvent("Escape", CloseLauncher)

    ChooserGui.Hide()
    PreviewChoiceValue := choice
    PreviewExpanded := expanded
    PreviewOpen := true
    PreviewGui.Show("w728 h590 Center")
}

ClosePreview(restoreChooser := true) {
    global PreviewGui, PreviewOpen, ChooserGui, SearchBox, ChooserOpen
    global PreviewChoiceValue, PreviewExpanded

    if !PreviewOpen
        return
    PreviewOpen := false
    if IsObject(PreviewGui) {
        try PreviewGui.Destroy()
        PreviewGui := 0
    }
    PreviewChoiceValue := 0
    PreviewExpanded := 0
    if restoreChooser && ChooserOpen {
        ChooserGui.Show()
        SearchBox.Focus()
    }
}

PastePreview(*) {
    global PreviewChoiceValue, PreviewExpanded

    if !PreviewChoiceValue || !PreviewExpanded
        return
    expanded := PreviewExpanded
    ClosePreview(false)
    PasteExpanded expanded
}

CopyPreview(*) {
    global PreviewChoiceValue, PreviewExpanded

    if !PreviewChoiceValue || !PreviewExpanded
        return
    A_Clipboard := PreviewExpanded.Text
    ClipWait 1
    TrayTip "Copied", "Trigger Search"
}

CloseActions(*) {
    global ActionsForChoice, ActionsReturnQuery, ActionsReturnKey
    global SearchBox, ResultsView, VisibleChoices, FooterText
    if !ActionsForChoice
        return
    ActionsForChoice := 0
    SearchBox.Enabled := true
    UpdateChooserContext()
    FooterText.Text := ""
    FooterText.Visible := false
    SearchBox.Value := ActionsReturnQuery
    RenderChoices FilterChoices(ActionsReturnQuery)
    for index, choice in VisibleChoices {
        if choice.Key = ActionsReturnKey {
            ResultsView.Modify(0, "-Select -Focus")
            ResultsView.Modify(index, "Select Focus Vis")
            break
        }
    }
    SearchBox.Focus()
}

CopyChoice(choice) {
    global ChooserGui, ChooserOpen, AtBoundary
    RecordRecent choice
    expanded := ExpandDynamicContent(choice.Content, A_Clipboard)
    ChooserGui.Hide()
    ChooserOpen := false
    A_Clipboard := expanded.Text
    ClipWait 1
    AtBoundary := true
}

EditSelectedChoice(choice) {
    global ChooserGui, ChooserOpen
    if !choice || choice.EditUrl = ""
        return
    RecordRecent choice
    ChooserGui.Hide()
    ChooserOpen := false
    Run choice.EditUrl
}

OpenWorkbook() {
    global SheetId

    if SheetId = "" {
        PromptForGoogleSheet(true)
        return
    }
    Run "https://docs.google.com/spreadsheets/d/" SheetId "/edit"
}

LoadSheetConfiguration() {
    global SettingsPath, ManifestPath, LegacySheetId, SheetId

    SheetId := Trim(IniRead(SettingsPath, "settings", "sheetId", ""))
    if SheetId != "" || !FileExist(ManifestPath)
        return

    ; A cache created by an older version proves this is an existing install.
    cachedSheetId := Trim(IniRead(ManifestPath, "cache", "sheetId", ""))
    SheetId := cachedSheetId != "" ? cachedSheetId : LegacySheetId
    SaveSheetConfiguration()
}

SaveSheetConfiguration() {
    global SettingsPath, SheetId
    IniWrite SheetId, SettingsPath, "settings", "sheetId"
}

RecentSettingsSection() {
    global SheetId
    return "recent-" SheetId
}

LoadRecentItems() {
    global SettingsPath, SheetId, RecentItems, RecentLimit

    RecentItems := []
    if SheetId = ""
        return
    section := RecentSettingsSection()
    Loop RecentLimit {
        category := IniRead(SettingsPath, section, "category" A_Index, "")
        groupLabel := IniRead(SettingsPath, section, "label" A_Index, "")
        detailName := IniRead(SettingsPath, section, "detail" A_Index, "")
        if Trim(category) != "" && Trim(groupLabel) != "" {
            RecentItems.Push({
                Category: category,
                GroupLabel: groupLabel,
                DetailName: detailName
            })
        }
    }
}

SaveRecentItems() {
    global SettingsPath, SheetId, RecentItems, RecentLimit

    if SheetId = ""
        return
    section := RecentSettingsSection()
    Loop RecentLimit {
        if A_Index <= RecentItems.Length {
            entry := RecentItems[A_Index]
            IniWrite entry.Category, SettingsPath, section, "category" A_Index
            IniWrite entry.GroupLabel, SettingsPath, section, "label" A_Index
            IniWrite entry.DetailName, SettingsPath, section, "detail" A_Index
        } else {
            IniWrite "", SettingsPath, section, "category" A_Index
            IniWrite "", SettingsPath, section, "label" A_Index
            IniWrite "", SettingsPath, section, "detail" A_Index
        }
    }
}

ExtractSheetId(value) {
    value := Trim(value)
    if RegExMatch(value, "i)/spreadsheets/d/([A-Za-z0-9_-]+)", &match)
        return match[1]
    if RegExMatch(value, "^[A-Za-z0-9_-]{20,}$")
        return value
    return ""
}

PromptForGoogleSheet(firstRun := false) {
    global SheetId

    title := firstRun ? "Set up Trigger Search" : "Change Google Sheet"
    prompt := "Paste the link to your public Google Sheet."
        . "`n`nIn Google Sheets, use File > Share > Publish to web first."
        . "`nYour choice is saved only on this computer."
    defaultValue := SheetId = "" ? ""
        : "https://docs.google.com/spreadsheets/d/" SheetId "/edit"
    answer := InputBox(prompt, title, "w600 h180", defaultValue)
    if answer.Result != "OK"
        return false

    newSheetId := ExtractSheetId(answer.Value)
    if newSheetId = "" {
        MsgBox "That does not look like a Google Sheets link."
            . "`n`nPaste the complete link from your browser and try again.",
            title
        return false
    }
    return ConnectGoogleSheet(newSheetId, title)
}

ConnectGoogleSheet(newSheetId, title := "Change Google Sheet") {
    global SheetId, SheetInfos, Snippets, Trigger
    global LauncherModifier, LauncherKey
    global LastRefreshError, LastShownRefreshError, RefreshFailureCount

    oldSheetId := SheetId
    oldInfos := SheetInfos
    oldSnippets := Snippets
    oldTrigger := Trigger
    oldLauncherModifier := LauncherModifier
    oldLauncherKey := LauncherKey
    stage := "checking the Google Sheet"

    try {
        DownloadWorkbook newSheetId, &infos, &csvByName, &stage
        SheetId := newSheetId
        LoadRecentItems()
        ApplySheets infos, csvByName
        if Snippets.Length = 0
            throw Error("No usable autocomplete rows were found. Use Name/Alias/Content headers, or one to three headerless columns.")

        SaveCache infos, csvByName
        SaveSheetConfiguration()
        SheetInfos := infos
        LastRefreshError := ""
        LastShownRefreshError := ""
        RefreshFailureCount := 0
        RefreshOpenChooser()
        TrayTip "Google Sheet connected and " Snippets.Length " snippets loaded.",
            "Trigger Search"
        return true
    } catch as problem {
        SheetId := oldSheetId
        LoadRecentItems()
        SheetInfos := oldInfos
        Snippets := oldSnippets
        InstallTrigger oldTrigger
        InstallLauncherHotkey oldLauncherModifier, oldLauncherKey
        report := RecordError(problem, "Connecting a Google Sheet — " stage)
        MsgBox "Trigger Search could not use that Sheet."
            . "`n`n" problem.Message
            . "`n`nMake sure the link is correct and the workbook is published to the web."
            . "`n`nTechnical details were saved to the last error report.",
            title
        return false
    }
}

InstallOriginalScriptsControls(*) {
    updater := A_ScriptDir "\refresh-all.ps1"
    if !FileExist(updater) {
        MsgBox "Use Refresh all scripts to install the managed bundle first.", "Trigger Search"
        return
    }
    Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' updater
        . '" -InstallRoot "' A_ScriptDir '\..\..\.." -AutoHotkeyPath "' A_AhkPath '" -InstallOriginalControls'
}

UpdateScriptFromGitHub(*) {
    refreshScript := A_ScriptDir "\refresh-all.ps1"
    if !FileExist(refreshScript) {
        try {
            refreshScript := CacheDir "\install-trigger-search.ps1"
            Download "https://raw.githubusercontent.com/nathanpuls/trigger-search/codex/unified-windows-20261026/windows/refresh-all.ps1", refreshScript
            Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' refreshScript
                . '" -Ref codex/unified-windows-20261026 -AutoHotkeyPath "' A_AhkPath '"'
        } catch {
            MsgBox "Could not download the installer. Your current installation is unchanged.", "Trigger Search"
        }
        return
    }
    Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' refreshScript
        . '" -InstallRoot "' A_ScriptDir '\..\..\.." -AutoHotkeyPath "' A_AhkPath '"'
}


FetchLiveGitHubFile(url) {
    commitRequest := GitHubRequest(
        "https://api.github.com/repos/nathanpuls/trigger-search/commits/main"
            . "?cacheBust=" A_NowUTC A_MSec,
        "application/vnd.github+json"
    )
    if !RegExMatch(commitRequest, '"sha"\s*:\s*"([0-9a-f]{40})"', &match)
        throw Error("GitHub did not return the current version identifier.")

    return GitHubRequest(url "?ref=" match[1], "application/vnd.github.raw+json")
}

GitHubRequest(url, accept) {
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(5000, 5000, 10000, 15000)
    request.Open("GET", url, false)
    request.SetRequestHeader("Accept", accept)
    request.SetRequestHeader("User-Agent", "SheetAutocomplete")
    request.SetRequestHeader("Cache-Control", "no-cache")
    request.Send()

    if request.Status != 200
        throw Error("GitHub returned HTTP " request.Status ".")
    return request.ResponseText
}

RefreshShouldDefer(force := false) {
    global ChooserOpen, PreviewOpen
    return !force && (ChooserOpen || PreviewOpen || A_TimeIdlePhysical < 1200)
}

RefreshData(force := false, *) {
    global Refreshing, SheetId, SheetInfos, LastRefreshError
    global LastShownRefreshError, RefreshFailureCount, Snippets
    global RefreshPending, LastRefreshTick

    if Refreshing
        return
    if SheetId = ""
        return
    if RefreshShouldDefer(force) {
        RefreshPending := true
        return
    }
    RefreshPending := false
    Refreshing := true
    stage := "starting refresh"

    try {
        DownloadWorkbook SheetId, &infos, &csvByName, &stage
        stage := "parsing the downloaded Sheet tabs"
        ApplySheets infos, csvByName
        stage := "saving the offline cache"
        SaveCache infos, csvByName
        SheetInfos := infos
        LastRefreshError := ""
        LastShownRefreshError := ""
        RefreshFailureCount := 0
        LastRefreshTick := A_TickCount
        RefreshOpenChooser()
    } catch as problem {
        ; Offline use is expected: keep the last successful in-memory/cache copy.
        RefreshFailureCount += 1
        report := RecordError(problem, "Refreshing snippets — " stage)
        location := problem.Line != "" ? " — line " problem.Line : ""
        LastRefreshError := stage ": " problem.Message location
        errorKey := Type(problem) "|" problem.Message "|" problem.Line "|" stage
        if Snippets.Length = 0 && errorKey != LastShownRefreshError {
            LastShownRefreshError := errorKey
            MsgBox report, "Trigger Search data error"
        }
    } finally {
        Refreshing := false
    }
}

RefreshInboxLive() {
    global SheetId, SheetInfos, InboxSheet, Snippets

    if SheetId = "" || SheetInfos.Length = 0
        return false

    targetName := NormalizeSheetName(InboxSheet != "" ? InboxSheet : "Inbox")
    inboxInfo := 0
    for info in SheetInfos {
        if NormalizeSheetName(info.Name) = targetName {
            inboxInfo := info
            break
        }
    }
    if !inboxInfo {
        TrayTip "Inbox tab is not available. Refresh snippets first.", "Trigger Search"
        return false
    }

    ; Never present a cached Inbox row as though this live check succeeded.
    ; Keep non-Inbox snippets intact if Google is temporarily unavailable.
    try {
        cacheBust := A_NowUTC A_MSec
        csv := FetchSheetCsv(inboxInfo, cacheBust, SheetId)
        freshInbox := []
        ParseSheet csv, inboxInfo, freshInbox

        merged := []
        for item in Snippets {
            if !IsInboxCategory(item.Category)
                merged.Push(item)
        }
        for item in freshInbox
            merged.Push(item)
        Snippets := merged
    } catch as problem {
        merged := []
        for item in Snippets {
            if !IsInboxCategory(item.Category)
                merged.Push(item)
        }
        Snippets := merged
        TrayTip "Could not verify the latest Inbox item. Clipboard unchanged.", "Trigger Search"
        return false
    }
    return true
}

DownloadWorkbook(sheetId, &infos, &csvByName, &stage) {
    stage := "downloading the list of Sheet tabs"
    cacheBust := A_NowUTC A_MSec
    htmlUrl := "https://docs.google.com/spreadsheets/d/" sheetId
        . "/htmlview?cacheBust=" cacheBust
    html := FetchText(htmlUrl)
    stage := "reading the list of Sheet tabs"
    infos := DiscoverSheets(html)
    if infos.Length = 0
        throw Error("No visible tabs were found. The workbook may not be published to the web.")

    csvByName := Map()
    for info in infos {
        stage := "downloading the " info.Name " tab"
        csvByName[info.Name] := FetchSheetCsv(info, cacheBust, sheetId)
    }
}

FetchSheetCsv(info, cacheBust, sheetId) {

    baseUrl := "https://docs.google.com/spreadsheets/d/" sheetId
    urls := [
        baseUrl "/export?format=csv&gid=" info.Gid "&cacheBust=" cacheBust,
        baseUrl "/gviz/tq?tqx=out:csv&gid=" info.Gid "&cacheBust=" cacheBust
    ]
    failures := []

    for url in urls {
        try {
            csv := FetchText(url)
            if LooksLikeCsv(csv)
                return csv
            failures.Push("invalid CSV")
        } catch as problem {
            failures.Push(problem.Message)
        }
    }
    throw Error("No valid public CSV response for " info.Name
        . ". Export: " failures[1] "; GViz: " failures[2])
}

LooksLikeCsv(csv) {
    if SubStr(LTrim(csv), 1, 1) = "<"
        return false
    rows := ParseCsv(csv)
    return rows.Length > 0 && rows[1].Length >= 1 && Trim(csv) != ""
}

RefreshOpenChooser() {
    global ChooserOpen, DetailParent, SearchServiceParent, Snippets, SearchBox
    global RootQuery, VisibleChoices, ResultsView

    if !ChooserOpen
        return

    selected := SelectedChoice()
    selectedKey := selected && selected.HasOwnProp("Key") ? selected.Key : ""

    if SearchServiceParent {
        parentKey := SearchServiceParent.Key
        refreshedParent := 0
        for item in Snippets {
            if item.Key = parentKey {
                refreshedParent := item
                break
            }
        }
        if refreshedParent {
            SearchServiceParent := refreshedParent
            UpdateChooserContext()
            SetSearchPlaceholder("←  " refreshedParent.GroupLabel)
            RenderChoices(FilterChoices(SearchBox.Value))
        } else {
            SearchServiceParent := 0
            UpdateChooserContext()
            SearchBox.Value := RootQuery
            RenderChoices(FilterChoices(RootQuery))
        }
    } else if DetailParent {
        parentKey := DetailParent.Key
        refreshedParent := 0
        for item in Snippets {
            if item.Key = parentKey {
                refreshedParent := item
                break
            }
        }

        if refreshedParent {
            DetailParent := refreshedParent
            UpdateChooserContext()
            RenderChoices(FilterChoices(SearchBox.Value))
        } else {
            DetailParent := 0
            UpdateChooserContext()
            SearchBox.Value := RootQuery
            RenderChoices(FilterChoices(RootQuery))
        }
    } else {
        UpdateChooserContext()
        RenderChoices(FilterChoices(SearchBox.Value))
    }

    if selectedKey != "" {
        for index, choice in VisibleChoices {
            if choice.HasOwnProp("Key") && choice.Key = selectedKey {
                ResultsView.Modify(0, "-Select -Focus")
                ResultsView.Modify(index, "Select Focus Vis")
                break
            }
        }
    }
    SearchBox.Focus()
}

BuildErrorReport(problem, context, mode := "Caught") {
    global AppVersion

    report := "Trigger Search v" AppVersion
        . "`nContext: " context
        . "`nError type: " Type(problem)
        . "`nMessage: " problem.Message
        . "`nFunction: " (problem.What != "" ? problem.What : "Not provided")
        . "`nFile: " (problem.File != "" ? problem.File : A_ScriptFullPath)
        . "`nLine: " (problem.Line != "" ? problem.Line : "Not provided")
        . "`nMode: " mode

    if problem.Extra != ""
        report .= "`nExtra: " problem.Extra
    if problem.Stack != ""
        report .= "`n`nStack trace:`n" problem.Stack
    return report
}

RecordError(problem, context, mode := "Caught") {
    global ErrorPath

    report := BuildErrorReport(problem, context, mode)
    try WriteTextAtomic ErrorPath, report
    OutputDebug report "`n"
    return report
}

ShowLastErrorReport(*) {
    global ErrorPath

    if !FileExist(ErrorPath) {
        MsgBox "No error has been recorded yet.", "Trigger Search diagnostics"
        return
    }
    MsgBox FileRead(ErrorPath, "UTF-8"), "Trigger Search diagnostics"
}

HandleUnexpectedError(problem, mode) {
    report := RecordError(problem, "Unexpected unhandled error", mode)
    MsgBox report, "Trigger Search unexpected error"
    return 0
}

RunSelfTestsAndExit() {
    resultPath := A_Temp "\sheet-autocomplete-self-test.txt"
    if FileExist(resultPath)
        FileDelete resultPath

    try {
        RunSelfTests()
        FileAppend "PASS", resultPath, "UTF-8-RAW"
        ExitApp 0
    } catch as problem {
        FileAppend BuildErrorReport(problem, "Automated self-test"), resultPath,
            "UTF-8-RAW"
        ExitApp 1
    }
}

RunSelfTests() {
    global Snippets, DetailParent, SearchServiceParent, RecentItems, InboxSheet
    global ChooserOpen, PreviewOpen, CategoryParent

    TestInboxWriter()
    TestKeyboardRemaps()
    TestZoomWindowControls()
    TestZoomAccessibility()
    automationRows := ParseCsv('Name,Alias,Description,Script ID`n'
        . 'Office visit,of,Office follow up,advancedmd.follow-up-office`n'
        . 'Renamed duplicate,other,Duplicate,advancedmd.follow-up-office`n'
        . 'Unsafe,x,Do not execute,cmd.exe /c calc`n'
        . 'Traversal,y,Do not execute,../../evil.ahk`n'
        . 'Telehealth,tf,Video follow up,advancedmd.follow-up-tele')
    automations := []
    ParseAutomations automationRows, {Name: "Automations", Gid: "987"}, automations
    shortcutRows := []
    ParseAutomations ParseCsv("Name,Alias,Description,Script ID,Dell Shortcut`n"
        . "AMD follow-up,of,Office visit,AMD.follow-up-office,Alt + O`n"
        . "Duplicate,dup,Same action,advancedmd.follow-up-office,Alt + O`n"
        . "Unknown,bad,No execution,AMD.arbitrary,cmd.exe /c calc"),
        {Name: "Automations", Gid: "987"}, shortcutRows
    Assert shortcutRows.Length = 1 && shortcutRows[1].ScriptId = "advancedmd.follow-up-office",
        "Reference columns and explicit AMD aliases must preserve safe automation dispatch."
    Assert shortcutRows[1].Content = "" && !shortcutRows[1].HasSavedContent,
        "Shortcut reference text must never become executable or pasteable content."
    Assert CanonicalAutomationId("dell.launch-AMD") = "dell.launch-advancedmd",
        "The existing AMD login alias must resolve to its trusted local action."
    helperRows := []
    ParseAutomations ParseCsv("Name,Alias,Description,Script ID`nFull MSE,mse,Exam,dell.mse"),
        {Name: "Automations", Gid: "987"}, helperRows
    Assert helperRows.Length = 1 && InStr(AutomationPath("dell.mse"), "dell/helpers.ahk"),
        "All registered Dell helpers must be accepted as automation rows."
    Assert automations.Length = 2, "Unknown IDs and duplicate automation rows must be rejected."
    Assert automations[1].Label = "Office visit" && automations[1].Content = ""
        && !automations[1].HasSavedContent, "Automation metadata must never become snippet text."
    Assert InStr(automations[1].EditUrl, "range=A2"), "Automation edits must link to the exact Sheet row."
    rejected := false
    try AutomationPath("../../evil.ahk")
    catch
        rejected := true
    Assert rejected, "Dispatch must reject IDs outside the local allowlist."
    wrongHeaders := []
    ParseAutomations ParseCsv("Name,Alias,Description,Command`nA,a,B,calc.exe"),
        {Name: "Automations", Gid: "987"}, wrongHeaders
    Assert wrongHeaders.Length = 0, "A command column must not be treated as Script ID."
    Snippets := automations
    DetailParent := 0
    SearchServiceParent := 0
    CategoryParent := ""
    Assert FilterChoices("of")[1].ScriptId = "advancedmd.follow-up-office",
        "Automation aliases must use the normal search ranking."
    Assert FilterChoices("Video")[1].ScriptId = "advancedmd.follow-up-tele",
        "Descriptions must be searchable."
    rankingRows := []
    ParseAutomations ParseCsv("Name,Alias,Description,Script ID`n"
        . "AMD telehealth follow-up,t,Video,AMD.follow-up-tele`n"
        . "Open AMD,l,Login,dell.launch-advancedmd"),
        {Name: "Automations", Gid: "987"}, rankingRows
    Snippets := [TestSnippet("Taper", "taper", ["tap"]),
        TestSnippet("Long alias", "long", ["taper"]),
        TestSnippet("Short alias", "short", ["ta"]), rankingRows[1], rankingRows[2]]
    rankedAliases := FilterChoices("T")
    Assert rankedAliases[1].ScriptId = "advancedmd.follow-up-tele",
        "An exact T alias must beat TAP and names across snippets and AMD automations."
    Assert rankedAliases[2].Label = "Short alias" && rankedAliases[3].Label = "Taper",
        "Matching two-letter aliases must precede matching three-letter aliases."
    Assert FilterChoices("L")[1].ScriptId = "dell.launch-advancedmd",
        "An exact L alias must find Open AMD regardless of its display name."
    Snippets := automations
    Assert !IsControlCombination(true, 0xA3, 0x11D),
        "The Right Ctrl key itself must not be treated as another key in a combination."
    Assert IsControlCombination(true, 0x43, 0x2E),
        "A second key while Ctrl is held must suppress tap launch."
    Assert IsRightControlTap(100, false, "RControl"), "A short Right Ctrl tap should launch."
    Assert !IsRightControlTap(900, false, "RControl"), "A held Right Ctrl should not launch."
    Assert !IsRightControlTap(100, true, "RControl"), "A Ctrl combination should not launch."
    Assert !IsRightControlTap(100, false, "c"), "Ctrl+C must retain its normal behavior."

    DetailParent := 0
    SearchServiceParent := 0
    ChooserOpen := true
    PreviewOpen := false
    Assert RefreshShouldDefer(false),
        "Automatic refresh should defer while the chooser is open."
    Assert !RefreshShouldDefer(true),
        "An explicit refresh should bypass chooser deferral."
    ChooserOpen := false
    Snippets := [
        TestSnippet("meeting", "meet", ["mtg"]),
        TestSnippet("email address", "email@example.com", ["email"])
    ]

    RecentItems := [{
        Category: "Personal",
        GroupLabel: "email address",
        DetailName: ""
    }]
    unfiltered := FilterChoices("")
    Assert unfiltered.Length = 1 && unfiltered[1].Label = "email address",
        "The empty main chooser should show recently used Sheet items."
    RecentItems := []

    InboxSheet := "Inbox"
    newestInbox := TestSnippet("newest inbox", "latest", [])
    newestInbox.Category := "Inbox"
    olderInbox := TestSnippet("older inbox", "older", [])
    olderInbox.Category := "Inbox"
    otherRecent := TestSnippet("other recent", "elsewhere", [])
    Snippets := [newestInbox, olderInbox, otherRecent]
    RecentItems := [{Category: "Personal", GroupLabel: "other recent", DetailName: ""},
        {Category: "Inbox", GroupLabel: "newest inbox", DetailName: ""}]
    home := FilterChoices("")
    Assert home.Length = 2 && home[1].Label = "newest inbox"
        && home[1].IsPinnedInbox && home[2].Label = "other recent",
        "The latest Inbox item should be pinned before Recents without duplication."
    RecentItems := []
    Snippets := [
        TestSnippet("meeting", "meet", ["mtg"]),
        TestSnippet("email address", "email@example.com", ["email"])
    ]

    aliasMatch := FilterChoices("email")
    Assert aliasMatch.Length > 0, "Alias search should return a result."
    Assert aliasMatch[1].Label = "email address",
        "Exact alias match should rank first."

    parsed := []
    ParseSheet '"Name","Alias","Content"`n"apple","","red apple"',
        {Name: "Test", Gid: "123"}, parsed
    Assert parsed.Length = 1, "A standard Name and Content row should parse."
    Assert parsed[1].Label = "apple", "The parsed Name should remain apple."
    Assert parsed[1].Content = "red apple",
        "The parsed Content should remain red apple."
    Assert InStr(parsed[1].EditUrl, "&range=C2"),
        "Editing a standard snippet should target its pasted Content cell."

    contentOnly := []
    ParseSheet '"Name","Alias","Content"`n"","","red apple"',
        {Name: "Test", Gid: "123"}, contentOnly
    Assert contentOnly.Length = 1 && contentOnly[1].Content = "red apple",
        "Content-only rows should remain usable without a Name."

    aiParsed := []
    ParseSheet '"Name","Alias","Content","Sig"`n'
        . '"AI Prompt","","","Write a sig for {medication}."`n'
        . '"Atomoxetine","ato","",""',
        {Name: "Psych Meds", Gid: "123"}, aiParsed
    Assert aiParsed.Length = 1,
        "The AI Prompt metadata row should not appear as a snippet."
    Assert aiParsed[1].Details.Length = 1,
        "An AI-enabled empty detail should remain available."
    DetailParent := aiParsed[1]
    nestedUnfiltered := FilterChoices("")
    Assert nestedUnfiltered.Length = 1,
        "A nested view should show its choices before the user searches."
    DetailParent := 0
    Assert !aiParsed[1].Details[1].HasSavedContent,
        "An AI-only detail should not pretend to contain saved text."
    Assert BuildAiPrompt(aiParsed[1].Details[1])
        = "Write a sig for Atomoxetine.",
        "AI placeholders should receive the selected item label."
    Snippets := aiParsed
    RecentItems := [{
        Category: "Psych Meds",
        GroupLabel: "Atomoxetine",
        DetailName: "Sig"
    }]
    recentDetail := FilterChoices("")
    Assert recentDetail.Length = 1
        && recentDetail[1].DisplayText = "Atomoxetine — Sig",
        "A recent nested detail should include its parent label."
    RecentItems := []
    Assert UrlEncode("A B") = "A%20B",
        "AI launch URLs should safely encode spaces."

    searchServices := []
    ParseSheet '"Content","Name","Alias"`n'
        . '"https://pubmed.ncbi.nlm.nih.gov/?term=$","PubMed","pm; literature"`n'
        . '"Broken","https://example.com/no-placeholder","bad"`n'
        . '"javascript:alert($)","Unsafe","unsafe"',
        {Name: "Search", Gid: "456"}, searchServices
    Assert searchServices.Length = 1,
        "Search services should require Name/Alias/Content headers and a $ placeholder."
    Assert searchServices[1].IsSearchService
        && searchServices[1].GroupLabel = "PubMed",
        "A valid search-service row should become a searchable parent."
    Assert searchServices[1].Aliases.Length = 2
        && searchServices[1].Aliases[1] = "pm",
        "Search services should support optional aliases."

    headerlessSearch := []
    ParseSheet 'Google,g,"https://www.google.com/search?q=$"`n'
        . 'Broken,"https://example.com/no-placeholder",bad',
        {Name: "Search", Gid: "457"}, headerlessSearch
    Assert headerlessSearch.Length = 0,
        "The Search tab should require its visible headers."

    flexibleSearchHeaders := []
    ParseSheet '"Nickname","Link","Name"`n'
        . '"docs","https://example.com/search?q=$","Docs"',
        {Name: "Search", Gid: "458"}, flexibleSearchHeaders
    Assert flexibleSearchHeaders.Length = 0,
        "Search launcher header synonyms should not create hidden schema rules."

    renamedSearchTab := []
    ParseSheet '"Name","Alias","Content"`n'
        . '"Knowledge Base","kb","https://example.com/find?q=$"',
        {Name: "Reference Tools", Gid: "459"}, renamedSearchTab
    Assert renamedSearchTab.Length = 1
        && !renamedSearchTab[1].HasOwnProp("IsSearchService"),
        "Only the Search tab should create search launchers."

    protocolFreeSearch := []
    ParseSheet '"Name","Alias","Content"`n'
        . '"Wikipedia","wiki","en.wikipedia.org/w/index.php?search=$"',
        {Name: "Search", Gid: "460"}, protocolFreeSearch
    Assert protocolFreeSearch.Length = 1
        && protocolFreeSearch[1].SearchTemplate
            = "https://en.wikipedia.org/w/index.php?search=$",
        "A protocol-free search template should default safely to HTTPS."
    Snippets := searchServices
    aliasChoice := FilterChoices("pm")
    Assert aliasChoice.Length = 1 && aliasChoice[1].GroupLabel = "PubMed",
        "A search-service alias should find its parent item."
    SearchServiceParent := searchServices[1]
    queryChoice := FilterChoices("adult ADHD")
    Assert queryChoice.Length = 1 && queryChoice[1].Type = "search-query",
        "Search-service query mode should expose one launchable query choice."
    Assert StrReplace(searchServices[1].SearchTemplate, "$",
        UrlEncode(queryChoice[1].SearchQuery))
        = "https://pubmed.ncbi.nlm.nih.gov/?term=adult%20ADHD",
        "Search-service queries should be URL encoded before template replacement."
    SearchServiceParent := 0

    headerlessOne := []
    ParseSheet "apple`nbanana", {Name: "Quick", Gid: "123"}, headerlessOne
    Assert headerlessOne.Length = 2 && headerlessOne[1].Content = "apple",
        "A one-column headerless tab should display and paste each value."

    headerlessTwo := []
    ParseSheet "apple,red apple`nbanana,yellow banana",
        {Name: "Quick", Gid: "123"}, headerlessTwo
    Assert headerlessTwo.Length = 2 && headerlessTwo[1].Label = "apple"
        && headerlessTwo[1].Content = "red apple",
        "A two-column headerless tab should use left as Name and right as Content."

    headerlessThree := []
    ParseSheet "apple,a,red apple`nbanana,b,yellow banana",
        {Name: "Quick", Gid: "123"}, headerlessThree
    Assert headerlessThree.Length = 2 && headerlessThree[1].Label = "apple"
        && headerlessThree[1].Aliases[1] = "a"
        && headerlessThree[1].Content = "red apple",
        "A three-column headerless tab should use Name, Alias, and Content."

    headerlessFour := []
    ParseSheet "apple,a,red apple,extra",
        {Name: "Quick", Gid: "123"}, headerlessFour
    Assert headerlessFour.Length = 0,
        "A headerless tab with four columns should require headers."

    labelDetail := []
    ParseSheet '"Name","Alias","Content","Label"`n'
        . '"Example","ex","Main text","Nested label text"',
        {Name: "Quick", Gid: "123"}, labelDetail
    Assert labelDetail.Length = 1 && labelDetail[1].Details.Length = 1
        && labelDetail[1].Details[1].DisplayText = "Label",
        "Label should be available as an ordinary nested field."

    Assert ExtractLaunchUrl("Open https://example.com/help when needed")
        = "https://example.com/help",
        "An embedded protocol URL should be launchable."
    Assert ExtractLaunchUrl("Open example.com/help when needed")
        = "https://example.com/help",
        "A recognizable bare web address should receive https."
    Assert ExtractLaunchUrl("me@example.com") = "",
        "An email address should not be treated as a web link."
    Assert ExtractLaunchUrl("https://one.example and https://two.example") = "",
        "Content containing multiple links should paste normally instead of guessing."
    Assert ExtractLaunchUrl("https://one.example and two.example") = "",
        "Mixed explicit and bare links should paste normally instead of guessing."
    Assert ExtractStandaloneLaunchUrl("example.com/help")
        = "https://example.com/help",
        "A link by itself should open with Right Arrow."
    Assert ExtractStandaloneLaunchUrl("Read example.com/help first") = "",
        "Text containing a link should not open with Right Arrow."

    dynamic := ExpandDynamicContent(
        "Annual: {date format="
            . Chr(34) "MM/dd/yyyy" Chr(34) " offset="
            . Chr(34) "+1y" Chr(34) "}`n"
            . "Follow-up: {date format="
            . Chr(34) "MM/dd/yyyy" Chr(34) " offset="
            . Chr(34) "+3M" Chr(34) "}`n"
            . "Copied: {clipboard}`nBefore {cursor}after",
        "clipboard value", "20260730120000")
    Assert dynamic.Text = "Annual: 07/30/2027`n"
        . "Follow-up: 10/30/2026`n"
        . "Copied: clipboard value`nBefore after",
        "Date, offset, and clipboard placeholders should expand at paste time."
    Assert dynamic.CursorLeft = 5,
        "The cursor placeholder should leave the cursor before trailing text."

    monthEnd := ExpandDynamicContent(
        "{date format=" Chr(34) "MM/dd/yyyy" Chr(34)
            . " offset=" Chr(34) "+1M" Chr(34) "}",
        "", "20260131120000")
    Assert monthEnd.Text = "02/28/2026",
        "Calendar-month offsets should clamp safely at month end."

    preserved := ExpandDynamicContent("{unsupported}", "", "20260730120000")
    Assert preserved.Text = "{unsupported}",
        "Unknown placeholders should remain ordinary text."

    fourWeeks := BuildUtilityChoice("4W", "20260730120000")
    Assert fourWeeks.Content = "08/27/2026",
        "A bare week duration should calculate a future date."
    Assert InStr(fourWeeks.Preview, "4 weeks from today"),
        "A date result should state how its duration was interpreted."

    sixMonths := BuildUtilityChoice("6m", "20260730120000")
    Assert sixMonths.Content = "01/30/2027",
        "A bare month duration should use calendar months."

    arithmetic := BuildUtilityChoice("(90 - 10) / 2")
    Assert arithmetic.Content = "40",
        "A complete arithmetic expression should calculate without an equals sign."
    arithmeticWithEquals := BuildUtilityChoice("= 90 / 3")
    Assert arithmeticWithEquals.Content = "30",
        "An optional equals sign should also be accepted."
    Assert !BuildUtilityChoice("30"),
        "A plain number should remain an ordinary snippet search."
    divideByZero := BuildUtilityChoice("90 / 0")
    Assert divideByZero.IsUtilityError
        && divideByZero.DisplayText = "Cannot divide by zero",
        "Division by zero should produce a clear non-pasteable result."

    directMatch := TestSnippet("doctor note", "Dr. White", [])
    nestedOnlyMatch := TestSnippet("medication", "regular content", [])
    nestedOnlyMatch.DetailSearch := " side effect white"
    Snippets := [nestedOnlyMatch, directMatch]
    contentMatch := FilterChoices("white")
    Assert contentMatch.Length = 2,
        "Direct and nested content matches should both remain searchable."
    Assert contentMatch[1].Label = "doctor note",
        "Direct Content should rank ahead of nested detail text."

    Assert LooksLikeCsv("Name,Content`napple,red apple"),
        "Unquoted public export CSV should be accepted."
    Assert LooksLikeCsv("apple`nbanana"),
        "A one-column public export should be accepted for headerless tabs."
    Assert !LooksLikeCsv("<html><body>Not CSV</body></html>"),
        "An HTML response should not be accepted as CSV."

    sampleId := "15JTaedzH2ZfT2FAb7FduyMg37aBCHTKborM7E0y8nts"
    Assert ExtractSheetId("https://docs.google.com/spreadsheets/d/" sampleId
        . "/edit?usp=sharing") = sampleId,
        "A complete Google Sheets link should yield its spreadsheet ID."
    Assert ExtractSheetId(sampleId) = sampleId,
        "A raw spreadsheet ID should remain valid."
    Assert ExtractSheetId("https://example.com/not-a-sheet") = "",
        "A non-Google link should be rejected."
    TestLauncherToggle()
}

TestSnippet(label, content, aliases) {
    return {
        Type: "snippet",
        Key: label,
        Label: label,
        GroupLabel: label,
        DisplayText: label,
        Content: content,
        Category: "Personal",
        Aliases: aliases,
        Details: [],
        DetailSearch: "",
        DetailOrder: 0,
        Preview: "",
        EditUrl: ""
    }
}

Assert(condition, message) {
    if !condition
        throw Error(message)
}

FetchText(url) {
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(5000, 5000, 10000, 15000)
    request.Open("GET", url, false)
    request.SetRequestHeader("User-Agent", "SheetAutocomplete")
    request.SetRequestHeader("Cache-Control", "no-cache")
    request.Send()
    if request.Status != 200
        throw Error("Google Sheets returned HTTP " request.Status ".")
    return request.ResponseText
}

DiscoverSheets(html) {
    infos := []
    seen := Map()
    position := 1
    pattern := 's)items\.push\(\{name:\s*"([^"]*)".*?gid:\s*"(-?\d+)"'

    while found := RegExMatch(html, pattern, &match, position) {
        name := DecodeJavascriptString(match[1])
        gid := match[2]
        if name != "" && !seen.Has(name) {
            infos.Push({Name: name, Gid: gid})
            seen[name] := true
        }
        position := found + match.Len(0)
    }
    return infos
}

DecodeJavascriptString(value) {
    position := 1
    while found := RegExMatch(value, "\\x([0-9A-Fa-f]{2})", &match, position) {
        replacement := Chr(Integer("0x" match[1]))
        value := SubStr(value, 1, found - 1) replacement
            . SubStr(value, found + match.Len(0))
        position := found + StrLen(replacement)
    }
    value := StrReplace(value, '\"', Chr(34))
    value := StrReplace(value, "\\", "\")
    return value
}

ApplySheets(infos, csvByName) {
    global Snippets

    ApplySettings infos, csvByName
    parsed := []

    for info in infos {
        if IsAdministrativeSheet(info.Name)
            continue
        if !csvByName.Has(info.Name)
            continue
        ParseSheet csvByName[info.Name], info, parsed
    }

    Snippets := parsed
}

ApplySettings(infos, csvByName) {
    global LauncherModifier, LauncherKey, AiEngine, InboxSheet
    InboxSheet := "Inbox"
    for info in infos {
        normalized := NormalizeSheetName(info.Name)
        if normalized != "settings" && normalized != "settingshelp"
            continue
        if !csvByName.Has(info.Name)
            continue

        rows := ParseCsv(csvByName[info.Name])
        if rows.Length = 0
            continue
        columns := HeaderMap(rows[1])
        if !columns.Has("setting") || !columns.Has("value")
            continue

        Loop rows.Length - 1 {
            row := rows[A_Index + 1]
            key := StrLower(Trim(Cell(row, columns["setting"])))
            key := RegExReplace(key, "[\s_-]+")
            value := Trim(Cell(row, columns["value"]))
            if key = "trigger" && value != ""
                InstallTrigger value
            else if key = "launchermodifier"
                LauncherModifier := value != "" ? value : "None"
            else if key = "launcherkey"
                LauncherKey := value != "" ? value : "None"
            else if key = "aiengine" && value != ""
                AiEngine := value
            else if key = "inboxsheet"
                InboxSheet := value != "" ? value : "Inbox"
        }
        InstallLauncherHotkey LauncherModifier, LauncherKey
    }
}

ParseSheet(csv, info, output) {
    rows := ParseCsv(csv)
    if rows.Length = 0
        return
    if StrLower(Trim(info.Name)) = "automations" {
        ParseAutomations rows, info, output
        return
    }
    columns := HeaderMap(rows[1])
    serviceColumn := columns.Has("name") ? columns["name"] : 0
    aliasColumn := columns.Has("alias") ? columns["alias"] : 0
    isSearchTab := StrLower(Trim(info.Name)) = "search"
    templateColumn := columns.Has("content") ? columns["content"] : 0
    if isSearchTab && serviceColumn && aliasColumn && templateColumn {
        firstLauncherRow := 2
        Loop rows.Length - firstLauncherRow + 1 {
            rowNumber := firstLauncherRow + A_Index - 1
            row := rows[rowNumber]
            service := Trim(Cell(row, serviceColumn))
            template := NormalizeSearchTemplate(Cell(row, templateColumn))
            if service = "" || template = ""
                continue
            aliases := []
            aliasText := aliasColumn ? Cell(row, aliasColumn) : ""
            Loop Parse, aliasText, ",;|`n`r" {
                alias := StrLower(Trim(A_LoopField))
                if alias != ""
                    aliases.Push(alias)
            }
            output.Push({
                Type: "search-service",
                Key: info.Gid ":" rowNumber,
                Label: service,
                GroupLabel: service,
                DisplayText: service "   →",
                Content: "",
                HasSavedContent: false,
                AiPrompt: "",
                Category: info.Name,
                Aliases: aliases,
                Details: [],
                DetailSearch: "",
                DetailOrder: 0,
                Preview: "Enter a query",
                EditUrl: EditUrl(info.Gid, rowNumber, templateColumn, templateColumn),
                IsSearchService: true,
                SearchTemplate: template
            })
        }
        return
    }
    if isSearchTab
        return
    hasHeaders := columns.Has("name") || columns.Has("alias")
        || columns.Has("content")
    if !hasHeaders {
        rightmostContentColumn := 0
        for row in rows {
            for columnIndex, value in row {
                if Trim(value) != ""
                    rightmostContentColumn := Max(rightmostContentColumn, columnIndex)
            }
        }
        if rightmostContentColumn > 3 {
            OutputDebug "Trigger Search: skipped headerless tab " info.Name
                . " because it uses more than three columns.`n"
            return
        }
        if rightmostContentColumn = 1
            columns["content"] := 1
        else if rightmostContentColumn = 2 {
            columns["name"] := 1
            columns["content"] := 2
        } else if rightmostContentColumn = 3 {
            columns["name"] := 1
            columns["alias"] := 2
            columns["content"] := 3
        }
    } else if !columns.Has("content") {
        OutputDebug "Trigger Search: skipped headered tab " info.Name
            . " because it has no Content column.`n"
        return
    }

    nameColumn := columns.Has("name") ? columns["name"] : 0
    contentColumn := columns.Has("content") ? columns["content"] : 0
    aliasColumn := columns.Has("alias") ? columns["alias"] : 0

    firstDataRow := hasHeaders ? 2 : 1
    displayHeaders := rows[1]
    aiPrompts := Map()
    if hasHeaders {
        Loop rows.Length - firstDataRow + 1 {
            metadataRow := rows[firstDataRow + A_Index - 1]
            metadataName := nameColumn ? Trim(Cell(metadataRow, nameColumn)) : ""
            if RegExReplace(StrLower(metadataName), "[\s_-]+") = "aiprompt" {
                for columnIndex, value in metadataRow {
                    if Trim(value) != ""
                        aiPrompts[columnIndex] := value
                }
            }
        }
    }
    Loop rows.Length - firstDataRow + 1 {
        rowNumber := firstDataRow + A_Index - 1
        row := rows[rowNumber]
        sheetName := nameColumn ? Trim(Cell(row, nameColumn)) : ""
        sheetContent := contentColumn ? Cell(row, contentColumn) : ""
        if RegExReplace(StrLower(sheetName), "[\s_-]+") = "aiprompt"
            continue
        contentPreviewName := PreviewText(sheetContent)
        label := sheetName != "" ? sheetName : contentPreviewName
        if label = ""
            continue
        hasSavedContent := Trim(sheetContent) != ""
        content := hasSavedContent ? sheetContent : ""
        editColumn := hasSavedContent ? contentColumn : nameColumn

        aliases := []
        aliasText := aliasColumn ? Cell(row, aliasColumn) : ""
        Loop Parse, aliasText, ",;|`n`r" {
            alias := StrLower(Trim(A_LoopField))
            if alias != ""
                aliases.Push(alias)
        }

        root := {
            Type: "snippet",
            Key: info.Gid ":" rowNumber,
            Label: label,
            GroupLabel: label,
            DisplayText: label,
            Content: content,
            HasSavedContent: hasSavedContent,
            AiPrompt: contentColumn && aiPrompts.Has(contentColumn)
                ? aiPrompts[contentColumn] : "",
            Category: info.Name,
            Aliases: aliases,
            Details: [],
            DetailSearch: "",
            DetailOrder: 0,
            Preview: MakePreview(sheetName, sheetContent, info.Name),
            EditUrl: EditUrl(info.Gid, rowNumber, Max(1, editColumn),
                Max(1, editColumn))
        }
        if hasHeaders {
          for columnIndex, header in displayHeaders {
            detailName := Trim(StrReplace(header, Chr(0xFEFF)))
            normalizedDetailName := StrLower(detailName)
            if detailName = "" || normalizedDetailName = "name"
                || normalizedDetailName = "content"
                || normalizedDetailName = "alias"
                continue
            detailContent := Cell(row, columnIndex)
            detailAiPrompt := aiPrompts.Has(columnIndex) ? aiPrompts[columnIndex] : ""
            if Trim(detailContent) = "" && Trim(detailAiPrompt) = ""
                continue

            detail := {
                Type: "detail",
                Key: root.Key ":" columnIndex,
                Label: label " " detailName,
                GroupLabel: label,
                DisplayText: detailName,
                DetailName: detailName,
                Content: detailContent,
                HasSavedContent: Trim(detailContent) != "",
                AiPrompt: detailAiPrompt,
                Category: info.Name,
                Aliases: [],
                Details: [],
                DetailSearch: "",
                DetailOrder: columnIndex,
                Preview: Trim(detailContent) != "" ? PreviewText(detailContent) : "",
                EditUrl: EditUrl(info.Gid, rowNumber, columnIndex, columnIndex)
            }
            root.Details.Push(detail)
            root.DetailSearch .= " " detailName " " detailContent
          }
        }

        if root.Details.Length > 0 {
            root.DisplayText := label "   →"
        }
        if root.HasSavedContent || root.Details.Length > 0 || Trim(root.AiPrompt) != ""
            output.Push(root)
    }
}

CompareSnippets(a, b) {
    aLabel := StrLower(a.GroupLabel)
    bLabel := StrLower(b.GroupLabel)
    if aLabel != bLabel
        return StrCompare(aLabel, bLabel)
    aCategory := StrLower(a.Category)
    bCategory := StrLower(b.Category)
    return StrCompare(aCategory, bCategory)
}

MakePreview(label, content, category) {
    preview := PreviewText(content)
    if Trim(content) = "" || StrLower(Trim(content)) = StrLower(Trim(label))
        return ""
    return preview
}

PreviewText(value) {
    value := RegExReplace(value, "\s+", " ")
    value := Trim(value)
    return StrLen(value) > 95 ? SubStr(value, 1, 92) "..." : value
}

EditUrl(gid, rowNumber, startColumn, endColumn) {
    global SheetId
    range := ColumnLetter(startColumn) rowNumber
    if endColumn != startColumn
        range .= ":" ColumnLetter(endColumn) rowNumber
    return "https://docs.google.com/spreadsheets/d/" SheetId
        . "/edit#gid=" gid "&range=" range
}

ColumnLetter(index) {
    result := ""
    while index > 0 {
        remainder := Mod(index - 1, 26)
        result := Chr(65 + remainder) result
        index := Floor((index - 1) / 26)
    }
    return result
}

HeaderMap(headerRow) {
    columns := Map()
    for index, header in headerRow {
        normalized := StrLower(Trim(StrReplace(header, Chr(0xFEFF))))
        if normalized != ""
            columns[normalized] := index
    }
    return columns
}

NormalizeSearchTemplate(value) {
    template := Trim(value)
    if !InStr(template, "$")
        return ""
    if RegExMatch(template, "i)^https?://\S+$")
        return template
    if RegExMatch(template, "i)^(?:[a-z0-9-]+\.)+[a-z]{2,}\S*$")
        return "https://" template
    return ""
}

Cell(row, index) {
    return index >= 1 && index <= row.Length ? row[index] : ""
}

ParseCsv(csv) {
    csv := StrReplace(csv, "`r`n", "`n")
    rows := []
    row := []
    field := ""
    quoted := false
    index := 1
    length := StrLen(csv)

    while index <= length {
        character := SubStr(csv, index, 1)
        if quoted {
            if character = Chr(34) && SubStr(csv, index + 1, 1) = Chr(34) {
                field .= Chr(34)
                index += 1
            } else if character = Chr(34) {
                quoted := false
            } else {
                field .= character
            }
        } else if character = Chr(34) && field = "" {
            quoted := true
        } else if character = "," {
            row.Push(field)
            field := ""
        } else if character = "`n" {
            row.Push(field)
            rows.Push(row)
            row := []
            field := ""
        } else if character != "`r" {
            field .= character
        }
        index += 1
    }

    if field != "" || row.Length > 0 {
        row.Push(field)
        rows.Push(row)
    }
    return rows
}

IsAdministrativeSheet(name) {
    normalized := NormalizeSheetName(name)
    return normalized = "settings" || normalized = "settingshelp"
        || normalized = "readme" || normalized = "template"
        || normalized = "blanktemplate" || normalized = "autohotkey"
        || normalized = "windowssetup"
}

NormalizeSheetName(name) {
    return RegExReplace(StrLower(Trim(name)), "[\s_&-]+")
}

SaveCache(infos, csvByName) {
    global CacheDir, ManifestPath, Trigger, SheetId

    manifest := "[cache]`ncount=" infos.Length "`ntrigger=" Trigger
        . "`nsheetId=" SheetId "`n"
    for index, info in infos {
        cacheFile := CacheDir "\sheet-" info.Gid ".csv"
        WriteTextAtomic cacheFile, csvByName[info.Name]
        manifest .= "`n[sheet" index "]`nname=" info.Name
            . "`ngid=" info.Gid "`nfile=" cacheFile "`n"
    }
    WriteTextAtomic ManifestPath, manifest
}

WriteTextAtomic(path, contents) {
    temporary := path ".tmp"
    if FileExist(temporary)
        FileDelete temporary
    FileAppend contents, temporary, "UTF-8-RAW"
    FileMove temporary, path, 1
}

LoadCache() {
    global ManifestPath, Trigger, SheetInfos, SheetId

    if SheetId = "" || !FileExist(ManifestPath)
        return

    cachedSheetId := Trim(IniRead(ManifestPath, "cache", "sheetId", ""))
    if cachedSheetId != "" && cachedSheetId != SheetId
        return
    count := IniRead(ManifestPath, "cache", "count", 0) + 0
    cachedTrigger := IniRead(ManifestPath, "cache", "trigger", Trigger)
    infos := []
    csvByName := Map()

    Loop count {
        section := "sheet" A_Index
        name := IniRead(ManifestPath, section, "name", "")
        gid := IniRead(ManifestPath, section, "gid", "")
        file := IniRead(ManifestPath, section, "file", "")
        if name = "" || gid = "" || !FileExist(file)
            return
        infos.Push({Name: name, Gid: gid})
        csvByName[name] := FileRead(file, "UTF-8")
    }

    if infos.Length > 0 {
        Trigger := cachedTrigger
        ApplySheets infos, csvByName
        SheetInfos := infos
    }
}



BeginRightControlTap(*) {
    global RightControlUsed, RightControlDown, RightControlEventCount
    RightControlEventCount += 1
    if RightControlDown
        return
    RightControlUsed := GetKeyState("LControl", "P") || GetKeyState("Shift", "P")
        || GetKeyState("Alt", "P") || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    RightControlDown := A_TickCount
}

EndRightControlTap(*) {
    global RightControlUsed, RightControlDown
    tapped := RightControlDown && IsRightControlTap(A_TickCount - RightControlDown,
        RightControlUsed, "RControl")
    RightControlDown := 0
    if tapped && !IsTriggerSearchOpen() {
        global KeyboardTestMode, KeyboardTestLaunchCount
        if KeyboardTestMode
            KeyboardTestLaunchCount += 1
        else
            ShowChooser()
    }
}

IsAutomationChoice(choice) {
    return choice && choice.HasOwnProp("Type") && choice.Type = "automation"
}

ManagedAutomationsAvailable(*) {
    return FileExist(A_ScriptDir "\..\automations\advancedmd\follow-up-office.ahk") != ""
}

AutomationPath(scriptId) {
    global AutomationRegistry
    ; A Sheet ID is never used as a filename, command, or argument.
    if !AutomationRegistry.Has(scriptId)
        throw Error("Unknown automation Script ID.")
    entry := AutomationRegistry[scriptId]
    return entry.File = "" ? "" : A_ScriptDir "\..\automations\" entry.File
}

ParseAutomations(rows, info, output) {
    global AutomationRegistry
    if rows[1].Length < 4
        return
    columns := HeaderMap(rows[1])
    for name in ["name", "alias", "description", "script id"] {
        if !columns.Has(name)
            return
    }
    seen := Map()
    for item in output {
        if IsAutomationChoice(item)
            seen[item.ScriptId] := true
    }
    Loop rows.Length - 1 {
        rowNumber := A_Index + 1
        row := rows[rowNumber]
        id := CanonicalAutomationId(Trim(Cell(row, columns["script id"])))
        name := Trim(Cell(row, columns["name"]))
        if name = "" || !AutomationRegistry.Has(id) || seen.Has(id)
            continue
        seen[id] := true
        aliases := []
        Loop Parse, Cell(row, columns["alias"]), ",;|`n`r" {
            alias := StrLower(Trim(A_LoopField))
            if alias != ""
                aliases.Push(alias)
        }
        description := Trim(Cell(row, columns["description"]))
        output.Push({Type: "automation", ScriptId: id, Key: "automation:" id,
            Label: name, GroupLabel: name, DisplayText: name,
            Content: "", HasSavedContent: false, AiPrompt: "", Category: info.Name,
            Aliases: aliases, Details: [], DetailSearch: StrLower(description),
            DetailOrder: 0, Preview: "Run automation  •  " description,
            EditUrl: EditUrl(info.Gid, rowNumber, columns["name"], columns["name"])})
    }
}

RunAutomation(scriptId, choice := 0) {
    global TargetWindow, ChooserGui, ChooserOpen, AtBoundary, AutomationRegistry
    try {
        path := AutomationPath(scriptId)
        entry := AutomationRegistry[scriptId]
        if path != "" && !FileExist(path)
            throw Error("Automation is not installed. Use Refresh all scripts.")
        target := ChooserOpen ? TargetWindow : WinExist("A")
        if !target || !WinExist("ahk_id " target)
            throw Error("The original window is no longer available.")
        if ChooserOpen {
            HideModifierHud()
            ChooserGui.Hide()
            ChooserOpen := false
        }
        WinActivate "ahk_id " target
        if !WinWaitActive("ahk_id " target, , 1)
            throw Error("Could not return to the original window.")
        if entry.File = ""
            RunBuiltinAutomation entry.Action
        else {
            arguments := entry.Action != "" ? ' "' entry.Action '"' : ""
            ; Alt+Z and the searchable action focus an existing thumbnail as-is.
            mini := scriptId = "zoom.join" ? FindZoomThumbnail() : 0
            if mini
                WinActivate mini.Hwnd
            else
                Run '"' A_AhkPath '" "' path '" ' target arguments
        }
        if choice
            RecordRecent choice
        AtBoundary := true
    } catch as problem {
        ; No clipboard, patient text, or window titles are recorded here.
        MsgBox problem.Message, "Trigger Search automation"
    }
}

CopyLatestInboxNow(*) {
    global Snippets, ChooserGui, ChooserOpen, TargetWindow
    if !RefreshInboxLive()
        return
    choice := LatestInboxChoice()
    if !choice || Trim(choice.Content) = "" {
        TrayTip "Inbox has no usable item.", "Trigger Search"
        return
    }
    expanded := ExpandDynamicContent(choice.Content, A_Clipboard)
    A_Clipboard := expanded.Text
    if ChooserOpen {
        HideModifierHud()
        ChooserGui.Hide()
        ChooserOpen := false
        if TargetWindow && WinExist("ahk_id " TargetWindow)
            try WinActivate "ahk_id " TargetWindow
    }
    TrayTip "Latest Inbox item copied.", "Trigger Search"
}

IsRightControlTap(duration, used, priorKey) {
    return duration < 700 && !used && priorKey = "RControl"
}

ShowKeyboardStatus(*) {
    global AppVersion, RightControlEventCount
    MsgBox "Trigger Search " AppVersion "`nScript: " A_ScriptFullPath
        . "`nRight Ctrl press events seen: " RightControlEventCount
        . "`nTap the keyboard's Right Ctrl, then reopen this status."
        . "`nNo typed text or clipboard content is recorded."
        . "`nCtrl+Alt+Space also opens the launcher.", "Trigger Search status"
}

RunBuiltinAutomation(action) {
    global SpecialClipboard, SpecialClipboardSet, RemapsEnabled
    if action = "builtin:clipboard-store" {
        SpecialClipboard := A_Clipboard
        SpecialClipboardSet := true
        TrayTip "Clipboard value remembered in memory.", "Trigger Search"
    } else if action = "builtin:clipboard-paste" {
        if !SpecialClipboardSet
            throw Error("Remember a clipboard value first (Ctrl+Alt+5).")
        A_Clipboard := SpecialClipboard
        Send "^v"
    } else if action = "builtin:refresh-all" {
        UpdateScriptFromGitHub()
    } else if action = "builtin:remaps" {
        SetKeyboardRemaps !RemapsEnabled
        TrayTip RemapsEnabled ? "Dell remaps enabled." : "Dell remaps disabled.", "Trigger Search"
    } else
        throw Error("Unknown built-in automation.")
}
SendRemappedKey(value, *) {
    Send value
}

ShouldRemapKeys(*) {
    global RemapsEnabled
    return RemapsEnabled && !IsTriggerSearchOpen()
}

RunKeyboardIntegrationTest(*) {
    global RightControlEventCount, KeyboardTestLaunchCount, RightControlDown, RightControlUsed
    result := A_Temp "\trigger-search-keyboard-test.txt"
    try {
        ; Replay handler transitions deterministically. Physical hook delivery must
        ; be checked on the Dell; hosted CI does not expose the user's keyboard.
        BeginRightControlTap()
        Sleep 30
        EndRightControlTap()
        Assert RightControlEventCount = 1, "Right Ctrl down handler did not run."
        Assert KeyboardTestLaunchCount = 1, "Right Ctrl tap did not request the launcher."
        BeginRightControlTap()
        RightControlUsed := IsControlCombination(true, 0x87, 0)
        EndRightControlTap()
        Assert KeyboardTestLaunchCount = 1, "A Ctrl combination incorrectly opened the launcher."
        BeginRightControlTap()
        RightControlDown := A_TickCount - 900
        EndRightControlTap()
        Assert KeyboardTestLaunchCount = 1, "A long hold incorrectly opened the launcher."
        WriteTextAtomic result, "PASS: handler replay; physical keyboard unverified"
        ExitApp 0
    } catch as problem {
        WriteTextAtomic result, problem.Message
        ExitApp 1
    }
}

IsControlCombination(controlHeld, vk, sc) {
    return controlHeld && vk != 0xA3 && sc != 0x11D
}

TestLauncherToggle() {
    global Snippets, SheetId, LastRefreshTick, ChooserOpen, PreviewOpen
    global ChooserGui, PreviewGui, TargetWindow, RecentItems, CategoryParent
    global SearchBox, VisibleChoices, ResultsView
    global DetailParent, SearchServiceParent, ActionsForChoice, AtBoundary
    SheetId := "test-toggle-no-network"
    Snippets := [TestSnippet("Toggle test", "sample", [])]
    RecentItems := []
    CategoryParent := ""
    DetailParent := 0
    SearchServiceParent := 0
    ActionsForChoice := 0
    ChooserOpen := false
    PreviewOpen := false
    LastRefreshTick := A_TickCount
    BuildChooser()
    HandleLauncher()
    Assert ChooserOpen, "F6 must open a closed launcher."
    originalTarget := TargetWindow
    WinGetPos &x, &y, , , "ahk_id " ChooserGui.Hwnd
    Loop 3 {
        ShowChooser()
        WinGetPos &nextX, &nextY, , , "ahk_id " ChooserGui.Hwnd
        Assert TargetWindow = originalTarget && x = nextX && y = nextY,
            "Repeated open requests must retain the target and window position."
    }
    SearchBox.Value := "toggle"
    Snippets := [TestSnippet("Toggle test", "updated", []),
        TestSnippet("Toggle new", "newly fetched", [])]
    RefreshOpenChooser()
    WinGetPos &nextX, &nextY, , , "ahk_id " ChooserGui.Hwnd
    Assert ChooserOpen && SearchBox.Value = "toggle" && TargetWindow = originalTarget
        && x = nextX && y = nextY && VisibleChoices.Length = 2
        && VisibleChoices[1].Content = "updated",
        "A refresh must update results without closing, clearing search, or moving the launcher."
    ResultsView.Modify(0, "-Select -Focus")
    ResultsView.Modify(2, "Select Focus Vis")
    Snippets := [Snippets[2], Snippets[1]]
    RefreshOpenChooser()
    Assert SelectedChoice().Key = "Toggle new",
        "Refreshing must preserve the selected item when it still exists."
    HandleLauncher()
    Assert !IsTriggerSearchOpen(), "A second F6 press must close the launcher."
    HandleLauncher()
    Assert ChooserOpen, "F6 must reopen after closing."
    PreviewGui := Gui("+ToolWindow", "Toggle preview test")
    PreviewGui.Show("w100 h100")
    PreviewOpen := true
    HandleLauncher()
    Assert !IsTriggerSearchOpen(), "F6 must close both preview and chooser."
    HandleLauncher()
    PreviewGui := Gui("+ToolWindow", "Escape preview test")
    PreviewGui.Show("w100 h100")
    PreviewOpen := true
    HandleEscape()
    Assert !IsTriggerSearchOpen(), "Escape must close both preview and chooser."
    ChooserGui.Destroy()
    ChooserGui := 0
}

CanonicalAutomationId(scriptId) {
    ; Explicit trusted aliases for the names already present in Nathan's Sheet.
    aliases := Map("AMD.follow-up-office", "advancedmd.follow-up-office",
        "AMD.follow-up-tele", "advancedmd.follow-up-tele",
        "AMD.intake-office", "advancedmd.intake-office",
        "dell.launch-AMD", "dell.launch-advancedmd")
    return aliases.Has(scriptId) ? aliases[scriptId] : scriptId
}

SendClipboardToInbox(*) {
    global SheetId
    static sending := false
    if sending
        return
    ; Capture once, before setup or a network request. Never write the clipboard.
    content := A_Clipboard
    if Trim(content, " `t`r`n") = "" {
        TrayTip "Copy some text first.", "Trigger Search Inbox"
        return
    }
    if StrLen(content) > 45000 {
        TrayTip "Clipboard text is too long for one Inbox cell (45,000 character limit).", "Trigger Search Inbox"
        return
    }
    sending := true
    try {
        config := LoadInboxWriter()
        if !config
            return
        label := "Dell · " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        SubmitInboxText config, content, label
        ; One live Inbox read also makes the newly written row the local pin.
        RefreshInboxLive()
        RefreshOpenChooser()
        TrayTip "Saved to the top of Inbox.", "Trigger Search"
    } catch {
        ; Do not log request bodies, clipboard data, tokens, or server errors.
        ; A timeout can occur after a committed write; never retry automatically.
        TrayTip "Could not confirm delivery. Clipboard unchanged. Check Inbox before retrying; check Inbox setup if nothing arrived.", "Trigger Search Inbox"
    } finally {
        sending := false
    }
}

LoadInboxWriter() {
    global CacheDir, SheetId
    path := CacheDir "\inbox-api.ini"
    if !FileExist(path) {
        downloaded := EnvGet("USERPROFILE") "\Downloads\Trigger-Search-Inbox-Setup.ini"
        if !FileExist(downloaded) {
            OpenInboxSetupDrive()
            MsgBox "Download Trigger-Search-Inbox-Setup.ini from your private Google Drive to any folder, then click OK and select it. You do not need ChatGPT on this computer.", "One-time Inbox setup"
            downloaded := FileSelect(1, , "Select your downloaded Trigger Search Inbox setup file", "Inbox setup (*.ini)")
        }
        if downloaded = ""
            return 0
        candidate := ReadInboxWriter(downloaded)
        ValidateInboxWriter candidate, SheetId
        DirCreate CacheDir
        ; Only the three configuration values are imported. No Sheet code runs.
        IniWrite candidate.Url, path, "inbox-api", "url"
        IniWrite candidate.Token, path, "inbox-api", "token"
        IniWrite candidate.SheetId, path, "inbox-api", "sheetId"
    }
    config := ReadInboxWriter(path)
    ValidateInboxWriter config, SheetId
    return config
}
ReadInboxWriter(path) {
    return {Url: Trim(IniRead(path, "inbox-api", "url", "")),
        Token: Trim(IniRead(path, "inbox-api", "token", "")),
        SheetId: Trim(IniRead(path, "inbox-api", "sheetId", ""))}
}
ValidateInboxWriter(config, sheetId) {
    if !RegExMatch(config.Url, "^https://script\.google\.com/macros/s/[A-Za-z0-9_-]+/exec$")
        throw Error("Inbox endpoint must be a Google Apps Script web app.")
    if config.Token = "" || InStr(config.Token, "`n") || InStr(config.Token, "`r")
        throw Error("Inbox setup has no valid token.")
    if sheetId = "" || config.SheetId != sheetId
        throw Error("Inbox setup belongs to a different Sheet.")
}
SubmitInboxText(config, content, label, transport := 0) {
    global SheetId
    ValidateInboxWriter config, SheetId
    if Trim(content, " `t`r`n") = "" || StrLen(content) > 45000
        throw Error("Clipboard must contain text that fits in one cell.")
    body := '{"token":' InboxJsonString(config.Token) ',"content":'
        . InboxJsonString(content) ',"label":' InboxJsonString(label) '}'
    result := transport ? transport.Call(config.Url, body) : PostInboxJson(config.Url, body)
    if result.Status != 200 || !InboxWriteSucceeded(result.Body)
        throw Error("Inbox did not confirm a successful write.")
}
PostInboxJson(url, body) {
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(5000, 5000, 10000, 15000)
    request.Open("POST", url, false)
    request.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    request.SetRequestHeader("Accept", "application/json")
    request.Send(body)
    return {Status: request.Status, Body: request.ResponseText}
}
InboxWriteSucceeded(body) {
    ; The existing endpoint returns {ok: true, message: ...} in this order.
    ; Never mistake HTML, an error object, or a quoted message for confirmation.
    return RegExMatch(body, '^\s*\{\s*"ok"\s*:\s*true\s*[,}]') != 0
}
InboxJsonString(value) {
    escaped := '"'
    Loop Parse value {
        char := A_LoopField
        if char = '"'
            escaped .= '\"'
        else if char = '\'
            escaped .= '\\'
        else if Ord(char) < 32
            escaped .= Format("\u{:04x}", Ord(char))
        else
            escaped .= char
    }
    return escaped '"'
}

TestInboxWriter() {
    global SheetId
    oldSheet := SheetId
    SheetId := "test-inbox-sheet"
    config := {Url: "https://script.google.com/macros/s/TEST_ONLY/exec", Token: "fake-test-token", SheetId: SheetId}
    sample := 'Line "one"\path' "`n`t" "café — 漢字"
    Assert InboxJsonString(sample) = '"Line \"one\"\\path\u000a\u0009café — 漢字"',
        "Clipboard JSON must preserve quotes, slashes, newlines, tabs, and Unicode in one cell."
    Assert InboxWriteSucceeded('{"ok":true,"message":"Saved to Inbox."}'), "A saved response must be accepted."
    Assert !InboxWriteSucceeded('{"ok":false,"message":"failed"}')
        && !InboxWriteSucceeded('<html>ok:true</html>')
        && !InboxWriteSucceeded('{"message":"ok:true"}'), "Only a successful endpoint response may confirm delivery."
    preservedClipboard := A_Clipboard
    SubmitInboxText config, sample, "Dell test", (url, body) => {Status: 200, Body: '{"ok":true}'}
    Assert A_Clipboard = preservedClipboard, "Sending must never change the clipboard."
    rejected := false
    try SubmitInboxText config, "", "test", (url, body) => {Status: 200, Body: '{"ok":true}'}
    catch
        rejected := true
    Assert rejected, "An empty clipboard must not be sent."
    rejected := false
    try SubmitInboxText config, "test", "test", (url, body) => {Status: 200, Body: '{"ok":false}'}
    catch
        rejected := true
    Assert rejected && A_Clipboard = preservedClipboard, "An API rejection must retain the clipboard and never report success."
    config.SheetId := "some-other-sheet"
    rejected := false
    try SubmitInboxText config, "test", "test", (url, body) => {Status: 200, Body: '{"ok":true}'}
    catch
        rejected := true
    Assert rejected, "A setup file for a different Sheet must not send anything."
    config.SheetId := SheetId
    config.Url := "https://example.com/collect"
    rejected := false
    try ValidateInboxWriter config, SheetId
    catch
        rejected := true
    Assert rejected, "Inbox setup must not transmit clipboard data to another host."
    SheetId := oldSheet
}

KeyboardRemapMap() {
    return Map("Insert", "^c", "Home", "^v", "Delete", "^x", "#End", "^s",
        "PgUp", "^a", "PgDn", "^z", "NumpadEnd", "^w", "F10", "^f")
}
InitializeKeyboardRemaps() {
    global SettingsPath
    ; Existing Dell behavior belongs to the managed launcher now. A saved toggle
    ; takes priority over the first-install default and survives code refreshes.
    enabled := ManagedAutomationsAvailable()
        && IniRead(SettingsPath, "keyboard", "remapsEnabled", "1") = "1"
    SetKeyboardRemaps enabled, false
}
SetKeyboardRemaps(enabled, persist := true) {
    global RemapsEnabled, SettingsPath
    HotIf ShouldRemapKeys
    for key, value in KeyboardRemapMap()
        Hotkey "$" key, SendRemappedKey.Bind(value), enabled ? "On" : "Off"
    HotIf
    RemapsEnabled := !!enabled
    if persist
        IniWrite enabled ? "1" : "0", SettingsPath, "keyboard", "remapsEnabled"
}
TestKeyboardRemaps() {
    global RemapsEnabled, ChooserOpen, PreviewOpen, SettingsPath
    savedEnabled := RemapsEnabled
    savedChooser := ChooserOpen
    savedPreview := PreviewOpen
    savedSettings := SettingsPath
    SettingsPath := A_Temp "\trigger-remap-test-" A_TickCount ".ini"
    try {
        ChooserOpen := false
        PreviewOpen := false
        InitializeKeyboardRemaps()
        Assert RemapsEnabled && ShouldRemapKeys(), "Managed installs must enable original single-key remaps by default."
        ChooserOpen := true
        Assert !ShouldRemapKeys(), "Remaps must leave navigation and editing normal inside the launcher."
        ChooserOpen := false
        SetKeyboardRemaps false
        InitializeKeyboardRemaps()
        Assert !RemapsEnabled && !ShouldRemapKeys(), "An explicit remap OFF choice must survive initialization."
        SetKeyboardRemaps true
        InitializeKeyboardRemaps()
        Assert RemapsEnabled, "An explicit remap ON choice must survive initialization."
    } finally {
        if FileExist(SettingsPath)
            FileDelete SettingsPath
        SettingsPath := savedSettings
        SetKeyboardRemaps savedEnabled, false
        ChooserOpen := savedChooser
        PreviewOpen := savedPreview
    }
}
OpenInboxSetupDrive(*) {
    Run "https://drive.google.com/file/d/1EjiWxMRvjII8yqJzbancrXXC3GOuykP_/view?usp=drivesdk"
}


; Zoom window controls run in the existing launcher, without another resident.
ActiveZoomMeeting() {
    hwnd := WinActive("ahk_exe Zoom.exe")
    if !hwnd
        return 0
    try {
        return ZoomControlCandidate(WinGetTitle(hwnd), WinGetClass(hwnd)) || ZoomThumbnailButton(hwnd) ? hwnd : 0
    }
    return 0
}
ZoomControlCandidate(title, className) {
    return className = "ZPContentViewWndClass" || RegExMatch(title, "i)Zoom (Meeting|Webinar)") != 0
}
ZoomControlArea(x, y, width, height) {
    monitor := MonitorGetPrimary()
    Loop MonitorGetCount() {
        MonitorGet A_Index, &left, &top, &right, &bottom
        if x + width / 2 >= left && x + width / 2 < right && y + height / 2 >= top && y + height / 2 < bottom {
            monitor := A_Index
            break
        }
    }
    MonitorGetWorkArea monitor, &left, &top, &right, &bottom
    return {Left: left + 24, Top: top + 24, Right: right - 24, Bottom: bottom - 24}
}
ZoomControlAnchor(position, start, available, size) {
    return available <= size ? 0 : Max(0, Min(2, Round(2 * (position - start) / (available - size))))
}
ZoomControlBounds(area, x, y, width, height, command) {
    availableWidth := Max(100, area.Right - area.Left)
    availableHeight := Max(100, area.Bottom - area.Top)
    horizontal := ZoomControlAnchor(x, area.Left, availableWidth, width)
    vertical := ZoomControlAnchor(y, area.Top, availableHeight, height)
    switch command {
        case "left": horizontal := Max(0, horizontal - 1)
        case "right": horizontal := Min(2, horizontal + 1)
        case "up": vertical := Max(0, vertical - 1)
        case "down": vertical := Min(2, vertical + 1)
        case "up-left": horizontal := 0, vertical := 0
        case "up-right": horizontal := 2, vertical := 0
        case "down-left": horizontal := 0, vertical := 2
        case "down-right": horizontal := 2, vertical := 2
        case "2": width := 640, height := 480
        case "3": width := 960, height := 720
        case "4": width := 1280, height := 960
        default: throw Error("Unknown Zoom window command.")
    }
    width := Min(width, availableWidth), height := Min(height, availableHeight)
    return {X: area.Left + Round((availableWidth - width) * horizontal / 2),
        Y: area.Top + Round((availableHeight - height) * vertical / 2),
        Width: width, Height: height, Horizontal: horizontal, Vertical: vertical}
}
ZoomWindowCommand(command) {
    static busy := false
    if busy
        return
    hwnd := ActiveZoomMeeting()
    if !hwnd
        return
    busy := true
    try {
        if RegExMatch(command, "^(left|right|up|down)$") {
            ; Capture both key-down orders. The second hotkey may be suppressed
            ; by busy, but its physical key state is still sampled here.
            left := command = "left" || GetKeyState("Left", "P")
            right := command = "right" || GetKeyState("Right", "P")
            up := command = "up" || GetKeyState("Up", "P")
            down := command = "down" || GetKeyState("Down", "P")
            Sleep 45
            command := ZoomDirectionChord(command, left || GetKeyState("Left", "P"),
                right || GetKeyState("Right", "P"), up || GetKeyState("Up", "P"), down || GetKeyState("Down", "P"))
        }
        ; Do not move a window if the user switched applications during sampling.
        if ActiveZoomMeeting() != hwnd
            return
        window := "ahk_id " hwnd
        thumbnail := ZoomThumbnailButton(hwnd)
        if command = "1" {
            if !thumbnail
                EnterZoomThumbnail hwnd
            return
        }
        ; Direction keys move the thumbnail itself; size keys expand it first.
        if thumbnail && RegExMatch(command, "^[2-5]$") {
            hwnd := RestoreZoomThumbnail(hwnd, thumbnail)
            window := "ahk_id " hwnd
        }
        if command = "5" {
            WinMaximize window
            return
        }
        ; Restore before measuring the normal window rectangle, not fullscreen bounds.
        if WinGetMinMax(window) != 0 {
            WinRestore window
            Sleep 100
        }
        WinGetPos &x, &y, &width, &height, window
        area := ZoomControlArea(x, y, width, height)
        bounds := ZoomControlBounds(area, x, y, width, height, command)
        WinMove bounds.X, bounds.Y, bounds.Width, bounds.Height, window
        Sleep 100
        ; Respect Zoom's enforced minimum dimensions while retaining the chosen anchor.
        WinGetPos , , &actualWidth, &actualHeight, window
        WinMove area.Left + Round(Max(0, area.Right - area.Left - actualWidth) * bounds.Horizontal / 2),
            area.Top + Round(Max(0, area.Bottom - area.Top - actualHeight) * bounds.Vertical / 2), , , window
    } catch as problem {
        TrayTip problem.Message, "Trigger Search Zoom"
    } finally {
        busy := false
    }
}
TestZoomWindowControls() {
    area := {Left: -1896, Top: 24, Right: -24, Bottom: 1016}
    for direction in ["left", "up"] {
        chord := ZoomDirectionChord(direction, true, false, true, false)
        corner := ZoomControlBounds(area, -664, 536, 640, 480, chord)
        Assert corner.X = area.Left && corner.Y = area.Top,
            "Either key-down order of Left+Up must snap directly from bottom right to top left."
    }
    for keys in [[false, true, true, false, "up-right"], [true, false, false, true, "down-left"],
        [false, true, false, true, "down-right"]]
        Assert ZoomDirectionChord("left", keys[1], keys[2], keys[3], keys[4]) = keys[5], "All four diagonal chords must be supported."
    Assert ZoomDirectionChord("left", true, true, true, false) = "left", "Opposing arrow keys must not invent a diagonal."
    b := ZoomControlBounds(area, -1280, 24, 640, 480, "left")
    Assert b.X = -1896 && b.Y = 24 && b.Width = 640, "Zoom left preserves size and top anchor on a negative-coordinate monitor."
    b := ZoomControlBounds(area, b.X, b.Y, b.Width, b.Height, "down")
    Assert b.Vertical = 1 && b.Horizontal = 0, "Zoom arrows move independently through a three-by-three grid."
    b := ZoomControlBounds(area, b.X, b.Y, b.Width, b.Height, "down")
    Assert b.Y = 536, "A second down press reaches the bottom."
    b := ZoomControlBounds(area, b.X, b.Y, b.Width, b.Height, "3")
    Assert b.X = area.Left && b.Y = 296 && b.Width = 960 && b.Height = 720, "Zoom resizing preserves bottom-left anchor."
    b := ZoomControlBounds({Left: 24, Top: 64, Right: 576, Bottom: 416}, 24, 64, 552, 352, "4")
    Assert b.Width = 552 && b.Height = 352, "Zoom size presets fit small work areas."
    Assert !ZoomControlCandidate("Zoom Workplace", "HomeWindow") && ZoomControlCandidate("Zoom Meeting", "MeetingWindow"),
        "Zoom controls must not intercept shortcuts in the home window."
}


; Use Windows accessibility to identify Zoom's documented thumbnail expansion
; button, not guessed window classes, screen coordinates, or a tiny resized main
; window. English button names only. No UI text is saved or logged.
ZoomThumbnailButton(hwnd) {
    static cache := Map()
    try {
        pid := WinGetPID(hwnd)
        if cache.Has(hwnd) && cache[hwnd].Pid = pid && A_TickCount - cache[hwnd].Tick < 500
            return cache[hwnd].Button
        button := FindZoomAccessibilityButton(hwnd, "i)^(Show full meeting window|Exit minimi[sz]ed video|Exit mini window|Restore full meeting window)$")
        if cache.Count > 32
            cache.Clear()
        cache[hwnd] := {Pid: pid, Tick: A_TickCount, Button: button}
        return button
    }
    return 0
}
FindZoomThumbnail(pid := 0) {
    for hwnd in WinGetList("ahk_exe Zoom.exe") {
        try {
            if pid && WinGetPID(hwnd) != pid
                continue
            if WinGetMinMax(hwnd) = -1
                continue
            if button := ZoomThumbnailButton(hwnd)
                return {Hwnd: hwnd, Button: button}
        }
    }
    return 0
}
FindZoomMainWindow(pid) {
    previous := DetectHiddenWindows(true)
    try {
        for hwnd in WinGetList("ahk_exe Zoom.exe ahk_pid " pid) {
            try {
                if ZoomControlCandidate(WinGetTitle(hwnd), WinGetClass(hwnd)) && !ZoomThumbnailButton(hwnd)
                    return hwnd
            }
        }
    } finally {
        DetectHiddenWindows previous
    }
    return 0
}
EnterZoomThumbnail(hwnd) {
    pid := WinGetPID(hwnd)
    WinGetPos &x, &y, &width, &height, hwnd
    area := ZoomControlArea(x, y, width, height)
    horizontal := ZoomControlAnchor(x, area.Left, area.Right - area.Left, width)
    vertical := ZoomControlAnchor(y, area.Top, area.Bottom - area.Top, height)
    button := FindZoomAccessibilityButton(hwnd, "i)^(Minimi[sz]e|Minimi[sz]e meeting|Minimi[sz]e window)$")
    if button
        button.Acc.accDoDefaultAction(button.Child)
    else
        ; Deliver the same system command as the native title-bar minimize
        ; button, allowing Zoom to handle its own thumbnail mode.
        PostMessage 0x0112, 0xF020, 0, , hwnd
    deadline := A_TickCount + 2000
    while A_TickCount < deadline {
        if mini := FindZoomThumbnail(pid) {
            WinGetPos , , &w, &h, mini.Hwnd
            WinMove area.Left + Round(Max(0, area.Right - area.Left - w) * horizontal / 2),
                area.Top + Round(Max(0, area.Bottom - area.Top - h) * vertical / 2), , , mini.Hwnd
            WinActivate mini.Hwnd
            return
        }
        Sleep 100
    }
    ; Never silently leave the call hidden when the requested visible thumbnail
    ; could not be positively identified. Restore the original main window.
    WinShow hwnd
    WinRestore hwnd
    WinActivate hwnd
    throw Error("Could not confirm Zoom's floating video. The main window was restored. Try Zoom's minimize button; its thumbnail control may differ on this version.")
}
RestoreZoomThumbnail(hwnd, button) {
    pid := WinGetPID(hwnd)
    WinGetPos &x, &y, &width, &height, hwnd
    area := ZoomControlArea(x, y, width, height)
    horizontal := ZoomControlAnchor(x, area.Left, area.Right - area.Left, width)
    vertical := ZoomControlAnchor(y, area.Top, area.Bottom - area.Top, height)
    button.Acc.accDoDefaultAction(button.Child)
    deadline := A_TickCount + 2000
    while A_TickCount < deadline {
        main := FindZoomMainWindow(pid)
        if main && DllCall("IsWindowVisible", "ptr", main) && WinGetMinMax(main) != -1 {
            WinActivate main
            if !WinWaitActive("ahk_id " main, , 1)
                throw Error("Zoom did not focus the full meeting window. Use its Show full meeting window button.")
            WinRestore main
            WinGetPos , , &w, &h, main
            WinMove area.Left + Round(Max(0, area.Right - area.Left - w) * horizontal / 2),
                area.Top + Round(Max(0, area.Bottom - area.Top - h) * vertical / 2), , , main
            return main
        }
        Sleep 100
    }
    throw Error("Zoom did not expand its thumbnail. Use its Show full meeting window button, then try the size key again.")
}
FindZoomAccessibilityButton(hwnd, pattern) {
    try {
        iid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "wstr", "{618736E0-3C3D-11CF-810C-00AA00389B71}", "ptr", iid)
        pointer := 0
        if DllCall("oleacc\AccessibleObjectFromWindow", "ptr", hwnd, "uint", 0xFFFFFFFC,
            "ptr", iid, "ptr*", &pointer, "int") != 0 || !pointer
            return 0
        root := ComValue(9, pointer, 1)
        budget := 600
        return FindZoomAccessibleNode(root, 0, pattern, 0, &budget)
    }
    return 0
}
FindZoomAccessibleNode(acc, child, pattern, depth, &budget) {
    if budget <= 0 || depth > 12
        return 0
    budget -= 1
    try {
        ; Match buttons only. Never invoke controls by approximate position.
        if acc.accRole(child) = 43 && !(acc.accState(child) & 0x8001)
            && RegExMatch(Trim(StrReplace(acc.accName(child), "&")), pattern)
            return {Acc: acc, Child: child}
    }
    if child != 0
        return 0
    try {
        count := Min(acc.accChildCount, budget)
        if count <= 0
            return 0
        size := 8 + 2 * A_PtrSize
        children := Buffer(count * size, 0)
        obtained := 0
        if DllCall("oleacc\AccessibleChildren", "ptr", ComObjValue(acc), "int", 0,
            "int", count, "ptr", children, "int*", &obtained, "int") < 0
            return 0
        result := 0
        Loop obtained {
            offset := (A_Index - 1) * size
            type := NumGet(children, offset, "ushort")
            try {
                if !result && type = 9 {
                    ; Transfer the child's COM reference to an owning wrapper.
                    pointer := NumGet(children, offset + 8, "ptr")
                    NumPut "ptr", 0, children, offset + 8
                    node := ComValue(9, pointer, 1)
                    result := FindZoomAccessibleNode(node, 0, pattern, depth + 1, &budget)
                } else if !result && type = 3
                    result := FindZoomAccessibleNode(acc, NumGet(children, offset + 8, "int"), pattern, depth + 1, &budget)
            } finally {
                DllCall("oleaut32\VariantClear", "ptr", children.Ptr + offset)
            }
        }
        return result
    }
    return 0
}
TestZoomAccessibility() {
    fixture := Gui("+ToolWindow", "Trigger Search accessibility fixture")
    counter := {Count: 0}
    fixture.AddButton("w200", "Show full meeting window").OnEvent("Click", (*) => counter.Count += 1)
    fixture.AddButton("w200", "End meeting").OnEvent("Click", (*) => counter.Count += 100)
    fixture.Show("NA w240 h120")
    try {
        button := FindZoomAccessibilityButton(fixture.Hwnd, "i)^Show full meeting window$")
        Assert IsObject(button), "Find the exact thumbnail expansion button using real Windows accessibility."
        button.Acc.accDoDefaultAction(button.Child)
        Sleep 100
        Assert counter.Count = 1, "Invoke only the expansion button, never End meeting."
        Assert !FindZoomAccessibilityButton(fixture.Hwnd, "i)^Minimize$"), "A missing control must not trigger a guessed click."
    } finally {
        fixture.Destroy()
    }
}

ZoomDirectionChord(command, left, right, up, down) {
    if left != right && up != down
        return (up ? "up" : "down") "-" (left ? "left" : "right")
    return command
}
