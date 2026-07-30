local M = {}

local chooser
local keyWatcher
local editHotkey
local openDetailsHotkey
local backHotkey
local mouseWatcher
local appWatcher
local refreshTimer
local refresh
local rankedSnippets
local refreshInProgress = false
local snippets = {}
local atBoundary = true
local previousApp
local discoveredSheetNames
local detailParent
local rootQuery = ""
local returnParentCategory
local returnParentRow

local config = {
  sheetId = "",
  sheetNames = { "Personal", "Psychiatric Medications" },
  sheetGids = {},
  trigger = ";",
  cachePath = hs.configdir .. "/autocomplete-snippets-cache.json",
  refreshInterval = 60,
  rows = 10,
  width = 42,
}

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isAdministrativeSheet(name)
  local normalized = trim(name):lower():gsub("[%s_&%-]+", "")
  return normalized == "settings" or normalized == "settingshelp"
    or normalized == "readme" or normalized == "template"
    or normalized == "blanktemplate" or normalized == "autohotkey"
    or normalized == "windowssetup"
end

local function csvRows(csv)
  csv = csv:gsub("\r\n", "\n")
  local rows, row, field = {}, {}, {}
  local i, quoted = 1, false

  local function finishField()
    row[#row + 1] = table.concat(field)
    field = {}
  end

  local function finishRow()
    finishField()
    rows[#rows + 1] = row
    row = {}
  end

  while i <= #csv do
    local char = csv:sub(i, i)

    if quoted then
      if char == '"' and csv:sub(i + 1, i + 1) == '"' then
        field[#field + 1] = '"'
        i = i + 1
      elseif char == '"' then
        quoted = false
      else
        field[#field + 1] = char
      end
    elseif char == '"' and #field == 0 then
      quoted = true
    elseif char == "," then
      finishField()
    elseif char == "\n" then
      finishRow()
    elseif char ~= "\r" then
      field[#field + 1] = char
    end

    i = i + 1
  end

  if #field > 0 or #row > 0 then
    finishRow()
  end

  return rows
end

local function looksLikeCsv(csv)
  if type(csv) ~= "string" or trim(csv):sub(1, 1) == "<" then return false end
  local ok, rows = pcall(csvRows, csv)
  return ok and type(rows) == "table" and #rows > 0 and #rows[1] >= 2
end

local function configuredSheetNames()
  local source
  if type(discoveredSheetNames) == "table" and #discoveredSheetNames > 0 then
    source = discoveredSheetNames
  elseif type(config.sheetNames) == "table" and #config.sheetNames > 0 then
    source = config.sheetNames
  elseif config.sheetName and config.sheetName ~= "" then
    source = { config.sheetName }
  else
    source = {}
  end

  local visible = {}
  for _, name in ipairs(source) do
    if not isAdministrativeSheet(name) then visible[#visible + 1] = name end
  end
  return visible
end

local function decodeJavascriptString(value)
  value = value:gsub("\\x(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  local ok, decoded = pcall(hs.json.decode, '"' .. value .. '"')
  if ok and type(decoded) == "string" then return decoded end
  return value:gsub('\\"', '"'):gsub("\\\\", "\\")
end

local function discoverSheets(html)
  local names, gids, seen = {}, {}, {}
  for encodedName, gid in html:gmatch(
      'items%.push%(%{name:%s*"(.-)".-gid:%s*"([%-0-9]+)"') do
    local name = decodeJavascriptString(encodedName)
    if name ~= "" and not seen[name] then
      names[#names + 1] = name
      gids[name] = tonumber(gid) or gid
      seen[name] = true
    end
  end
  if #names == 0 then return nil, "no visible tabs found" end
  return names, gids
end

local function columnLetter(columnIndex)
  local result = ""
  local value = columnIndex
  while value > 0 do
    local remainder = (value - 1) % 26
    result = string.char(65 + remainder) .. result
    value = math.floor((value - 1) / 26)
  end
  return result
end

local function parseSheet(csv, category)
  local rows = csvRows(csv)
  if #rows == 0 then return nil, "the CSV is empty" end

  local function addSnippet(parsed, sheetLabel, sheetContent, rowIndex,
      detailName, detailColumnIndex, baseEndColumnIndex)
    local label = sheetLabel ~= "" and sheetLabel or trim(sheetContent)
    if label == "" then return end

    local hasContent = trim(sheetContent) ~= ""
    if detailName and not hasContent then return end
    local content = hasContent and sheetContent or label
    local preview = sheetContent:gsub("%s+", " ")
    if #preview > 90 then preview = preview:sub(1, 87) .. "..." end
    local displayText = detailName or label
    local searchLabel = detailName and (label .. " " .. detailName) or label
    local subText = detailName and (category .. "  •  " .. label) or category
    if detailName and preview ~= "" then
      subText = subText .. "  •  " .. preview
    elseif sheetLabel ~= "" and hasContent
        and preview:lower() ~= label:lower() then
      subText = category .. "  •  " .. preview
    end

    local sheetGid = type(config.sheetGids) == "table"
      and config.sheetGids[category] or nil
    local editUrl
    if sheetGid ~= nil then
      local editRange = "A" .. tostring(rowIndex) .. ":B" .. tostring(rowIndex)
      if detailColumnIndex then
        editRange = columnLetter(detailColumnIndex) .. tostring(rowIndex)
      elseif baseEndColumnIndex and baseEndColumnIndex > 2 then
        editRange = "A" .. tostring(rowIndex) .. ":"
          .. columnLetter(baseEndColumnIndex) .. tostring(rowIndex)
      end
      editUrl = "https://docs.google.com/spreadsheets/d/"
        .. config.sheetId .. "/edit#gid=" .. tostring(sheetGid)
        .. "&range=" .. editRange
      subText = subText .. "  •  ⌘E to edit"
    end

    parsed[#parsed + 1] = {
      text = displayText,
      subText = subText,
      label = searchLabel,
      groupLabel = label,
      detailOrder = detailColumnIndex or 0,
      detailName = detailName,
      isDetail = detailName ~= nil,
      rowIndex = rowIndex,
      category = category,
      content = content,
      editUrl = editUrl,
    }
  end

  local columns = {}
  for index, name in ipairs(rows[1]) do
    local normalizedName = trim(name):gsub("^\239\187\191", ""):lower()
    columns[normalizedName] = index
  end

  if not columns.label and not columns.content then
    return nil, 'every tab must have a "Label" or "Content" column'
  end
  if not columns.label or not columns.content then
    print('Mac autocomplete: "' .. category
      .. '" is missing Label or Content; using the column that remains')
  end

  local parsed = {}
  for rowIndex = 2, #rows do
    local row = rows[rowIndex]
    local sheetLabel = columns.label and trim(row[columns.label] or "") or ""
    local sheetContent = columns.content and (row[columns.content] or "") or ""
    local aliasText = columns.alias and trim(row[columns.alias]) or ""
    local baseEndColumnIndex = math.max(columns.label or 0, columns.content or 0,
      columns.alias or 0)
    local rootIndex = #parsed + 1
    addSnippet(parsed, sheetLabel, sheetContent, rowIndex, nil, nil,
      baseEndColumnIndex)

    local parentLabel = sheetLabel ~= "" and sheetLabel or trim(sheetContent)
    if parentLabel ~= "" then
      for columnIndex, header in ipairs(rows[1]) do
        local detailName = trim(header):gsub("^\239\187\191", "")
        if columnIndex ~= columns.label and columnIndex ~= columns.content
            and columnIndex ~= columns.alias
            and detailName ~= "" then
          addSnippet(parsed, parentLabel, row[columnIndex] or "", rowIndex,
            detailName, columnIndex)
        end
      end
    end

    local root = parsed[rootIndex]
    if root and not root.isDetail then
      root.aliases = {}
      for alias in aliasText:gmatch("[^,;|\n]+") do
        alias = trim(alias):lower()
        if alias ~= "" then root.aliases[#root.aliases + 1] = alias end
      end
      local detailCount = #parsed - rootIndex
      root.detailCount = detailCount
      if detailCount > 0 then
        local detailWords = {}
        for index = rootIndex + 1, #parsed do
          detailWords[#detailWords + 1] = parsed[index].label
          detailWords[#detailWords + 1] = parsed[index].content
        end
        root.detailSearch = table.concat(detailWords, " ")
        root.text = root.text .. "   ›"
        local noun = detailCount == 1 and "detail" or "details"
        root.subText = root.subText .. "  •  " .. tostring(detailCount)
          .. " " .. noun
      end
    end
  end

  return parsed
end

local function parseSheets(sheetCsvs)
  local parsed = {}
  for _, category in ipairs(configuredSheetNames()) do
    local csv = sheetCsvs[category]
    if not csv then return nil, 'missing response for tab "' .. category .. '"' end

    local categorySnippets, errorMessage = parseSheet(csv, category)
    if not categorySnippets then
      print('Mac autocomplete: skipped tab "' .. category .. '": ' .. errorMessage)
    else
      for _, snippet in ipairs(categorySnippets) do parsed[#parsed + 1] = snippet end
    end
  end

  table.sort(parsed, function(a, b)
    if a.groupLabel:lower() ~= b.groupLabel:lower() then
      return a.groupLabel:lower() < b.groupLabel:lower()
    end
    if a.category:lower() ~= b.category:lower() then
      return a.category:lower() < b.category:lower()
    end
    if a.detailOrder ~= b.detailOrder then return a.detailOrder < b.detailOrder end
    return a.label:lower() < b.label:lower()
  end)
  return parsed
end

local function applySheetSettings(sheetCsvs)
  for sheetName, csv in pairs(sheetCsvs or {}) do
    local normalizedSheetName = trim(sheetName):lower():gsub("[%s_&%-]+", "")
    if normalizedSheetName == "settings"
        or normalizedSheetName == "settingshelp" then
      local rows = csvRows(csv)
      if #rows > 0 then
        local settingColumn, valueColumn
        for columnIndex, header in ipairs(rows[1]) do
          local normalized = trim(header):lower()
          if normalized == "setting" then settingColumn = columnIndex end
          if normalized == "value" then valueColumn = columnIndex end
        end
        if settingColumn and valueColumn then
          for rowIndex = 2, #rows do
            local key = trim(rows[rowIndex][settingColumn]):lower()
              :gsub("[%s_%-]+", "")
            local value = trim(rows[rowIndex][valueColumn])
            if key == "trigger" and value ~= "" then config.trigger = value end
          end
        else
          print('Mac autocomplete: Settings needs "Setting" and "Value" columns')
        end
      end
    end
  end
end

local function readFile(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  return contents
end

local function writeFile(path, contents)
  local file, errorMessage = io.open(path, "w")
  if not file then return false, errorMessage end
  file:write(contents)
  file:close()
  return true
end

local function installSheets(sheetCsvs, source)
  applySheetSettings(sheetCsvs)
  local parsed, errorMessage = parseSheets(sheetCsvs)
  if not parsed then
    print("Mac autocomplete: ignored " .. source .. ": " .. errorMessage)
    return false
  end

  snippets = parsed
  if chooser then chooser:choices(rankedSnippets(chooser:query() or "")) end
  print(string.format("Mac autocomplete: loaded %d snippets from %s", #snippets, source))
  return true
end

rankedSnippets = function(query)
  local needle = trim(query):lower()

  local matches = {}
  for _, snippet in ipairs(snippets) do
    local inCurrentView
    if detailParent then
      inCurrentView = snippet.isDetail
        and snippet.category == detailParent.category
        and snippet.rowIndex == detailParent.rowIndex
    else
      inCurrentView = not snippet.isDetail
    end

    local label = (detailParent and snippet.detailName or snippet.label):lower()
    local category = snippet.category:lower()
    local directContent = snippet.content:lower()
    local nestedContent = (snippet.detailSearch or ""):lower()
    local aliasExact, aliasPrefix, aliasContains = false, false, false
    if not detailParent then
      for _, alias in ipairs(snippet.aliases or {}) do
        if alias == needle then aliasExact = true end
        if alias:sub(1, #needle) == needle then aliasPrefix = true end
        if alias:find(needle, 1, true) then aliasContains = true end
      end
    end
    local rank

    if not inCurrentView then
      rank = nil
    elseif needle == "" then
      rank = 0
    elseif aliasExact then
      rank = 0
    elseif label == needle then
      rank = 1
    elseif aliasPrefix then
      rank = 2
    elseif label:sub(1, #needle) == needle then
      rank = 3
    elseif aliasContains then
      rank = 4
    elseif label:find(needle, 1, true) then
      rank = 5
    elseif not detailParent and category:sub(1, #needle) == needle then
      rank = 6
    elseif not detailParent and category:find(needle, 1, true) then
      rank = 7
    elseif directContent:find(needle, 1, true) then
      rank = 8
    elseif not detailParent and nestedContent:find(needle, 1, true) then
      rank = 9
    end

    if rank ~= nil then
      matches[#matches + 1] = { choice = snippet, rank = rank }
    end
  end

  table.sort(matches, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.choice.groupLabel:lower() ~= b.choice.groupLabel:lower() then
      return a.choice.groupLabel:lower() < b.choice.groupLabel:lower()
    end
    if a.choice.category:lower() ~= b.choice.category:lower() then
      return a.choice.category:lower() < b.choice.category:lower()
    end
    if a.choice.detailOrder ~= b.choice.detailOrder then
      return a.choice.detailOrder < b.choice.detailOrder
    end
    return a.choice.label:lower() < b.choice.label:lower()
  end)

  local choices = {}
  for _, match in ipairs(matches) do choices[#choices + 1] = match.choice end
  return choices
end

local function updateChooserHotkeys()
  local visible = chooser and chooser:isVisible()
  if editHotkey then
    if visible then editHotkey:enable() else editHotkey:disable() end
  end
  if openDetailsHotkey then
    if visible and not detailParent then
      openDetailsHotkey:enable()
    else
      openDetailsHotkey:disable()
    end
  end
  if backHotkey then
    if visible and detailParent then
      backHotkey:enable()
    else
      backHotkey:disable()
    end
  end
end

local function rootPlaceholder()
  return "⌕"
end

local function openDetails(choice)
  if not choice or choice.isDetail or not choice.detailCount
      or choice.detailCount == 0 then return end
  rootQuery = chooser:query() or rootQuery
  returnParentCategory = choice.category
  returnParentRow = choice.rowIndex
  detailParent = choice
  chooser:placeholderText("←  " .. choice.groupLabel .. " details")
  chooser:query("")
  chooser:choices(rankedSnippets(""))
  updateChooserHotkeys()
end

local function closeDetails()
  if not detailParent then return end
  detailParent = nil
  chooser:placeholderText(rootPlaceholder())
  chooser:query(rootQuery)
  local choices = rankedSnippets(rootQuery)
  chooser:choices(choices)
  for index, choice in ipairs(choices) do
    if not choice.isDetail and choice.category == returnParentCategory
        and choice.rowIndex == returnParentRow then
      chooser:selectedRow(index)
      break
    end
  end
  updateChooserHotkeys()
end

local function pasteSnippet(choice)
  if not choice then return end
  local oldClipboard = hs.pasteboard.getContents()
  hs.pasteboard.setContents(choice.content)

  local targetApp = previousApp
  if targetApp then targetApp:activate() end

  hs.timer.doAfter(0.08, function()
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    atBoundary = choice.content:match("%s$") ~= nil
  end)

  hs.timer.doAfter(0.8, function()
    if hs.pasteboard.getContents() == choice.content then
      if oldClipboard == nil then
        hs.pasteboard.clearContents()
      else
        hs.pasteboard.setContents(oldClipboard)
      end
    end
  end)
end

local function editSnippet(choice)
  if not choice or not choice.editUrl then return end
  chooser:hide()
  hs.urlevent.openURL(choice.editUrl)
end

local function showChooser()
  if #snippets == 0 then
    hs.alert.show("Autocomplete: no snippets loaded")
    return
  end

  previousApp = hs.application.frontmostApplication()
  detailParent = nil
  rootQuery = ""
  returnParentCategory = nil
  returnParentRow = nil
  chooser:placeholderText(rootPlaceholder())
  chooser:query("")
  chooser:choices(rankedSnippets(""))
  chooser:show()
  refresh()
end

local function hasCommandModifier(flags)
  return flags.cmd or flags.ctrl or flags.alt or flags.fn
end

-- Ask the focused text control what is immediately before the cursor. This
-- fixes boundary detection after mouse clicks and cursor movement. Some apps
-- do not expose text through Accessibility, so nil means "use key tracking."
local function focusedTextBoundary()
  local ok, result = pcall(function()
    local focused = hs.axuielement.systemWideElement()
      :attributeValue("AXFocusedUIElement")
    if not focused then return nil end

    local selectedRange = focused:attributeValue("AXSelectedTextRange")
    if type(selectedRange) ~= "table" or type(selectedRange.location) ~= "number" then
      return nil
    end

    if selectedRange.location == 0 then return true end

    local previousCharacter = focused:parameterizedAttributeValue(
      "AXStringForRange",
      { location = selectedRange.location - 1, length = 1 }
    )
    if type(previousCharacter) ~= "string" or previousCharacter == "" then
      return nil
    end

    return previousCharacter:match("%s") ~= nil
  end)

  if not ok then return nil end
  return result
end

local boundaryKeyCodes = {
  [hs.keycodes.map.space] = true,
  [hs.keycodes.map.tab] = true,
  [hs.keycodes.map["return"]] = true,
  [hs.keycodes.map.padenter] = true,
}

local uncertainKeyCodes = {
  [hs.keycodes.map.left] = true,
  [hs.keycodes.map.right] = true,
  [hs.keycodes.map.up] = true,
  [hs.keycodes.map.down] = true,
  [hs.keycodes.map.home] = true,
  [hs.keycodes.map["end"]] = true,
  [hs.keycodes.map.pageup] = true,
  [hs.keycodes.map.pagedown] = true,
  [hs.keycodes.map.escape] = true,
}

local function watchKey(event)
  local flags = event:getFlags()
  local typedCharacter = event:getCharacters()

  if chooser and chooser:isVisible() then
    return false
  end

  if hasCommandModifier(flags) then
    atBoundary = false
    return false
  end

  local keyCode = event:getKeyCode()
  local character = typedCharacter

  if character == config.trigger then
    local actualBoundary = focusedTextBoundary()
    local shouldOpen = actualBoundary
    if shouldOpen == nil then shouldOpen = atBoundary end

    if shouldOpen then
      atBoundary = true
      showChooser()
      return true
    end

    atBoundary = false
    return false
  end

  if boundaryKeyCodes[keyCode] then
    atBoundary = true
  elseif uncertainKeyCodes[keyCode] then
    atBoundary = false
  elseif character and character ~= "" then
    atBoundary = character:match("%s") ~= nil
  elseif keyCode == hs.keycodes.map.delete or keyCode == hs.keycodes.map.forwarddelete then
    atBoundary = false
  end

  return false
end

local function encodeQueryValue(value)
  return hs.http.encodeForQuery(tostring(value))
end

refresh = function()
  if config.sheetId == "" or config.sheetId == "PASTE_YOUR_SHEET_ID_HERE" then
    hs.alert.show("Autocomplete: add your Google Sheet ID")
    return
  end

  if refreshInProgress then return end
  refreshInProgress = true

  local function fetchSheetCsvs(sheetNames)
    if #sheetNames == 0 then
      refreshInProgress = false
      hs.alert.show("Autocomplete: no visible Sheet tabs found")
      return
    end

    local responses, remaining, failed = {}, #sheetNames, false

    local function finishSheet(category, body, errorMessage)
      if body then
        responses[category] = body
      else
        failed = true
        print("Mac autocomplete: " .. category .. " refresh failed: "
          .. tostring(errorMessage))
      end

      remaining = remaining - 1
      if remaining == 0 then
        refreshInProgress = false
        if not failed and installSheets(responses, "Google Sheets") then
          local cacheJson = hs.json.encode({
            sheets = responses,
            sheetNames = sheetNames,
            sheetGids = config.sheetGids,
          })
          local ok, cacheError = writeFile(config.cachePath, cacheJson)
          if not ok then
            print("Mac autocomplete: could not write cache: "
              .. tostring(cacheError))
          end
        end
      end
    end

    for _, sheetName in ipairs(sheetNames) do
      local category = sheetName
      local baseUrl = "https://docs.google.com/spreadsheets/d/"
        .. encodeQueryValue(config.sheetId)
      local gvizUrl = baseUrl .. "/gviz/tq?tqx=out:csv&sheet="
        .. encodeQueryValue(category)
        .. "&cacheBust=" .. tostring(os.time())
      local gid = type(config.sheetGids) == "table"
        and config.sheetGids[category] or nil
      local exportUrl = gid and (baseUrl .. "/export?format=csv&gid="
        .. encodeQueryValue(gid) .. "&cacheBust=" .. tostring(os.time())) or nil

      local function requestCsv(url, fallbackUrl)
        hs.http.asyncGet(url, nil, function(status, body)
          if status == 200 and looksLikeCsv(body) then
            finishSheet(category, body, nil)
          elseif fallbackUrl then
            requestCsv(fallbackUrl, nil)
          else
            finishSheet(category, nil, "HTTP " .. tostring(status)
              .. (status == 200 and " returned invalid CSV" or ""))
          end
        end)
      end

      requestCsv(exportUrl or gvizUrl, exportUrl and gvizUrl or nil)
    end
  end

  local metadataUrl = "https://docs.google.com/spreadsheets/d/"
    .. encodeQueryValue(config.sheetId)
    .. "/htmlview?cacheBust=" .. tostring(os.time())
  hs.http.asyncGet(metadataUrl, nil, function(status, body)
    if status == 200 then
      local names, gids = discoverSheets(body)
      if names then
        discoveredSheetNames = names
        for name, gid in pairs(gids) do config.sheetGids[name] = gid end
        fetchSheetCsvs(names)
        return
      end
      print("Mac autocomplete: could not discover tabs: " .. tostring(gids))
    else
      print("Mac autocomplete: tab discovery failed with HTTP " .. tostring(status))
    end
    fetchSheetCsvs(configuredSheetNames())
  end)
end

function M.start(userConfig)
  if keyWatcher then M.stop() end
  for key, value in pairs(userConfig or {}) do config[key] = value end
  discoveredSheetNames = nil

  chooser = hs.chooser.new(pasteSnippet)
    :placeholderText(rootPlaceholder())
    :searchSubText(true)
    :rows(config.rows)
    :width(config.width)
    :queryChangedCallback(function(query)
      if not detailParent then rootQuery = query end
      chooser:choices(rankedSnippets(query))
    end)
    :showCallback(function()
      updateChooserHotkeys()
    end)
    :hideCallback(function()
      updateChooserHotkeys()
    end)

  editHotkey = hs.hotkey.new({ "cmd" }, "e", function()
    if chooser and chooser:isVisible() then
      editSnippet(chooser:selectedRowContents())
    end
  end)

  openDetailsHotkey = hs.hotkey.new({}, "right", function()
    if chooser and chooser:isVisible() then
      openDetails(chooser:selectedRowContents())
    end
  end)

  backHotkey = hs.hotkey.new({}, "left", function()
    if chooser and chooser:isVisible() then closeDetails() end
  end)

  local cachedJson = readFile(config.cachePath)
  if cachedJson then
    local ok, cachedData = pcall(hs.json.decode, cachedJson)
    if ok and type(cachedData) == "table" then
      local cachedSheets = cachedData
      if type(cachedData.sheets) == "table" then
        cachedSheets = cachedData.sheets
        if type(cachedData.sheetNames) == "table" then
          discoveredSheetNames = cachedData.sheetNames
        end
        if type(cachedData.sheetGids) == "table" then
          for name, gid in pairs(cachedData.sheetGids) do
            config.sheetGids[name] = gid
          end
        end
      end
      installSheets(cachedSheets, "local cache")
    end
  end
  keyWatcher = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, watchKey):start()
  mouseWatcher = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.rightMouseDown,
    hs.eventtap.event.types.otherMouseDown,
  }, function()
    -- Web editors such as Gmail often update their focused Accessibility
    -- element just after the click. Re-check once focus settles; if the app
    -- exposes no cursor context, treat the click as a new typing run.
    hs.timer.doAfter(0.05, function()
      local actualBoundary = focusedTextBoundary()
      atBoundary = actualBoundary == nil and true or actualBoundary
    end)
    return false
  end):start()

  appWatcher = hs.application.watcher.new(function(_, eventType)
    if eventType == hs.application.watcher.activated then atBoundary = true end
  end):start()

  if type(config.refreshInterval) == "number" and config.refreshInterval > 0 then
    refreshTimer = hs.timer.doEvery(config.refreshInterval, refresh)
  end

  refresh()
  return M
end

function M.refresh()
  refresh()
end

function M.stop()
  if keyWatcher then keyWatcher:stop(); keyWatcher = nil end
  if editHotkey then editHotkey:disable(); editHotkey:delete(); editHotkey = nil end
  if openDetailsHotkey then
    openDetailsHotkey:disable(); openDetailsHotkey:delete(); openDetailsHotkey = nil
  end
  if backHotkey then backHotkey:disable(); backHotkey:delete(); backHotkey = nil end
  if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
  if mouseWatcher then mouseWatcher:stop(); mouseWatcher = nil end
  if appWatcher then appWatcher:stop(); appWatcher = nil end
  if chooser then chooser:delete(); chooser = nil end
end

return M
