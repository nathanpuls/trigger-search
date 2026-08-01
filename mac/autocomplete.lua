local M = {}

local chooser
local keyWatcher
local editHotkey
local copyHotkey
local aiHotkey
local actionsHotkey
local openDetailsHotkey
local openLinkHotkey
local backHotkey
local escapeHotkey
local launcherHotkey
local actionChooser
local actionChoice
local actionReturnQuery = ""
local actionReturnRow = 1
local actionReturning = false
local bulletChoiceImage
local hollowChoiceImage
local settingsMenu
local mouseWatcher
local appWatcher
local refreshTimer
local refresh
local promptForGoogleSheet
local rankedSnippets
local showChooser
local updateLauncherHotkey
local showActions
local launchAiPrompt
local refreshInProgress = false
local snippets = {}
local atBoundary = true
local previousApp
local discoveredSheetNames
local newSnippetTargets = {}
local detailParent
local rootQuery = ""
local returnParentCategory
local returnParentRow
local sheetSettingKey = "triggerSearchSheetId"

local config = {
  sheetId = "",
  sheetNames = {},
  sheetGids = {},
  trigger = ";",
  launcherModifier = "None",
  launcherKey = "None",
  aiEngine = "ChatGPT",
  cachePath = hs.configdir .. "/autocomplete-snippets-cache.json",
  refreshInterval = 60,
  rows = 10,
  width = 42,
}

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function nestedDisplayText(label)
  local display = label .. "   →"
  local styled = hs.styledtext.new(display, {
    font = hs.styledtext.defaultFonts.system,
    color = { white = 0.15, alpha = 1 },
  })
  return styled:setStyle({
    font = { name = ".AppleSystemUIFont", size = 17 },
  }, -1, -1)
end

local function stripUrlPunctuation(value)
  return (value:gsub("[%)%]%}%.,;:!?]+$", ""))
end

local function extractLaunchUrl(value)
  local text = tostring(value or "")
  local candidates, seen = {}, {}

  local function add(candidate, needsProtocol)
    candidate = stripUrlPunctuation(candidate)
    if candidate == "" then return end
    local normalized = needsProtocol and ("https://" .. candidate) or candidate
    if not seen[normalized] then
      candidates[#candidates + 1] = normalized
      seen[normalized] = true
    end
  end

  for candidate in text:gmatch("https?://[^%s<>\"']+") do add(candidate, false) end
  local position = 1
  local pattern = "[%w%-]+%.[%a][%a]+[%w%-%._~:/%?#%[%]@!$&'()*+,;=%%]*"
  while true do
    local startAt, endAt = text:find(pattern, position)
    if not startAt then break end
    local previous = startAt > 1 and text:sub(startAt - 1, startAt - 1) or ""
    if previous ~= "@" and not previous:match("[%w_]") then
      add(text:sub(startAt, endAt), true)
    end
    position = endAt + 1
  end

  return #candidates == 1 and candidates[1] or nil
end

local function extractStandaloneLaunchUrl(value)
  local original = trim(value)
  local launchUrl = extractLaunchUrl(original)
  if not launchUrl then return nil end
  if original == launchUrl or "https://" .. original == launchUrl then
    return launchUrl
  end
  return nil
end

local function extractSheetId(value)
  value = trim(value)
  local sheetId = value:match("/spreadsheets/d/([%w_%-]+)")
  if sheetId then return sheetId end
  if value:match("^[%w_%-]+$") and #value >= 20 then return value end
  return nil
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
  return ok and type(rows) == "table" and #rows > 0 and #rows[1] >= 1
    and trim(csv) ~= ""
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

local function newSnippetTarget(csv)
  local rows = csvRows(csv)
  if #rows == 0 then return "A2" end

  local entryColumn = 1
  for columnIndex, header in ipairs(rows[1]) do
    if trim(header):lower():gsub("^\239\187\191", "") == "label" then
      entryColumn = columnIndex
      break
    end
  end

  local lastOccupiedRow = 1
  for rowIndex, row in ipairs(rows) do
    for _, value in ipairs(row) do
      if trim(value) ~= "" then
        lastOccupiedRow = rowIndex
        break
      end
    end
  end

  return columnLetter(entryColumn) .. tostring(math.max(2, lastOccupiedRow + 1))
end

local monthNames = {
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
}

local monthNamesShort = {
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

local weekdayNames = {
  "Sunday", "Monday", "Tuesday", "Wednesday",
  "Thursday", "Friday", "Saturday",
}

local weekdayNamesShort = {
  "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
}

local function daysInMonth(year, month)
  return os.date("*t", os.time({
    year = year,
    month = month + 1,
    day = 0,
    hour = 12,
  })).day
end

local function addCalendarMonths(timestamp, amount)
  local parts = os.date("*t", timestamp)
  local zeroBasedMonth = (parts.year * 12 + parts.month - 1) + amount
  local year = math.floor(zeroBasedMonth / 12)
  local month = zeroBasedMonth - year * 12 + 1
  parts.year = year
  parts.month = month
  parts.day = math.min(parts.day, daysInMonth(year, month))
  parts.isdst = nil
  return os.time(parts)
end

local function applyDateOffset(timestamp, offsetText)
  local shifted = timestamp
  for sign, amountText, unit in offsetText:gmatch("([+-])(%d+)([yMdhm])") do
    local amount = tonumber(amountText) or 0
    if sign == "-" then amount = -amount end
    if unit == "y" then
      shifted = addCalendarMonths(shifted, amount * 12)
    elseif unit == "M" then
      shifted = addCalendarMonths(shifted, amount)
    else
      local parts = os.date("*t", shifted)
      if unit == "d" then
        parts.day = parts.day + amount
      elseif unit == "h" then
        parts.hour = parts.hour + amount
      elseif unit == "m" then
        parts.min = parts.min + amount
      end
      parts.isdst = nil
      shifted = os.time(parts)
    end
  end
  return shifted
end

local function placeholderAttribute(body, name)
  local quoted = body:match(name .. '%s*=%s*"([^"]*)"')
  if quoted ~= nil then return quoted end
  return body:match(name .. "%s*=%s*([^%s]+)")
end

local function formatDynamicDate(timestamp, format)
  local parts = os.date("*t", timestamp)
  local hour12 = parts.hour % 12
  if hour12 == 0 then hour12 = 12 end
  local values = {
    EEEE = weekdayNames[parts.wday],
    MMMM = monthNames[parts.month],
    yyyy = string.format("%04d", parts.year),
    EEE = weekdayNamesShort[parts.wday],
    MMM = monthNamesShort[parts.month],
    SSS = "000",
    yy = string.format("%02d", parts.year % 100),
    MM = string.format("%02d", parts.month),
    dd = string.format("%02d", parts.day),
    HH = string.format("%02d", parts.hour),
    hh = string.format("%02d", hour12),
    mm = string.format("%02d", parts.min),
    ss = string.format("%02d", parts.sec),
    M = tostring(parts.month),
    d = tostring(parts.day),
    H = tostring(parts.hour),
    h = tostring(hour12),
    m = tostring(parts.min),
    s = tostring(parts.sec),
    a = parts.hour < 12 and "AM" or "PM",
  }
  local tokenOrder = {
    "EEEE", "MMMM", "yyyy", "EEE", "MMM", "SSS",
    "yy", "MM", "dd", "HH", "hh", "mm", "ss",
    "M", "d", "H", "h", "m", "s", "a",
  }
  local output, index, literal = {}, 1, false
  while index <= #format do
    local character = format:sub(index, index)
    if character == "'" then
      if format:sub(index + 1, index + 1) == "'" then
        output[#output + 1] = "'"
        index = index + 2
      else
        literal = not literal
        index = index + 1
      end
    elseif literal then
      output[#output + 1] = character
      index = index + 1
    else
      local matched = false
      for _, token in ipairs(tokenOrder) do
        if format:sub(index, index + #token - 1) == token then
          output[#output + 1] = values[token]
          index = index + #token
          matched = true
          break
        end
      end
      if not matched then
        output[#output + 1] = character
        index = index + 1
      end
    end
  end
  return table.concat(output)
end

local cursorMarker = "<<<TRIGGER_SEARCH_CURSOR_7F3A>>>"

local function expandDynamicContent(content, clipboardText, timestamp)
  local baseTimestamp = timestamp or os.time()
  local expanded = content:gsub("{([^{}\r\n]+)}", function(rawBody)
    local body = trim(rawBody)
    if body == "clipboard" then return clipboardText or "" end
    if body == "cursor" then return cursorMarker end

    local keyword = body:match("^([%a]+)")
    if keyword ~= "date" and keyword ~= "time"
        and keyword ~= "datetime" and keyword ~= "day" then
      return "{" .. rawBody .. "}"
    end

    local defaultFormats = {
      date = "MM/dd/yyyy",
      time = "h:mm a",
      datetime = "MM/dd/yyyy h:mm a",
      day = "EEEE",
    }
    local format = placeholderAttribute(body, "format")
      or defaultFormats[keyword]
    local offset = placeholderAttribute(body, "offset") or ""
    return formatDynamicDate(applyDateOffset(baseTimestamp, offset), format)
  end)

  local cursorStart = expanded:find(cursorMarker, 1, true)
  local cursorLeft = 0
  if cursorStart then
    local suffix = expanded:sub(cursorStart + #cursorMarker)
      :gsub(cursorMarker, "")
    cursorLeft = utf8.len(suffix) or #suffix
  end
  expanded = expanded:gsub(cursorMarker, "")
  return expanded, cursorLeft
end

local function formatCalculationNumber(value)
  if math.abs(value) < 1e-12 then value = 0 end
  if value == math.floor(value) then return string.format("%.0f", value) end
  return string.format("%.10f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function parseArithmetic(query)
  local expression = trim(query)
  local explicit = expression:sub(1, 1) == "="
  if explicit then expression = trim(expression:sub(2)) end
  if expression == "" or not expression:match("^[%d%.%s%+%-%*%/%(%)]*$") then
    return nil
  end
  if not explicit and not expression:match("[%+%-%*%/%(%)]") then return nil end

  local state = { text = expression, position = 1 }
  local function skipWhitespace()
    while state.text:sub(state.position, state.position):match("%s") do
      state.position = state.position + 1
    end
  end

  local parseExpression
  local function parsePrimary()
    skipWhitespace()
    local character = state.text:sub(state.position, state.position)
    if character == "+" or character == "-" then
      state.position = state.position + 1
      local value, errorMessage = parsePrimary()
      if value == nil then return nil, errorMessage end
      return character == "-" and -value or value
    end
    if character == "(" then
      state.position = state.position + 1
      local value, errorMessage = parseExpression()
      if value == nil then return nil, errorMessage end
      skipWhitespace()
      if state.text:sub(state.position, state.position) ~= ")" then
        return nil, "missing closing parenthesis"
      end
      state.position = state.position + 1
      return value
    end

    local start = state.position
    local dots = 0
    while true do
      character = state.text:sub(state.position, state.position)
      if character:match("%d") then
        state.position = state.position + 1
      elseif character == "." and dots == 0 then
        dots = dots + 1
        state.position = state.position + 1
      else
        break
      end
    end
    local numberText = state.text:sub(start, state.position - 1)
    if numberText == "" or numberText == "." then return nil, "expected a number" end
    return tonumber(numberText)
  end

  local function parseTerm()
    local value, errorMessage = parsePrimary()
    if value == nil then return nil, errorMessage end
    while true do
      skipWhitespace()
      local operator = state.text:sub(state.position, state.position)
      if operator ~= "*" and operator ~= "/" then break end
      state.position = state.position + 1
      local right, rightError = parsePrimary()
      if right == nil then return nil, rightError end
      if operator == "/" and right == 0 then return nil, "division by zero" end
      value = operator == "*" and value * right or value / right
    end
    return value
  end

  parseExpression = function()
    local value, errorMessage = parseTerm()
    if value == nil then return nil, errorMessage end
    while true do
      skipWhitespace()
      local operator = state.text:sub(state.position, state.position)
      if operator ~= "+" and operator ~= "-" then break end
      state.position = state.position + 1
      local right, rightError = parseTerm()
      if right == nil then return nil, rightError end
      value = operator == "+" and value + right or value - right
    end
    return value
  end

  local value, errorMessage = parseExpression()
  skipWhitespace()
  if value == nil then return nil, errorMessage end
  if state.position <= #state.text then return nil, "unexpected character" end
  return value
end

local function utilityChoice(query, timestamp)
  local cleaned = trim(query)
  local amountText, unit = cleaned:match("^(%d+)%s*([dDwWmMyY])$")
  if amountText and unit then
    local amount = tonumber(amountText)
    local normalizedUnit = unit:upper()
    local shifted = timestamp or os.time()
    local unitName
    if normalizedUnit == "D" then
      local parts = os.date("*t", shifted)
      parts.day = parts.day + amount
      parts.isdst = nil
      shifted = os.time(parts)
      unitName = amount == 1 and "day" or "days"
    elseif normalizedUnit == "W" then
      local parts = os.date("*t", shifted)
      parts.day = parts.day + amount * 7
      parts.isdst = nil
      shifted = os.time(parts)
      unitName = amount == 1 and "week" or "weeks"
    elseif normalizedUnit == "M" then
      shifted = addCalendarMonths(shifted, amount)
      unitName = amount == 1 and "month" or "months"
    else
      shifted = addCalendarMonths(shifted, amount * 12)
      unitName = amount == 1 and "year" or "years"
    end
    local pasteValue = formatDynamicDate(shifted, "MM/dd/yyyy")
    return {
      text = formatDynamicDate(shifted, "MMMM d, yyyy"),
      subText = tostring(amount) .. " " .. unitName
        .. " from today  •  Enter to paste " .. pasteValue,
      content = pasteValue,
      isUtility = true,
      utilityType = "date",
    }
  end

  local value, errorMessage = parseArithmetic(cleaned)
  if value ~= nil then
    local result = formatCalculationNumber(value)
    return {
      text = result,
      subText = cleaned:gsub("^=%s*", "") .. "  •  Enter to paste result",
      content = result,
      isUtility = true,
      utilityType = "arithmetic",
    }
  end
  if errorMessage == "division by zero" then
    return {
      text = "Cannot divide by zero",
      subText = cleaned,
      content = "",
      isUtility = true,
      isUtilityError = true,
    }
  end
  return nil
end

local function parseSheet(csv, category)
  local rows = csvRows(csv)
  if #rows == 0 then return nil, "the CSV is empty" end

  local function addSnippet(parsed, sheetLabel, sheetContent, rowIndex,
      detailName, detailColumnIndex, baseEditColumnIndex, aiPrompt)
    local label = sheetLabel ~= "" and sheetLabel or trim(sheetContent)
    if label == "" then return end

    local hasContent = trim(sheetContent) ~= ""
    if detailName and not hasContent and trim(aiPrompt) == "" then return end
    local content = hasContent and sheetContent or (detailName and "" or label)
    local preview = sheetContent:gsub("%s+", " ")
    if #preview > 90 then preview = preview:sub(1, 87) .. "..." end
    local displayText = detailName or label
    local searchLabel = detailName and (label .. " " .. detailName) or label
    local subText = category
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
      local editRange = "A" .. tostring(rowIndex)
      if detailColumnIndex then
        editRange = columnLetter(detailColumnIndex) .. tostring(rowIndex)
      elseif baseEditColumnIndex then
        editRange = columnLetter(baseEditColumnIndex) .. tostring(rowIndex)
      end
      editUrl = "https://docs.google.com/spreadsheets/d/"
        .. config.sheetId .. "/edit#gid=" .. tostring(sheetGid)
        .. "&range=" .. editRange
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
      hasSavedContent = hasContent or not detailName,
      aiPrompt = trim(aiPrompt),
      editUrl = editUrl,
      image = bulletChoiceImage,
    }
  end

  local columns = {}
  for index, name in ipairs(rows[1]) do
    local normalizedName = trim(name):gsub("^\239\187\191", ""):lower()
    columns[normalizedName] = index
  end

  local hasHeaders = columns.label ~= nil or columns.content ~= nil
  if not hasHeaders then
    local rightmostContentColumn = 0
    for _, row in ipairs(rows) do
      for columnIndex, value in ipairs(row) do
        if trim(value) ~= "" then
          rightmostContentColumn = math.max(rightmostContentColumn, columnIndex)
        end
      end
    end
    if rightmostContentColumn > 2 then
      return nil, "headerless tabs may use only one or two columns"
    end
    columns.label = 1
    if rightmostContentColumn >= 2 then columns.content = 2 end
  elseif not columns.label or not columns.content then
    print('Mac autocomplete: "' .. category
      .. '" is missing Label or Content; using the column that remains')
  end

  local parsed = {}
  local firstDataRow = hasHeaders and 2 or 1
  local aiPrompts = {}
  if hasHeaders then
    for rowIndex = firstDataRow, #rows do
      local metadataLabel = columns.label and trim(rows[rowIndex][columns.label] or "") or ""
      if metadataLabel:lower():gsub("[%s_%-]+", "") == "aiprompt" then
        for columnIndex, value in ipairs(rows[rowIndex]) do
          if trim(value) ~= "" then aiPrompts[columnIndex] = value end
        end
      end
    end
  end
  for rowIndex = firstDataRow, #rows do
    local row = rows[rowIndex]
    local sheetLabel = columns.label and trim(row[columns.label] or "") or ""
    local sheetContent = columns.content and (row[columns.content] or "") or ""
    local aliasText = hasHeaders and columns.alias
      and trim(row[columns.alias] or "") or ""
    local isAiMetadata = sheetLabel:lower():gsub("[%s_%-]+", "") == "aiprompt"
    if not isAiMetadata then
    local baseEditColumnIndex = trim(sheetContent) ~= ""
      and columns.content or columns.label
    local rootIndex = #parsed + 1
    addSnippet(parsed, sheetLabel, sheetContent, rowIndex, nil, nil,
      baseEditColumnIndex, columns.content and aiPrompts[columns.content])

    local parentLabel = sheetLabel ~= "" and sheetLabel or trim(sheetContent)
    if hasHeaders and parentLabel ~= "" then
      for columnIndex, header in ipairs(rows[1]) do
        local detailName = trim(header):gsub("^\239\187\191", "")
        if columnIndex ~= columns.label and columnIndex ~= columns.content
            and columnIndex ~= columns.alias
            and detailName ~= "" then
          addSnippet(parsed, parentLabel, row[columnIndex] or "", rowIndex,
            detailName, columnIndex, nil, aiPrompts[columnIndex])
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
        root.text = nestedDisplayText(root.text)
      end
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
            if key == "launchermodifier" then
              config.launcherModifier = value ~= "" and value or "None"
            end
            if key == "launcherkey" then
              config.launcherKey = value ~= "" and value or "None"
            end
            if key == "aiengine" and value ~= "" then
              config.aiEngine = value
            end
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
  if not parsed or #parsed == 0 then
    errorMessage = errorMessage or "no usable autocomplete rows were found"
    print("Mac autocomplete: ignored " .. source .. ": " .. errorMessage)
    return false
  end

  snippets = parsed
  local targets = {}
  for _, category in ipairs(configuredSheetNames()) do
    if sheetCsvs[category] then
      targets[category] = newSnippetTarget(sheetCsvs[category])
    end
  end
  newSnippetTargets = targets
  if updateLauncherHotkey then updateLauncherHotkey() end
  if chooser then chooser:choices(rankedSnippets(chooser:query() or "")) end
  print(string.format("Mac autocomplete: loaded %d snippets from %s", #snippets, source))
  return true
end

rankedSnippets = function(query)
  local needle = trim(query):lower()

  -- The root chooser is intentionally search-first instead of an alphabetical
  -- browser. Nested views still reveal their choices immediately.
  if not detailParent and needle == "" then return {} end

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
  local utility = not detailParent and utilityChoice(query)
  if utility then
    utility.image = bulletChoiceImage
    choices[#choices + 1] = utility
  end
  for _, match in ipairs(matches) do choices[#choices + 1] = match.choice end
  return choices
end

local function updateChooserHotkeys()
  local visible = chooser and chooser:isVisible()
  local actionVisible = actionChooser and actionChooser:isVisible()
  if editHotkey then
    if visible then editHotkey:enable() else editHotkey:disable() end
  end
  if copyHotkey then
    if visible then copyHotkey:enable() else copyHotkey:disable() end
  end
  if aiHotkey then
    if visible then aiHotkey:enable() else aiHotkey:disable() end
  end
  if actionsHotkey then
    if visible then actionsHotkey:enable() else actionsHotkey:disable() end
  end
  if openDetailsHotkey then
    if visible then openDetailsHotkey:enable() else openDetailsHotkey:disable() end
  end
  if backHotkey then
    if actionVisible or (visible and detailParent) then
      backHotkey:enable()
    else
      backHotkey:disable()
    end
  end
  if openLinkHotkey then
    if visible then openLinkHotkey:enable() else openLinkHotkey:disable() end
  end
  if escapeHotkey then
    if visible or actionVisible then escapeHotkey:enable() else escapeHotkey:disable() end
  end
end

local function rootPlaceholder()
  return "Search"
end

local function openDetails(choice)
  if not choice or choice.isDetail or not choice.detailCount
      or choice.detailCount == 0 then return end
  rootQuery = chooser:query() or rootQuery
  returnParentCategory = choice.category
  returnParentRow = choice.rowIndex
  detailParent = choice
  chooser:placeholderText("←  " .. choice.groupLabel)
  chooser:query("")
  chooser:choices(rankedSnippets(""))
  updateChooserHotkeys()
end

local function openChoiceLink(choice, standaloneOnly)
  if not choice or choice.isUtilityError then return false end
  local expandedContent = expandDynamicContent(
    choice.content, hs.pasteboard.getContents() or "")
  local launchUrl
  if standaloneOnly then
    launchUrl = extractStandaloneLaunchUrl(expandedContent)
  else
    launchUrl = extractLaunchUrl(expandedContent)
  end
  if not launchUrl then return false end
  chooser:hide()
  atBoundary = true
  hs.urlevent.openURL(launchUrl)
  return true
end

local function openSelectedAction(choice)
  if not choice then return end
  if not detailParent and not choice.isDetail and choice.detailCount
      and choice.detailCount > 0 then
    openDetails(choice)
    return
  end
  openChoiceLink(choice, true)
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
  if choice.isUtilityError then
    hs.alert.show(choice.text)
    return
  end
  if choice.hasSavedContent == false or trim(choice.content) == "" then
    if trim(choice.aiPrompt) ~= "" then
      launchAiPrompt(choice)
    else
      hs.alert.show("No saved text or AI prompt is configured")
    end
    return
  end
  local oldClipboard = hs.pasteboard.getContents()
  local expandedContent, cursorLeft = expandDynamicContent(
    choice.content, oldClipboard or "")
  hs.pasteboard.setContents(expandedContent)

  local targetApp = previousApp
  if targetApp then targetApp:activate() end

  hs.timer.doAfter(0.08, function()
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    if cursorLeft > 0 then
      hs.timer.doAfter(0.04, function()
        for _ = 1, cursorLeft do
          hs.eventtap.keyStroke({}, "left", 0)
        end
      end)
    end
    atBoundary = expandedContent:match("%s$") ~= nil
  end)

  hs.timer.doAfter(0.8, function()
    if hs.pasteboard.getContents() == expandedContent then
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

local function copySnippet(choice)
  if not choice or choice.isUtilityError then return end
  if choice.hasSavedContent == false or trim(choice.content) == "" then
    hs.alert.show("No saved text to copy")
    return
  end
  local expandedContent = expandDynamicContent(
    choice.content, hs.pasteboard.getContents() or "")
  hs.pasteboard.setContents(expandedContent)
  chooser:hide()
  atBoundary = true
end

local function urlEncode(value)
  return (tostring(value or ""):gsub("([^%w%-_%.~])", function(character)
    return string.format("%%%02X", string.byte(character))
  end))
end

local function buildAiPrompt(choice)
  if not choice or trim(choice.aiPrompt) == "" then return nil end
  local prompt = choice.aiPrompt
  local item = choice.groupLabel or choice.label or choice.text or ""
  local replaced = false
  local function replace(pattern)
    local count
    prompt, count = prompt:gsub(pattern, item)
    if count > 0 then replaced = true end
  end
  replace("{[Mm][Ee][Dd][Ii][Cc][Aa][Tt][Ii][Oo][Nn]}")
  replace("{[Ii][Tt][Ee][Mm]}")
  replace("{[Ll][Aa][Bb][Ee][Ll]}")
  if not replaced and trim(item) ~= "" then
    local category = (choice.category or ""):lower()
    local contextName = category:find("med", 1, true) and "Medication" or "Item"
    prompt = prompt .. "\n\n" .. contextName .. ": " .. item
  end
  return prompt
end

local function copyAiPrompt(choice)
  local prompt = buildAiPrompt(choice)
  if not prompt then
    hs.alert.show("No AI prompt is configured for this item")
    return false
  end
  hs.pasteboard.setContents(prompt)
  return true
end

launchAiPrompt = function(choice)
  local prompt = buildAiPrompt(choice)
  if not prompt then
    hs.alert.show("No AI prompt is configured for this item")
    return
  end
  hs.pasteboard.setContents(prompt)
  chooser:hide()
  atBoundary = true
  local engine = trim(config.aiEngine):lower():gsub("[%s_%-]+", "")
  if engine == "googleaimode" or engine == "googleai" then
    hs.urlevent.openURL("https://www.google.com/search?udm=50&q=" .. urlEncode(prompt))
  elseif engine == "microsoftcopilot" or engine == "copilot" then
    hs.urlevent.openURL("https://copilot.microsoft.com/")
    hs.alert.show("AI prompt copied — paste it into Copilot")
  else
    hs.urlevent.openURL("https://chatgpt.com/?q=" .. urlEncode(prompt))
  end
end

local function restoreAfterActions()
  if not chooser then return end
  chooser:placeholderText(detailParent and ("←  " .. detailParent.groupLabel)
    or rootPlaceholder())
  chooser:query(actionReturnQuery)
  chooser:choices(rankedSnippets(actionReturnQuery))
  if actionReturnRow and actionReturnRow > 0 then chooser:selectedRow(actionReturnRow) end
  chooser:show()
end

local function performAction(actionId, choice)
  if actionId == "paste" then pasteSnippet(choice)
  elseif actionId == "copy" then copySnippet(choice)
  elseif actionId == "ai" then launchAiPrompt(choice)
  elseif actionId == "copyAi" then
    if copyAiPrompt(choice) then
      actionChooser:hide()
      atBoundary = true
    end
  elseif actionId == "open" then openChoiceLink(choice, false)
  elseif actionId == "edit" then editSnippet(choice)
  elseif actionId == "back" then restoreAfterActions()
  end
end

showActions = function()
  if not chooser or not chooser:isVisible() then return end
  local choice = chooser:selectedRowContents()
  if not choice then return end
  actionChoice = choice
  actionReturnQuery = chooser:query() or ""
  actionReturnRow = chooser:selectedRow() or 1
  local actions = {}
  local function add(text, subText, actionId, available)
    local displayText, displaySubText = text, subText
    if not available then
      local dim = { color = { white = 0.5, alpha = 1 } }
      displayText = hs.styledtext.new(text, dim)
      displaySubText = hs.styledtext.new(subText, dim)
    end
    actions[#actions + 1] = {
      text = displayText,
      subText = displaySubText,
      actionId = actionId,
      valid = available,
      image = available and bulletChoiceImage or hollowChoiceImage,
    }
  end
  local hasSavedContent = choice.hasSavedContent ~= false
    and trim(choice.content) ~= ""
  local hasAi = trim(choice.aiPrompt) ~= ""
  local hasLink = extractLaunchUrl(choice.content or "") ~= nil
  add("Paste", "Return", "paste", hasSavedContent)
  add("Copy", "⌘C", "copy", hasSavedContent)
  add("Ask AI", hasSavedContent and ("⌘Return  •  " .. config.aiEngine)
    or ("Return or ⌘Return  •  " .. config.aiEngine), "ai", hasAi)
  add("Copy AI prompt", "Copy the prepared prompt", "copyAi", hasAi)
  add("Open link", "⌘O", "open", hasLink)
  add("Edit in Google Sheets", "⌘E", "edit", choice.editUrl ~= nil)
  chooser:hide()
  actionChooser:placeholderText("←  Actions for "
    .. (choice.groupLabel or choice.label or "item"))
  actionChooser:choices(actions)
  actionChooser:show()
end

showChooser = function()
  if config.sheetId == "" then
    promptForGoogleSheet(true)
    return
  end
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

updateLauncherHotkey = function()
  if launcherHotkey then
    launcherHotkey:disable()
    launcherHotkey:delete()
    launcherHotkey = nil
  end

  local modifierName = trim(config.launcherModifier):lower()
    :gsub("[%s_/%-]+", "")
  local keyName = trim(config.launcherKey):lower():gsub("[%s_%-]+", "")
  if keyName == "" or keyName == "none" then return end

  local modifiers = {}
  if modifierName == "" or modifierName == "none" then
    modifiers = {}
  elseif modifierName == "altoption" or modifierName == "alt"
      or modifierName == "option" then
    modifiers = { "alt" }
  elseif modifierName == "control" or modifierName == "ctrl" then
    modifiers = { "ctrl" }
  elseif modifierName == "commandwindows" or modifierName == "command"
      or modifierName == "cmd" or modifierName == "windows"
      or modifierName == "win" then
    modifiers = { "cmd" }
  elseif modifierName == "shift" then
    modifiers = { "shift" }
  else
    print("Mac autocomplete: unsupported Launcher Modifier: "
      .. tostring(config.launcherModifier))
    return
  end

  if keyName == "enter" then keyName = "return" end
  local isFunctionKey = keyName:match("^f%d%d?$") ~= nil
    and tonumber(keyName:sub(2)) <= 12
  local isLetterOrNumber = keyName:match("^[a-z0-9]$") ~= nil
  local isNamedKey = keyName == "space" or keyName == "return"
    or keyName == "tab"
  if not isFunctionKey and not isLetterOrNumber and not isNamedKey then
    print("Mac autocomplete: unsupported Launcher Key: "
      .. tostring(config.launcherKey))
    return
  end
  if #modifiers == 0 and not isFunctionKey then
    print("Mac autocomplete: a launcher without a modifier must use F1-F12")
    return
  end

  launcherHotkey = hs.hotkey.new(modifiers, keyName, showChooser)
  launcherHotkey:enable()
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

  if (chooser and chooser:isVisible())
      or (actionChooser and actionChooser:isVisible()) then
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

local function downloadWorkbook(sheetId, allowFallback, callback)
  local function fetchSheetCsvs(sheetNames, sheetGids)
    if #sheetNames == 0 then
      callback(nil, "No visible autocomplete tabs were found.")
      return
    end

    local responses, remaining, failures = {}, #sheetNames, {}

    local function finishSheet(category, body, errorMessage)
      if body then
        responses[category] = body
      else
        failures[#failures + 1] = category .. ": " .. tostring(errorMessage)
      end

      remaining = remaining - 1
      if remaining == 0 then
        if #failures > 0 then
          callback(nil, table.concat(failures, "; "))
        else
          callback({
            sheets = responses,
            sheetNames = sheetNames,
            sheetGids = sheetGids,
          })
        end
      end
    end

    for _, sheetName in ipairs(sheetNames) do
      local category = sheetName
      local baseUrl = "https://docs.google.com/spreadsheets/d/"
        .. encodeQueryValue(sheetId)
      local gvizUrl = baseUrl .. "/gviz/tq?tqx=out:csv&sheet="
        .. encodeQueryValue(category)
        .. "&cacheBust=" .. tostring(os.time())
      local gid = type(sheetGids) == "table" and sheetGids[category] or nil
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
    .. encodeQueryValue(sheetId)
    .. "/htmlview?cacheBust=" .. tostring(os.time())
  hs.http.asyncGet(metadataUrl, nil, function(status, body)
    if status == 200 then
      local names, gids = discoverSheets(body)
      if names then
        fetchSheetCsvs(names, gids)
        return
      end
      if not allowFallback then
        callback(nil, "The workbook did not expose a visible tab list. "
          .. "Make sure it is published to the web.")
        return
      end
      print("Mac autocomplete: could not discover tabs: " .. tostring(gids))
    elseif not allowFallback then
      callback(nil, "Google returned HTTP " .. tostring(status)
        .. ". Make sure the link is correct and the workbook is published to the web.")
      return
    else
      print("Mac autocomplete: tab discovery failed with HTTP " .. tostring(status))
    end
    fetchSheetCsvs(configuredSheetNames(), config.sheetGids)
  end)
end

local function installWorkbook(data, source, sheetId)
  local oldNames, oldGids, oldTrigger, oldLauncherModifier, oldLauncherKey =
    discoveredSheetNames, config.sheetGids, config.trigger,
    config.launcherModifier, config.launcherKey
  discoveredSheetNames = data.sheetNames
  config.sheetGids = data.sheetGids or {}
  if not installSheets(data.sheets, source) or #snippets == 0 then
    discoveredSheetNames, config.sheetGids = oldNames, oldGids
    config.trigger = oldTrigger
    config.launcherModifier, config.launcherKey = oldLauncherModifier, oldLauncherKey
    if updateLauncherHotkey then updateLauncherHotkey() end
    return false, "No usable autocomplete rows were found. "
      .. "Use Label/Content headers, or one or two headerless columns."
  end

  local cacheJson = hs.json.encode({
    sheetId = sheetId,
    sheets = data.sheets,
    sheetNames = data.sheetNames,
    sheetGids = data.sheetGids,
  })
  local ok, cacheError = writeFile(config.cachePath, cacheJson)
  if not ok then
    print("Mac autocomplete: could not write cache: " .. tostring(cacheError))
  end
  return true
end

refresh = function()
  if config.sheetId == "" or config.sheetId == "PASTE_YOUR_SHEET_ID_HERE" then
    return
  end
  if refreshInProgress then return end
  refreshInProgress = true

  downloadWorkbook(config.sheetId, true, function(data, errorMessage)
    refreshInProgress = false
    if not data then
      print("Mac autocomplete: refresh failed: " .. tostring(errorMessage))
      return
    end
    local ok, installError = installWorkbook(data, "Google Sheets", config.sheetId)
    if not ok then
      print("Mac autocomplete: refresh failed: " .. tostring(installError))
    end
  end)
end

local function openWorkbook()
  if config.sheetId == "" then return end
  hs.urlevent.openURL("https://docs.google.com/spreadsheets/d/"
    .. config.sheetId .. "/edit")
end

local function openNewSnippet(category)
  if config.sheetId == "" then return end
  local target = newSnippetTargets[category] or "A2"
  local gid = type(config.sheetGids) == "table" and config.sheetGids[category] or nil
  local url = "https://docs.google.com/spreadsheets/d/"
    .. config.sheetId .. "/edit"
  if gid ~= nil then url = url .. "#gid=" .. tostring(gid) end
  url = url .. (gid ~= nil and "&range=" or "#range=") .. target
  hs.urlevent.openURL(url)
end

local function buildNewSnippetMenu()
  local items = {}
  for _, category in ipairs(configuredSheetNames()) do
    local sheetName = category
    items[#items + 1] = {
      title = sheetName,
      fn = function() openNewSnippet(sheetName) end,
    }
  end
  if #items == 0 then
    items[1] = { title = "No autocomplete tabs found", disabled = true }
  end
  return items
end

promptForGoogleSheet = function(firstRun)
  if refreshInProgress then
    hs.alert.show("Trigger Search is already refreshing. Try again in a moment.")
    return
  end

  local title = firstRun and "Set up Trigger Search" or "Change Google Sheet"
  local defaultText = config.sheetId ~= "" and
    ("https://docs.google.com/spreadsheets/d/" .. config.sheetId .. "/edit") or ""
  local button, value = hs.dialog.textPrompt(
    title,
    "Paste the link to your public Google Sheet. In Google Sheets, use "
      .. "File > Share > Publish to web first. This choice is saved only on this Mac.",
    defaultText,
    "Connect",
    "Cancel"
  )
  if button ~= "Connect" then return end

  local newSheetId = extractSheetId(value)
  if not newSheetId then
    hs.dialog.blockAlert(
      "That does not look like a Google Sheets link.",
      "Paste the complete link from your browser and try again.",
      "OK", nil, "warning")
    return
  end

  refreshInProgress = true
  downloadWorkbook(newSheetId, false, function(data, errorMessage)
    refreshInProgress = false
    if not data then
      print("Mac autocomplete: Sheet connection failed: " .. tostring(errorMessage))
      hs.dialog.blockAlert(
        "Trigger Search could not use that Sheet.",
        tostring(errorMessage),
        "OK", nil, "critical")
      return
    end

    local oldSheetId = config.sheetId
    config.sheetId = newSheetId
    local ok, installError = installWorkbook(data, "Google Sheets", newSheetId)
    if not ok then
      config.sheetId = oldSheetId
      print("Mac autocomplete: Sheet connection failed: " .. tostring(installError))
      hs.dialog.blockAlert(
        "Trigger Search could not use that Sheet.",
        tostring(installError),
        "OK", nil, "critical")
      return
    end

    hs.settings.set(sheetSettingKey, newSheetId)
    hs.alert.show("Google Sheet connected: " .. tostring(#snippets) .. " snippets loaded")
  end)
end

local function buildSettingsMenu()
  settingsMenu = hs.menubar.new(true, "TriggerSearchMenu")
  if not settingsMenu then return end
  local iconPath = hs.configdir .. "/trigger-search-menuTemplate.png"
  local icon = hs.image.imageFromPath(iconPath)
  if icon then
    settingsMenu:setIcon(icon:setSize({ w = 18, h = 18 }), true)
  else
    settingsMenu:setTitle("TS")
  end
  settingsMenu:setTooltip("Trigger Search")
  settingsMenu:setMenu(function()
    local missingSheet = config.sheetId == ""
    return {
      { title = "Open Trigger Search", fn = showChooser },
      {
        title = "New Snippet",
        menu = buildNewSnippetMenu(),
        disabled = missingSheet,
      },
      { title = "Refresh Now", fn = refresh, disabled = missingSheet },
      { title = "Open Google Sheet", fn = openWorkbook, disabled = missingSheet },
      { title = "Change Google Sheet…", fn = function()
          promptForGoogleSheet(false)
        end },
    }
  end)
end

function M.start(userConfig)
  if keyWatcher then M.stop() end
  for key, value in pairs(userConfig or {}) do config[key] = value end
  local savedSheetId = trim(hs.settings.get(sheetSettingKey))
  if savedSheetId ~= "" then
    config.sheetId = savedSheetId
  elseif config.sheetId ~= "" and config.sheetId ~= "PASTE_YOUR_SHEET_ID_HERE" then
    -- Migrate an existing init.lua configuration into persistent local settings.
    hs.settings.set(sheetSettingKey, config.sheetId)
  else
    config.sheetId = ""
  end
  discoveredSheetNames = nil

  bulletChoiceImage = hs.image.imageFromURL(
    "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxNiAxNiI+PGNpcmNsZSBjeD0iOCIgY3k9IjgiIHI9IjIuNiIgZmlsbD0iIzY2NiIvPjwvc3ZnPg==")
  hollowChoiceImage = hs.image.imageFromURL(
    "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxNiAxNiI+PGNpcmNsZSBjeD0iOCIgY3k9IjgiIHI9IjIuOCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSIjODg4IiBzdHJva2Utd2lkdGg9IjEuMiIvPjwvc3ZnPg==")

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

  actionChooser = hs.chooser.new(function(action)
    if not action then
      if actionReturning then return end
      actionChoice = nil
      atBoundary = true
      return
    end
    performAction(action.actionId, actionChoice)
  end)
    :searchSubText(true)
    :rows(7)
    :width(config.width)
    :showCallback(updateChooserHotkeys)
    :hideCallback(updateChooserHotkeys)
    :invalidCallback(function() end)

  editHotkey = hs.hotkey.new({ "cmd" }, "e", function()
    if chooser and chooser:isVisible() then
      editSnippet(chooser:selectedRowContents())
    end
  end)

  copyHotkey = hs.hotkey.new({ "cmd" }, "c", function()
    if chooser and chooser:isVisible() then
      copySnippet(chooser:selectedRowContents())
    end
  end)

  aiHotkey = hs.hotkey.new({ "cmd" }, "return", function()
    if chooser and chooser:isVisible() then
      launchAiPrompt(chooser:selectedRowContents())
    end
  end)

  actionsHotkey = hs.hotkey.new({ "cmd" }, "k", function()
    showActions()
  end)

  openDetailsHotkey = hs.hotkey.new({}, "right", function()
    if chooser and chooser:isVisible() then
      openSelectedAction(chooser:selectedRowContents())
    end
  end)

  openLinkHotkey = hs.hotkey.new({ "cmd" }, "o", function()
    if chooser and chooser:isVisible() then
      openChoiceLink(chooser:selectedRowContents(), false)
    end
  end)

  backHotkey = hs.hotkey.new({}, "left", function()
    if actionChooser and actionChooser:isVisible() then
      actionReturning = true
      actionChooser:hide()
      restoreAfterActions()
      hs.timer.doAfter(0.05, function() actionReturning = false end)
    elseif chooser and chooser:isVisible() then
      closeDetails()
    end
  end)

  escapeHotkey = hs.hotkey.new({}, "escape", function()
    actionReturning = false
    actionChoice = nil
    detailParent = nil
    rootQuery = ""
    if actionChooser and actionChooser:isVisible() then actionChooser:hide() end
    if chooser and chooser:isVisible() then chooser:hide() end
    atBoundary = true
    updateChooserHotkeys()
  end)

  updateLauncherHotkey()

  local cachedJson = config.sheetId ~= "" and readFile(config.cachePath) or nil
  if cachedJson then
    local ok, cachedData = pcall(hs.json.decode, cachedJson)
    if ok and type(cachedData) == "table" then
      local cacheMatchesSheet = not cachedData.sheetId
        or cachedData.sheetId == config.sheetId
      local cachedSheets = cachedData
      if cacheMatchesSheet and type(cachedData.sheets) == "table" then
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
      if cacheMatchesSheet then installSheets(cachedSheets, "local cache") end
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

  buildSettingsMenu()
  if config.sheetId == "" then
    hs.timer.doAfter(0.2, function() promptForGoogleSheet(true) end)
  else
    refresh()
  end
  return M
end

function M.refresh()
  refresh()
end

-- Useful for testing and for users who want to bind an additional launcher.
function M.show()
  showChooser()
end

function M.expandDynamicContent(content, options)
  options = options or {}
  return expandDynamicContent(content or "", options.clipboard or "",
    options.timestamp)
end

function M.utilityChoice(query, options)
  options = options or {}
  return utilityChoice(query or "", options.timestamp)
end

function M.extractLaunchUrl(value)
  return extractLaunchUrl(value)
end

function M.extractStandaloneLaunchUrl(value)
  return extractStandaloneLaunchUrl(value)
end

function M.buildAiPrompt(choice)
  return buildAiPrompt(choice)
end

function M.urlEncode(value)
  return urlEncode(value)
end

function M.parseSheet(csv, category)
  return parseSheet(csv or "", category or "Test")
end

function M.stop()
  if keyWatcher then keyWatcher:stop(); keyWatcher = nil end
  if editHotkey then editHotkey:disable(); editHotkey:delete(); editHotkey = nil end
  if copyHotkey then copyHotkey:disable(); copyHotkey:delete(); copyHotkey = nil end
  if aiHotkey then aiHotkey:disable(); aiHotkey:delete(); aiHotkey = nil end
  if actionsHotkey then
    actionsHotkey:disable(); actionsHotkey:delete(); actionsHotkey = nil
  end
  if openDetailsHotkey then
    openDetailsHotkey:disable(); openDetailsHotkey:delete(); openDetailsHotkey = nil
  end
  if openLinkHotkey then
    openLinkHotkey:disable(); openLinkHotkey:delete(); openLinkHotkey = nil
  end
  if backHotkey then backHotkey:disable(); backHotkey:delete(); backHotkey = nil end
  if escapeHotkey then
    escapeHotkey:disable(); escapeHotkey:delete(); escapeHotkey = nil
  end
  if launcherHotkey then
    launcherHotkey:disable(); launcherHotkey:delete(); launcherHotkey = nil
  end
  if refreshTimer then refreshTimer:stop(); refreshTimer = nil end
  if mouseWatcher then mouseWatcher:stop(); mouseWatcher = nil end
  if appWatcher then appWatcher:stop(); appWatcher = nil end
  if settingsMenu then settingsMenu:delete(); settingsMenu = nil end
  if chooser then chooser:delete(); chooser = nil end
  if actionChooser then actionChooser:delete(); actionChooser = nil end
end

return M
