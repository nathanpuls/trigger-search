#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Sheet Autocomplete version 0.8.0
global AppVersion := "0.8.0"

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
global Refreshing := false
global LastRefreshError := ""
global LastShownRefreshError := ""
global RefreshFailureCount := 0
global AtBoundary := true
global LastActiveWindow := 0
global TargetWindow := 0
global ChooserOpen := false
global SheetInfos := []
global Snippets := []
global VisibleChoices := []
global DetailParent := 0
global RootQuery := ""
global ReturnParentKey := ""
global KeyboardWatcher := 0

global ChooserGui := 0
global SearchBox := 0
global ResultsView := 0

if A_Args.Length > 0 && A_Args[1] = "--self-test"
    RunSelfTestsAndExit()

OnError HandleUnexpectedError
Initialize()

#HotIf IsChooserOpen()
Up::MoveSelection(-1)
Down::MoveSelection(1)
Enter::ChooseSelected()
*Esc::CancelChooser()
Right::OpenSelectedDetails()
Left::CloseDetails()
^e::EditSelected()
^1::ChooseVisibleByNumber(1)
^2::ChooseVisibleByNumber(2)
^3::ChooseVisibleByNumber(3)
^4::ChooseVisibleByNumber(4)
^5::ChooseVisibleByNumber(5)
^6::ChooseVisibleByNumber(6)
^7::ChooseVisibleByNumber(7)
^8::ChooseVisibleByNumber(8)
^9::ChooseVisibleByNumber(9)
#HotIf

~LButton::ResetBoundary()
~RButton::ResetBoundary()
~MButton::ResetBoundary()

Initialize() {
    global CacheDir, RefreshIntervalMs, Trigger, SheetId
    global Snippets, AppVersion

    DirCreate CacheDir
    A_IconTip := "Trigger Search v" AppVersion
    LoadSheetConfiguration()
    LoadCache()
    BuildChooser()
    InstallTrigger(Trigger)
    StartKeyboardWatcher()

    A_TrayMenu.Add()
    A_TrayMenu.Add("Trigger Search v" AppVersion, (*) => 0)
    A_TrayMenu.Disable("Trigger Search v" AppVersion)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Open autocomplete", (*) => ShowChooser())
    A_TrayMenu.Add("Refresh snippets", RefreshData)
    A_TrayMenu.Add("Open Google Sheet", (*) => OpenWorkbook())
    A_TrayMenu.Add("Change Google Sheet...", (*) => PromptForGoogleSheet(false))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Update script from GitHub", UpdateScriptFromGitHub)
    A_TrayMenu.Add("Show last error report", ShowLastErrorReport)

    SetTimer CheckActiveWindow, 400
    SetTimer RefreshData, RefreshIntervalMs
    if SheetId = ""
        SetTimer () => PromptForGoogleSheet(true), -100
    else if Snippets.Length = 0
        RefreshData()
    else
        SetTimer RefreshData, -25
}

BuildChooser() {
    global ChooserGui, SearchBox, ResultsView

    ChooserGui := Gui("+AlwaysOnTop +ToolWindow", "Trigger Search")
    ChooserGui.MarginX := 14
    ChooserGui.MarginY := 12
    ChooserGui.SetFont("s10", "Segoe UI")

    SearchBox := ChooserGui.Add("Edit", "xm w730 h30 vQuery")
    ResultsView := ChooserGui.Add(
        "ListView",
        "xm y+8 w730 r12 -Multi -Hdr",
        ["Shortcut", "Label", "Details"]
    )
    ResultsView.ModifyCol(1, 65)
    ResultsView.ModifyCol(2, 225)
    ResultsView.ModifyCol(3, 400)

    SearchBox.OnEvent("Change", SearchChanged)
    ResultsView.OnEvent("DoubleClick", ResultDoubleClicked)
    ChooserGui.OnEvent("Close", (*) => CancelChooser())
    ChooserGui.OnEvent("Escape", (*) => CancelChooser())

    SetSearchPlaceholder("Search")
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
    global ChooserGui, DetailParent

    if DetailParent
        ChooserGui.Title := "Trigger Search — " DetailParent.GroupLabel " details"
    else
        ChooserGui.Title := "Trigger Search"
    SetSearchPlaceholder("Search")
}

StartKeyboardWatcher() {
    global KeyboardWatcher

    if IsObject(KeyboardWatcher) && KeyboardWatcher.InProgress
        return

    KeyboardWatcher := InputHook("V L0 I1")
    KeyboardWatcher.NotifyNonText := true
    KeyboardWatcher.OnChar := TrackTypedCharacter
    KeyboardWatcher.OnKeyDown := TrackNonTextKey
    KeyboardWatcher.Start()
}

TrackTypedCharacter(input, characters) {
    global AtBoundary, Trigger, ChooserOpen

    if ChooserOpen
        return

    lastCharacter := SubStr(characters, -1)
    if lastCharacter = Trigger
        return
    AtBoundary := RegExMatch(lastCharacter, "\s") != 0
}

TrackNonTextKey(input, vk, sc) {
    global AtBoundary, ChooserOpen

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
    AtBoundary := true
}

CheckActiveWindow(*) {
    global LastActiveWindow, AtBoundary, ChooserOpen

    EnsureKeyboardWatcher()
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
    global Snippets, TargetWindow, ChooserOpen, DetailParent, RootQuery
    global ReturnParentKey, SearchBox, ChooserGui
    global Refreshing, LastRefreshError, SheetId

    if SheetId = "" {
        PromptForGoogleSheet(true)
        if SheetId = ""
            return
    }

    if Snippets.Length = 0 {
        if !Refreshing
            RefreshData()
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
    RootQuery := ""
    ReturnParentKey := ""
    UpdateChooserContext()
    SearchBox.Value := ""
    RenderChoices(FilterChoices(""))
    PositionChooser(TargetWindow)
    SearchBox.Focus()
    SetTimer RefreshData, -10
}

PositionChooser(targetHwnd) {
    global ChooserGui

    try {
        WinGetPos &x, &y, &width, &height, "ahk_id " targetHwnd
        left := x + Floor((width - 760) / 2)
        top := y + Max(40, Floor((height - 450) / 3))
        ChooserGui.Show("w760 h450 x" left " y" top)
    } catch {
        ChooserGui.Show("w760 h450 Center")
    }
}

CancelChooser(*) {
    global ChooserOpen, ChooserGui, DetailParent, RootQuery, AtBoundary

    if !ChooserOpen
        return
    ChooserGui.Hide()
    ChooserOpen := false
    DetailParent := 0
    RootQuery := ""
    AtBoundary := true
}

IsChooserOpen(*) {
    global ChooserOpen
    return ChooserOpen
}

SearchChanged(control, info) {
    global DetailParent, RootQuery

    query := control.Value
    if !DetailParent
        RootQuery := query
    RenderChoices(FilterChoices(query))
}

FilterChoices(query) {
    global Snippets, DetailParent

    needle := StrLower(Trim(query))
    ranked := []
    source := DetailParent ? DetailParent.Details : Snippets

    for item in source {
        label := StrLower(DetailParent ? item.DetailName : item.Label)
        category := StrLower(item.Category)
        directContent := StrLower(item.Content)
        nestedContent := StrLower(item.DetailSearch)
        aliasExact := false
        aliasPrefix := false
        aliasContains := false

        if !DetailParent && needle != "" {
            for alias in item.Aliases {
                if alias = needle
                    aliasExact := true
                if SubStr(alias, 1, StrLen(needle)) = needle
                    aliasPrefix := true
                if InStr(alias, needle)
                    aliasContains := true
            }
        }

        rank := -1
        if needle = ""
            rank := 0
        else if aliasExact
            rank := 0
        else if label = needle
            rank := 1
        else if aliasPrefix
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
            ranked.Push({Item: item, Rank: rank})
    }

    InsertionSort ranked, CompareRanked
    choices := []
    for entry in ranked
        choices.Push(entry.Item)
    return choices
}

CompareRanked(a, b) {
    if a.Rank != b.Rank
        return a.Rank < b.Rank ? -1 : 1

    aGroup := StrLower(a.Item.GroupLabel)
    bGroup := StrLower(b.Item.GroupLabel)
    if aGroup != bGroup
        return StrCompare(aGroup, bGroup)

    aCategory := StrLower(a.Item.Category)
    bCategory := StrLower(b.Item.Category)
    if aCategory != bCategory
        return StrCompare(aCategory, bCategory)

    if a.Item.DetailOrder != b.Item.DetailOrder
        return a.Item.DetailOrder < b.Item.DetailOrder ? -1 : 1
    return StrCompare(StrLower(a.Item.Label), StrLower(b.Item.Label))
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
    if row = 0
        row := ResultsView.GetNext(0, "S")
    if row < 1 || row > VisibleChoices.Length
        return 0
    return VisibleChoices[row]
}

ChooseSelected(*) {
    choice := SelectedChoice()
    if !choice
        return
    ChooseChoice choice
}

ResultDoubleClicked(control, row) {
    global VisibleChoices

    if row >= 1 && row <= VisibleChoices.Length
        ChooseChoice VisibleChoices[row]
}

ChooseChoice(choice) {
    PasteChoice choice
}

PasteChoice(choice) {
    global TargetWindow, ChooserGui, ChooserOpen, AtBoundary

    clipboardText := A_Clipboard
    savedClipboard := ClipboardAll()
    expanded := ExpandDynamicContent(choice.Content, clipboardText)
    ChooserGui.Hide()
    ChooserOpen := false
    A_Clipboard := expanded.Text
    if !ClipWait(1) {
        A_Clipboard := savedClipboard
        return
    }

    if TargetWindow
        WinActivate "ahk_id " TargetWindow
    Sleep 80
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

OpenSelectedDetails(*) {
    global DetailParent, RootQuery, SearchBox, ReturnParentKey

    if DetailParent
        return
    choice := SelectedChoice()
    if !choice || !choice.HasOwnProp("Details") || choice.Details.Length = 0
        return

    RootQuery := SearchBox.Value
    ReturnParentKey := choice.Key
    DetailParent := choice
    UpdateChooserContext()
    SearchBox.Value := ""
    RenderChoices(FilterChoices(""))
    SearchBox.Focus()
}

CloseDetails(*) {
    global DetailParent, SearchBox, RootQuery, ReturnParentKey
    global ResultsView, VisibleChoices

    if !DetailParent
        return
    DetailParent := 0
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
    global ChooserGui, ChooserOpen

    choice := SelectedChoice()
    if !choice || !choice.EditUrl
        return
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
    global LastRefreshError, LastShownRefreshError, RefreshFailureCount

    oldSheetId := SheetId
    oldInfos := SheetInfos
    oldSnippets := Snippets
    oldTrigger := Trigger
    stage := "checking the Google Sheet"

    try {
        DownloadWorkbook newSheetId, &infos, &csvByName, &stage
        SheetId := newSheetId
        ApplySheets infos, csvByName
        if Snippets.Length = 0
            throw Error("No usable autocomplete rows were found. Each data tab needs Label and Content headers.")

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
        SheetInfos := oldInfos
        Snippets := oldSnippets
        InstallTrigger oldTrigger
        report := RecordError(problem, "Connecting a Google Sheet — " stage)
        MsgBox "Trigger Search could not use that Sheet."
            . "`n`n" problem.Message
            . "`n`nMake sure the link is correct and the workbook is published to the web."
            . "`n`nTechnical details were saved to the last error report.",
            title
        return false
    }
}

UpdateScriptFromGitHub(*) {
    global UpdateUrl

    backup := A_ScriptFullPath ".backup"

    try {
        replacement := FetchLiveGitHubFile(UpdateUrl)

        if !InStr(replacement, "#Requires AutoHotkey v2.0")
            || !InStr(replacement, "; Sheet Autocomplete version ")
            throw Error("GitHub did not return a valid Sheet Autocomplete script.")

        current := FileRead(A_ScriptFullPath, "UTF-8")
        if current = replacement {
            TrayTip "You already have the newest version.", "Trigger Search"
            return
        }

        if FileExist(backup)
            FileDelete backup
        FileCopy A_ScriptFullPath, backup, 1
        WriteTextAtomic A_ScriptFullPath, replacement
        TrayTip "Update installed. Reloading now...", "Trigger Search"
        Sleep 500
        Reload
    } catch as problem {
        report := RecordError(problem, "Updating the script from GitHub")
        MsgBox report, "Trigger Search update error"
    }
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
    request.Open("GET", url, false)
    request.SetRequestHeader("Accept", accept)
    request.SetRequestHeader("User-Agent", "SheetAutocomplete")
    request.SetRequestHeader("Cache-Control", "no-cache")
    request.Send()

    if request.Status != 200
        throw Error("GitHub returned HTTP " request.Status ".")
    return request.ResponseText
}

RefreshData(*) {
    global Refreshing, SheetId, SheetInfos, LastRefreshError
    global LastShownRefreshError, RefreshFailureCount, Snippets

    if Refreshing
        return
    if SheetId = ""
        return
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
    return rows.Length > 0 && rows[1].Length >= 2
}

RefreshOpenChooser() {
    global ChooserOpen, DetailParent, Snippets, SearchBox
    global RootQuery, VisibleChoices, ResultsView

    if !ChooserOpen
        return

    selected := SelectedChoice()
    selectedKey := selected && selected.HasOwnProp("Key") ? selected.Key : ""

    if DetailParent {
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
    global Snippets, DetailParent

    DetailParent := 0
    Snippets := [
        TestSnippet("meeting", "meet", ["mtg"]),
        TestSnippet("email address", "email@example.com", ["email"])
    ]

    unfiltered := FilterChoices("")
    Assert unfiltered.Length = 2, "Empty search should return every snippet."

    aliasMatch := FilterChoices("email")
    Assert aliasMatch.Length > 0, "Alias search should return a result."
    Assert aliasMatch[1].Label = "email address",
        "Exact alias match should rank first."

    parsed := []
    ParseSheet '"Label","Alias","Content"`n"apple","","red apple"',
        {Name: "Test", Gid: "123"}, parsed
    Assert parsed.Length = 1, "A standard Label and Content row should parse."
    Assert parsed[1].Label = "apple", "The parsed Label should remain apple."
    Assert parsed[1].Content = "red apple",
        "The parsed Content should remain red apple."
    Assert InStr(parsed[1].EditUrl, "&range=C2"),
        "Editing a standard snippet should target its pasted Content cell."

    labelOnly := []
    ParseSheet '"Label","Alias","Content"`n"apple","",""',
        {Name: "Test", Gid: "123"}, labelOnly
    Assert InStr(labelOnly[1].EditUrl, "&range=A2"),
        "Editing a Label-only snippet should target its pasted Label cell."

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

    directMatch := TestSnippet("doctor note", "Dr. White", [])
    nestedOnlyMatch := TestSnippet("medication", "regular content", [])
    nestedOnlyMatch.DetailSearch := " side effect white"
    Snippets := [nestedOnlyMatch, directMatch]
    contentMatch := FilterChoices("white")
    Assert contentMatch.Length = 2,
        "Direct and nested content matches should both remain searchable."
    Assert contentMatch[1].Label = "doctor note",
        "Direct Content should rank ahead of nested detail text."

    Assert LooksLikeCsv("Label,Content`napple,red apple"),
        "Unquoted public export CSV should be accepted."
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
    temporary := A_Temp "\sheet-autocomplete-" A_TickCount "-" Random(1000, 9999) ".tmp"
    try {
        Download url, temporary
        return FileRead(temporary, "UTF-8")
    } finally {
        if FileExist(temporary)
            FileDelete temporary
    }
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

    InsertionSort parsed, CompareSnippets
    Snippets := parsed
}

ApplySettings(infos, csvByName) {
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
        }
    }
}

ParseSheet(csv, info, output) {
    rows := ParseCsv(csv)
    if rows.Length = 0
        return
    columns := HeaderMap(rows[1])
    if !columns.Has("label") && !columns.Has("content")
        return

    labelColumn := columns.Has("label") ? columns["label"] : 0
    contentColumn := columns.Has("content") ? columns["content"] : 0
    aliasColumn := columns.Has("alias") ? columns["alias"] : 0

    Loop rows.Length - 1 {
        rowNumber := A_Index + 1
        row := rows[rowNumber]
        sheetLabel := labelColumn ? Trim(Cell(row, labelColumn)) : ""
        sheetContent := contentColumn ? Cell(row, contentColumn) : ""
        label := sheetLabel != "" ? sheetLabel : Trim(sheetContent)
        if label = ""
            continue
        content := Trim(sheetContent) != "" ? sheetContent : label
        editColumn := Trim(sheetContent) != "" ? contentColumn : labelColumn

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
            Category: info.Name,
            Aliases: aliases,
            Details: [],
            DetailSearch: "",
            DetailOrder: 0,
            Preview: MakePreview(sheetLabel, sheetContent, info.Name),
            EditUrl: EditUrl(info.Gid, rowNumber, Max(1, editColumn),
                Max(1, editColumn))
        }

        for columnIndex, header in rows[1] {
            detailName := Trim(StrReplace(header, Chr(0xFEFF)))
            normalizedDetailName := StrLower(detailName)
            if detailName = "" || normalizedDetailName = "label"
                || normalizedDetailName = "content"
                || normalizedDetailName = "alias"
                continue
            detailContent := Cell(row, columnIndex)
            if Trim(detailContent) = ""
                continue

            detail := {
                Type: "detail",
                Key: root.Key ":" columnIndex,
                Label: label " " detailName,
                GroupLabel: label,
                DisplayText: detailName,
                DetailName: detailName,
                Content: detailContent,
                Category: info.Name,
                Aliases: [],
                Details: [],
                DetailSearch: "",
                DetailOrder: columnIndex,
                Preview: PreviewText(detailContent),
                EditUrl: EditUrl(info.Gid, rowNumber, columnIndex, columnIndex)
            }
            root.Details.Push(detail)
            root.DetailSearch .= " " detailName " " detailContent
        }

        if root.Details.Length > 0 {
            root.DisplayText := label "   ›"
            root.Preview := root.Details.Length " "
                . (root.Details.Length = 1 ? "detail" : "details")
                . (root.Preview != "" ? "  •  " root.Preview : "")
        }
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
