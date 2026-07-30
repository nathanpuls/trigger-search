#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Sheet Autocomplete version 0.3.2
global AppVersion := "0.3.2"

SendMode "Input"
SetTitleMatchMode 2

; Public Google Sheet used by the Mac prototype. No OAuth or sign-in.
global SheetId := "15JTaedzH2ZfT2FAb7FduyMg37aBCHTKborM7E0y8nts"
global RefreshIntervalMs := 60000
global CacheDir := A_AppData "\SheetAutocomplete"
global ManifestPath := CacheDir "\cache.ini"
global StatePath := CacheDir "\state.ini"
global UpdateUrl := "https://api.github.com/repos/nathanpuls/sheet-autocomplete/contents/autocomplete.ahk?ref=main"

global Trigger := ";"
global TriggerHotkey := ""
global Refreshing := false
global LastRefreshError := ""
global AtBoundary := true
global LastActiveWindow := 0
global TargetWindow := 0
global ChooserOpen := false
global ActiveCategory := ""
global Categories := []
global SheetInfos := []
global Snippets := []
global VisibleChoices := []
global DetailParent := 0
global RootQuery := ""
global ReturnParentKey := ""
global KeyboardWatcher := 0

global ChooserGui := 0
global ScopeText := 0
global SearchBox := 0
global ResultsView := 0

Initialize()

#HotIf IsChooserOpen()
Up::MoveSelection(-1)
Down::MoveSelection(1)
Enter::ChooseSelected()
Esc::CancelChooser()
Right::OpenSelectedDetails()
Left::CloseDetails()
^e::EditSelected()
#HotIf

~LButton::ResetBoundary()
~RButton::ResetBoundary()
~MButton::ResetBoundary()

Initialize() {
    global CacheDir, RefreshIntervalMs, ActiveCategory, StatePath, Trigger
    global Snippets, AppVersion

    DirCreate CacheDir
    A_IconTip := "Sheet Autocomplete v" AppVersion
    ActiveCategory := IniRead(StatePath, "state", "category", "")
    LoadCache()
    BuildChooser()
    InstallTrigger(Trigger)
    StartKeyboardWatcher()

    A_TrayMenu.Add()
    A_TrayMenu.Add("Sheet Autocomplete v" AppVersion, (*) => 0)
    A_TrayMenu.Disable("Sheet Autocomplete v" AppVersion)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Open autocomplete", (*) => ShowChooser())
    A_TrayMenu.Add("Refresh snippets", RefreshData)
    A_TrayMenu.Add("Update script from GitHub", UpdateScriptFromGitHub)
    A_TrayMenu.Add("Open Google Sheet", (*) => OpenWorkbook())

    SetTimer CheckActiveWindow, 400
    SetTimer RefreshData, RefreshIntervalMs
    if Snippets.Length = 0
        RefreshData()
    else
        SetTimer RefreshData, -25
}

BuildChooser() {
    global ChooserGui, ScopeText, SearchBox, ResultsView

    ChooserGui := Gui("+AlwaysOnTop +ToolWindow", "Sheet Autocomplete")
    ChooserGui.MarginX := 14
    ChooserGui.MarginY := 12
    ChooserGui.SetFont("s10", "Segoe UI")

    ScopeText := ChooserGui.Add("Text", "xm w730 c555555", "All")
    SearchBox := ChooserGui.Add("Edit", "xm y+6 w730 h30 vQuery")
    ResultsView := ChooserGui.Add(
        "ListView",
        "xm y+8 w730 r12 -Multi NoSortHdr",
        ["Label", "Tab", "Preview"]
    )
    ResultsView.ModifyCol(1, 230)
    ResultsView.ModifyCol(2, 165)
    ResultsView.ModifyCol(3, 315)

    SearchBox.OnEvent("Change", SearchChanged)
    ResultsView.OnEvent("DoubleClick", ResultDoubleClicked)
    ChooserGui.OnEvent("Close", (*) => CancelChooser())
    ChooserGui.OnEvent("Escape", (*) => CancelChooser())

    ; Native Windows placeholder text inside the search box.
    DllCall(
        "SendMessage",
        "Ptr", SearchBox.Hwnd,
        "UInt", 0x1501,
        "Ptr", true,
        "Str", "Type to search"
    )
}

StartKeyboardWatcher() {
    global KeyboardWatcher

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

    if ChooserOpen
        return
    current := WinExist("A")
    if current && current != LastActiveWindow {
        LastActiveWindow := current
        AtBoundary := true
    }
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
    global ReturnParentKey, SearchBox, ChooserGui, ScopeText
    global Refreshing, LastRefreshError

    if Snippets.Length = 0 {
        if !Refreshing
            RefreshData()
        if Snippets.Length = 0 {
            message := Refreshing
                ? "Snippets are still loading. Try again in a few seconds."
                : (LastRefreshError != ""
                    ? "Could not load snippets: " LastRefreshError
                    : "No snippets are available. Check the public Sheet and internet connection.")
            TrayTip message, "Sheet Autocomplete"
            return
        }
    }

    TargetWindow := WinExist("A")
    ChooserOpen := true
    DetailParent := 0
    RootQuery := ""
    ReturnParentKey := ""
    ScopeText.Text := CurrentScopeLabel()
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
    global Snippets, ActiveCategory, DetailParent

    needle := StrLower(Trim(query))
    if !DetailParent && SubStr(needle, 1, 1) = "/"
        return CategoryChoices(needle)

    ranked := []
    source := DetailParent ? DetailParent.Details : Snippets

    for item in source {
        if !DetailParent && ActiveCategory != "" && item.Category != ActiveCategory
            continue

        label := StrLower(DetailParent ? item.DetailName : item.Label)
        category := StrLower(item.Category)
        content := StrLower(item.Content " " item.DetailSearch)
        aliasExact := false
        aliasPrefix := false
        aliasContains := false

        if !DetailParent {
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
        else if InStr(content, needle)
            rank := 8

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
        return aGroup < bGroup ? -1 : 1

    aCategory := StrLower(a.Item.Category)
    bCategory := StrLower(b.Item.Category)
    if aCategory != bCategory
        return aCategory < bCategory ? -1 : 1

    if a.Item.DetailOrder != b.Item.DetailOrder
        return a.Item.DetailOrder < b.Item.DetailOrder ? -1 : 1
    return StrLower(a.Item.Label) < StrLower(b.Item.Label) ? -1 : 1
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

CategoryChoices(needle) {
    global Categories

    choices := [{
        Type: "category",
        Label: "/all",
        Category: "",
        Preview: "Search all"
    }]

    for category in Categories {
        choices.Push({
            Type: "category",
            Label: "/" Slugify(category),
            Category: category,
            Preview: "Search only " category
        })
    }

    if needle = "/"
        return choices

    filtered := []
    for choice in choices {
        if InStr(StrLower(choice.Label), needle)
            filtered.Push(choice)
    }
    return filtered
}

Slugify(value) {
    return RegExReplace(StrLower(Trim(value)), "\s+", "-")
}

RenderChoices(choices) {
    global ResultsView, VisibleChoices

    VisibleChoices := choices
    ResultsView.Opt("-Redraw")
    ResultsView.Delete()

    for choice in choices {
        if choice.HasOwnProp("Type") && choice.Type = "category" {
            ResultsView.Add("", choice.Label, "", choice.Preview)
        } else {
            label := choice.HasOwnProp("DisplayText") ? choice.DisplayText : choice.Label
            ResultsView.Add("", label, choice.Category, choice.Preview)
        }
    }

    ResultsView.Opt("+Redraw")
    if choices.Length > 0
        ResultsView.Modify(1, "Select Focus Vis")
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
    global ActiveCategory, DetailParent, RootQuery, ScopeText, SearchBox
    global ChooserGui, ChooserOpen, StatePath

    if choice.HasOwnProp("Type") && choice.Type = "category" {
        ActiveCategory := choice.Category
        IniWrite ActiveCategory, StatePath, "state", "category"
        DetailParent := 0
        RootQuery := ""
        ScopeText.Text := CurrentScopeLabel()
        SearchBox.Value := ""
        RenderChoices(FilterChoices(""))
        SearchBox.Focus()
        return
    }

    PasteChoice choice
}

PasteChoice(choice) {
    global TargetWindow, ChooserGui, ChooserOpen, AtBoundary

    savedClipboard := ClipboardAll()
    ChooserGui.Hide()
    ChooserOpen := false
    A_Clipboard := choice.Content
    if !ClipWait(1) {
        A_Clipboard := savedClipboard
        return
    }

    if TargetWindow
        WinActivate "ahk_id " TargetWindow
    Sleep 80
    Send "^v"
    Sleep 250
    A_Clipboard := savedClipboard
    AtBoundary := RegExMatch(choice.Content, "\s$") != 0
}

OpenSelectedDetails(*) {
    global DetailParent, RootQuery, SearchBox, ScopeText, ReturnParentKey

    if DetailParent
        return
    choice := SelectedChoice()
    if !choice || !choice.HasOwnProp("Details") || choice.Details.Length = 0
        return

    RootQuery := SearchBox.Value
    ReturnParentKey := choice.Key
    DetailParent := choice
    ScopeText.Text := "←  " choice.GroupLabel " details"
    SearchBox.Value := ""
    RenderChoices(FilterChoices(""))
    SearchBox.Focus()
}

CloseDetails(*) {
    global DetailParent, SearchBox, ScopeText, RootQuery, ReturnParentKey
    global ResultsView, VisibleChoices

    if !DetailParent
        return
    DetailParent := 0
    ScopeText.Text := CurrentScopeLabel()
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

CurrentScopeLabel() {
    global ActiveCategory
    return ActiveCategory = "" ? "All" : ActiveCategory
}

OpenWorkbook() {
    global SheetId
    Run "https://docs.google.com/spreadsheets/d/" SheetId "/edit"
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
            TrayTip "You already have the newest version.", "Sheet Autocomplete"
            return
        }

        if FileExist(backup)
            FileDelete backup
        FileCopy A_ScriptFullPath, backup, 1
        WriteTextAtomic A_ScriptFullPath, replacement
        TrayTip "Update installed. Reloading now...", "Sheet Autocomplete"
        Sleep 500
        Reload
    } catch as problem {
        TrayTip "Update failed: " problem.Message, "Sheet Autocomplete"
    }
}

FetchLiveGitHubFile(url) {
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.Open("GET", url, false)
    request.SetRequestHeader("Accept", "application/vnd.github.raw+json")
    request.SetRequestHeader("User-Agent", "SheetAutocomplete")
    request.SetRequestHeader("Cache-Control", "no-cache")
    request.Send()

    if request.Status != 200
        throw Error("GitHub returned HTTP " request.Status ".")
    return request.ResponseText
}

RefreshData(*) {
    global Refreshing, SheetId, SheetInfos, LastRefreshError
    global CacheDir, Snippets

    if Refreshing
        return
    Refreshing := true

    try {
        cacheBust := A_NowUTC A_MSec
        htmlUrl := "https://docs.google.com/spreadsheets/d/" SheetId
            . "/htmlview?cacheBust=" cacheBust
        html := FetchText(htmlUrl)
        infos := DiscoverSheets(html)
        if infos.Length = 0
            throw Error("No visible tabs were found.")

        csvByName := Map()
        for info in infos {
            csvUrl := "https://docs.google.com/spreadsheets/d/" SheetId
                . "/gviz/tq?tqx=out:csv&gid=" info.Gid
                . "&cacheBust=" cacheBust
            csv := FetchText(csvUrl)
            if SubStr(LTrim(csv), 1, 1) != Chr(34)
                throw Error("Invalid CSV response for " info.Name)
            csvByName[info.Name] := csv
        }

        ApplySheets infos, csvByName
        SaveCache infos, csvByName
        SheetInfos := infos
        LastRefreshError := ""
    } catch as problem {
        ; Offline use is expected: keep the last successful in-memory/cache copy.
        LastRefreshError := problem.Message
        OutputDebug "Sheet Autocomplete refresh failed: " problem.Message "`n"
        WriteTextAtomic CacheDir "\last-error.txt", problem.Message
        if Snippets.Length = 0
            TrayTip "Could not load snippets: " problem.Message, "Sheet Autocomplete"
    } finally {
        Refreshing := false
    }
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
    global Categories, Snippets, ActiveCategory, StatePath

    ApplySettings infos, csvByName
    categories := []
    parsed := []

    for info in infos {
        if IsAdministrativeSheet(info.Name)
            continue
        if !csvByName.Has(info.Name)
            continue
        categories.Push(info.Name)
        ParseSheet csvByName[info.Name], info, parsed
    }

    InsertionSort parsed, CompareSnippets
    Categories := categories
    Snippets := parsed

    if ActiveCategory != "" && !ArrayContains(Categories, ActiveCategory) {
        ActiveCategory := ""
        IniWrite "", StatePath, "state", "category"
    }
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
    baseEndColumn := Max(labelColumn, contentColumn, aliasColumn)

    Loop rows.Length - 1 {
        rowNumber := A_Index + 1
        row := rows[rowNumber]
        sheetLabel := labelColumn ? Trim(Cell(row, labelColumn)) : ""
        sheetContent := contentColumn ? Cell(row, contentColumn) : ""
        label := sheetLabel != "" ? sheetLabel : Trim(sheetContent)
        if label = ""
            continue
        content := Trim(sheetContent) != "" ? sheetContent : label

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
            EditUrl: EditUrl(info.Gid, rowNumber, 1, Max(1, baseEndColumn))
        }

        for columnIndex, header in rows[1] {
            detailName := Trim(StrReplace(header, Chr(0xFEFF)))
            if detailName = "" || columnIndex = labelColumn
                || columnIndex = contentColumn || columnIndex = aliasColumn
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
        return aLabel < bLabel ? -1 : 1
    aCategory := StrLower(a.Category)
    bCategory := StrLower(b.Category)
    return aCategory < bCategory ? -1 : (aCategory > bCategory ? 1 : 0)
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

ArrayContains(items, target) {
    for item in items {
        if item = target
            return true
    }
    return false
}

SaveCache(infos, csvByName) {
    global CacheDir, ManifestPath, Trigger

    manifest := "[cache]`ncount=" infos.Length "`ntrigger=" Trigger "`n"
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
    global ManifestPath, Trigger, SheetInfos

    if !FileExist(ManifestPath)
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
