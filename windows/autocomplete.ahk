#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Sheet Autocomplete version 0.13.8
global AppVersion := "0.13.8"

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
global AiEngine := "ChatGPT"
global Refreshing := false
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
global VisibleChoices := []
global DetailParent := 0
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

if A_Args.Length > 0 && A_Args[1] = "--self-test"
    RunSelfTestsAndExit()

OnError HandleUnexpectedError
Initialize()

#HotIf IsChooserOpen()
Up::MoveSelection(-1)
Down::MoveSelection(1)
Enter::ChooseSelected()
*Esc::CancelChooser()
Right::OpenSelectedAction()
Left::CloseDetails()
^e::EditSelected()
^c::CopySelected()
^o::OpenSelectedLink()
^p::PreviewSelected()
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
#HotIf

#HotIf IsPreviewOpen()
*Esc::ClosePreview()
#HotIf

~LButton::ResetBoundary()
~RButton::ResetBoundary()
~MButton::ResetBoundary()

Initialize() {
    global CacheDir, RefreshIntervalMs, Trigger, SheetId
    global LauncherModifier, LauncherKey
    global Snippets, AppVersion

    DirCreate CacheDir
    A_IconTip := "Trigger Search v" AppVersion
    LoadSheetConfiguration()
    LoadCache()
    BuildChooser()
    InstallTrigger(Trigger)
    InstallLauncherHotkey(LauncherModifier, LauncherKey)
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
    global ChooserGui, SearchBox, ResultsView, FooterText

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
    ChooserGui.SetFont("s9 c666666", "Segoe UI")
    FooterText := ChooserGui.Add("Text", "xm y+6 w730 Right Hidden", "")

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
        ChooserGui.Title := "Trigger Search — " DetailParent.GroupLabel
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
    global Snippets, TargetWindow, ChooserOpen, DetailParent, RootQuery
    global ReturnParentKey, SearchBox, ChooserGui
    global Refreshing, LastRefreshError, SheetId, ActionsForChoice, FooterText

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
    ActionsForChoice := 0
    SearchBox.Enabled := true
    FooterText.Text := ""
    FooterText.Visible := false
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
        top := y + Max(40, Floor((height - 475) / 3))
        ChooserGui.Show("w760 h475 x" left " y" top)
    } catch {
        ChooserGui.Show("w760 h475 Center")
    }
}

CancelChooser(*) {
    global ChooserOpen, ChooserGui, DetailParent, RootQuery, AtBoundary
    global ActionsForChoice

    if !ChooserOpen
        return
    ActionsForChoice := 0
    ChooserGui.Hide()
    ChooserOpen := false
    DetailParent := 0
    RootQuery := ""
    AtBoundary := true
}

IsChooserOpen(*) {
    global ChooserOpen, PreviewOpen
    return ChooserOpen && !PreviewOpen
}

IsPreviewOpen(*) {
    global PreviewOpen
    return PreviewOpen
}

SearchChanged(control, info) {
    global DetailParent, RootQuery, ActionsForChoice

    if ActionsForChoice
        return

    query := control.Value
    if !DetailParent
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
    global Snippets, DetailParent

    needle := StrLower(Trim(query))
    ; Keep the root view blank until the user searches. Nested views continue
    ; to reveal their choices immediately.
    if !DetailParent && needle = ""
        return []
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
    utility := !DetailParent ? BuildUtilityChoice(query) : 0
    if utility
        choices.Push(utility)
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
    if choice.HasOwnProp("Type") && choice.Type = "action" {
        if choice.HasOwnProp("Available") && !choice.Available
            return
        PerformAction choice.ActionId
        return
    }
    if choice.HasOwnProp("IsUtilityError") && choice.IsUtilityError
        return
    PasteChoice choice
}

PasteChoice(choice) {
    global TargetWindow, ChooserGui, ChooserOpen, AtBoundary

    if choice.HasOwnProp("HasSavedContent") && !choice.HasSavedContent {
        if choice.HasOwnProp("AiPrompt") && Trim(choice.AiPrompt) != ""
            LaunchAiPrompt choice
        else
            TrayTip "No saved text or AI prompt is configured.", "Trigger Search"
        return
    }
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
    global DetailParent, RootQuery, SearchBox, ReturnParentKey

    choice := SelectedChoice()
    if !choice
        return

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

OpenSelectedLink(*) {
    global ActionsForChoice
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
    ChooserGui.Hide()
    ChooserOpen := false
    AtBoundary := true
    Run launchUrl
    return true
}

CloseDetails(*) {
    global DetailParent, SearchBox, RootQuery, ReturnParentKey
    global ResultsView, VisibleChoices

    global ActionsForChoice
    if ActionsForChoice {
        CloseActions()
        return
    }
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
    global ChooserGui, ChooserOpen, ActionsForChoice

    if ActionsForChoice {
        choice := ActionsForChoice
        ActionsForChoice := 0
        EditSelectedChoice choice
        return
    }

    choice := SelectedChoice()
    if !choice || !choice.EditUrl
        return
    ChooserGui.Hide()
    ChooserOpen := false
    Run choice.EditUrl
}

CopySelected(*) {
    global ChooserGui, ChooserOpen, AtBoundary, ActionsForChoice

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

LaunchSelectedAi(*) {
    global ActionsForChoice
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
    A_Clipboard := prompt
    ClipWait 1
    ChooserGui.Hide()
    ChooserOpen := false
    AtBoundary := true
}

ShowActionsMenu(*) {
    global ActionsForChoice, ActionsReturnQuery, ActionsReturnKey
    global SearchBox, VisibleChoices, ResultsView, FooterText, ChooserGui, AiEngine
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
    if actionId = "paste"
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

    choice := ActionsForChoice ? ActionsForChoice : SelectedChoice()
    if !choice
        return
    if ActionsForChoice
        CloseActions()
    PreviewChoice choice
}

PreviewChoice(choice) {
    global PreviewGui, PreviewOpen, ChooserGui

    if !choice || (choice.HasOwnProp("HasSavedContent")
        && !choice.HasSavedContent) || Trim(choice.Content) = "" {
        TrayTip "No saved text is available to preview.", "Trigger Search"
        return
    }

    expanded := ExpandDynamicContent(choice.Content, A_Clipboard)
    title := choice.HasOwnProp("DetailName") && choice.DetailName != ""
        ? choice.GroupLabel " — " choice.DetailName
        : (choice.HasOwnProp("GroupLabel") ? choice.GroupLabel : choice.Label)

    if IsObject(PreviewGui)
        try PreviewGui.Destroy()
    PreviewGui := Gui("+AlwaysOnTop +ToolWindow", "Preview — " title)
    PreviewGui.MarginX := 24
    PreviewGui.MarginY := 20
    PreviewGui.SetFont("s9 c777777 Bold", "Segoe UI")
    PreviewGui.Add("Text", "xm w680", "PREVIEW")
    PreviewGui.SetFont("s16 c222222 Bold", "Segoe UI")
    PreviewGui.Add("Text", "xm y+5 w680", title)
    PreviewGui.SetFont("s10 c222222 Norm", "Segoe UI")
    PreviewGui.Add("Edit", "xm y+16 w680 r24 ReadOnly", expanded.Text)
    PreviewGui.SetFont("s9 c888888", "Segoe UI")
    PreviewGui.Add("Text", "xm y+10 w680 Right", "Esc to return")
    PreviewGui.OnEvent("Close", ClosePreview)
    PreviewGui.OnEvent("Escape", ClosePreview)

    ChooserGui.Hide()
    PreviewOpen := true
    PreviewGui.Show("w728 h590 Center")
}

ClosePreview(*) {
    global PreviewGui, PreviewOpen, ChooserGui, SearchBox, ChooserOpen

    if !PreviewOpen
        return
    PreviewOpen := false
    if IsObject(PreviewGui) {
        try PreviewGui.Destroy()
        PreviewGui := 0
    }
    if ChooserOpen {
        ChooserGui.Show()
        SearchBox.Focus()
    }
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
        ApplySheets infos, csvByName
        if Snippets.Length = 0
            throw Error("No usable autocomplete rows were found. Use Label/Content headers, or one or two headerless columns.")

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
    return rows.Length > 0 && rows[1].Length >= 1 && Trim(csv) != ""
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
    Assert unfiltered.Length = 0,
        "The main chooser should remain blank until the user searches."

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

    aiParsed := []
    ParseSheet '"Label","Alias","Content","Sig"`n'
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
    Assert UrlEncode("A B") = "A%20B",
        "AI launch URLs should safely encode spaces."

    headerlessOne := []
    ParseSheet "apple`nbanana", {Name: "Quick", Gid: "123"}, headerlessOne
    Assert headerlessOne.Length = 2 && headerlessOne[1].Content = "apple",
        "A one-column headerless tab should display and paste each value."

    headerlessTwo := []
    ParseSheet "apple,red apple`nbanana,yellow banana",
        {Name: "Quick", Gid: "123"}, headerlessTwo
    Assert headerlessTwo.Length = 2 && headerlessTwo[1].Label = "apple"
        && headerlessTwo[1].Content = "red apple",
        "A two-column headerless tab should use left as Label and right as Content."

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

    Assert LooksLikeCsv("Label,Content`napple,red apple"),
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
    global LauncherModifier, LauncherKey, AiEngine
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
        }
        InstallLauncherHotkey LauncherModifier, LauncherKey
    }
}

ParseSheet(csv, info, output) {
    rows := ParseCsv(csv)
    if rows.Length = 0
        return
    columns := HeaderMap(rows[1])
    hasHeaders := columns.Has("label") || columns.Has("content")
    if !hasHeaders {
        rightmostContentColumn := 0
        for row in rows {
            for columnIndex, value in row {
                if Trim(value) != ""
                    rightmostContentColumn := Max(rightmostContentColumn, columnIndex)
            }
        }
        if rightmostContentColumn > 2 {
            OutputDebug "Trigger Search: skipped headerless tab " info.Name
                . " because it uses more than two columns.`n"
            return
        }
        columns["label"] := 1
        if rightmostContentColumn >= 2
            columns["content"] := 2
    }

    labelColumn := columns.Has("label") ? columns["label"] : 0
    contentColumn := columns.Has("content") ? columns["content"] : 0
    aliasColumn := hasHeaders && columns.Has("alias") ? columns["alias"] : 0

    firstDataRow := hasHeaders ? 2 : 1
    aiPrompts := Map()
    if hasHeaders {
        Loop rows.Length - firstDataRow + 1 {
            metadataRow := rows[firstDataRow + A_Index - 1]
            metadataLabel := labelColumn ? Trim(Cell(metadataRow, labelColumn)) : ""
            if RegExReplace(StrLower(metadataLabel), "[\s_-]+") = "aiprompt" {
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
        sheetLabel := labelColumn ? Trim(Cell(row, labelColumn)) : ""
        sheetContent := contentColumn ? Cell(row, contentColumn) : ""
        if RegExReplace(StrLower(sheetLabel), "[\s_-]+") = "aiprompt"
            continue
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
            HasSavedContent: true,
            AiPrompt: contentColumn && aiPrompts.Has(contentColumn)
                ? aiPrompts[contentColumn] : "",
            Category: info.Name,
            Aliases: aliases,
            Details: [],
            DetailSearch: "",
            DetailOrder: 0,
            Preview: MakePreview(sheetLabel, sheetContent, info.Name),
            EditUrl: EditUrl(info.Gid, rowNumber, Max(1, editColumn),
                Max(1, editColumn))
        }
        if hasHeaders {
          for columnIndex, header in rows[1] {
            detailName := Trim(StrReplace(header, Chr(0xFEFF)))
            normalizedDetailName := StrLower(detailName)
            if detailName = "" || normalizedDetailName = "label"
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
