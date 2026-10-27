# Exercise OOXML strikethrough without Excel, credentials, or live Sheet writes.
param([string]$LiveSheetId = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Join-Path ([IO.Path]::GetTempPath()) ('trigger-format-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $book = Join-Path $root 'fixture.xlsx'
    $zip = [IO.Compression.ZipFile]::Open($book, 'Create')
    function Add-Xml([string]$Name, [string]$Body) {
        $entry = $zip.CreateEntry($Name)
        $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
        try { $writer.Write($Body) } finally { $writer.Dispose() }
    }
    try {
        Add-Xml 'xl/workbook.xml' '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Snips" r:id="r1"/><sheet name="Automations" r:id="r2"/></sheets></workbook>'
        Add-Xml 'xl/_rels/workbook.xml.rels' '<Relationships><Relationship Id="r1" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Target="/xl/worksheets/sheet2.xml"/></Relationships>'
        Add-Xml 'xl/styles.xml' '<styleSheet><fonts><font/><font><strike/></font><font><strike val="0"/></font></fonts><cellXfs><xf fontId="0"/><xf fontId="1"/><xf fontId="2"/></cellXfs></styleSheet>'
        Add-Xml 'xl/sharedStrings.xml' '<sst><si><r><rPr><strike/></rPr><t>All </t></r><r><rPr><strike/></rPr><t>struck</t></r></si><si><r><rPr><strike/></rPr><t>Partially </t></r><r><t>active</t></r></si></sst>'
        Add-Xml 'xl/worksheets/sheet1.xml' '<worksheet><sheetData/></worksheet>'
        Add-Xml 'xl/worksheets/sheet2.xml' @'
<worksheet><sheetData>
<row r="1"><c r="A1" t="inlineStr"><is><t>Name</t></is></c><c r="D1" t="inlineStr"><is><t>Script ID</t></is></c></row>
<row r="2"><c r="A2" t="inlineStr" s="1"><is><t>Plan</t></is></c><c r="D2" t="inlineStr"><is><t>dell.plan-navigation</t></is></c></row>
<row r="3"><c r="A3" t="inlineStr" s="2"><is><t>Zoom</t></is></c><c r="D3" t="inlineStr"><is><t>zoom.join</t></is></c></row>
<row r="4"><c r="A4" t="s"><v>0</v></c><c r="D4" t="inlineStr"><is><t>dell.mse</t></is></c></row>
<row r="5"><c r="A5" t="s"><v>1</v></c><c r="D5" t="inlineStr"><is><t>dell.sid</t></is></c></row>
<row r="6"><c r="A6" t="inlineStr"><is><t>By ID</t></is></c><c r="D6" t="inlineStr" s="1"><is><t>clipboard.paste</t></is></c></row>
<row r="7"><c r="A7" t="inlineStr"><is><t>Description only</t></is></c><c r="C7" t="inlineStr" s="1"><is><t>Old note</t></is></c><c r="D7" t="inlineStr"><is><t>zoom.end</t></is></c></row>
<row r="8"><c r="A8" t="inlineStr" s="1"><is><t>Invalid command</t></is></c><c r="D8" t="inlineStr"><is><t>cmd.exe /c calc</t></is></c></row>
<row r="9"><c r="A9" t="inlineStr"><is><t>Duplicate active</t></is></c><c r="D9" t="inlineStr"><is><t>dell.plan-navigation</t></is></c></row>
<row r="10"><c r="A10" t="inlineStr" s="1"><is><r><rPr><strike val="0"/></rPr><t>Explicitly active</t></r></is></c><c r="D10" t="inlineStr"><is><t>teams.call-clipboard</t></is></c></row>
</sheetData></worksheet>
'@
    } finally { $zip.Dispose() }
    $output = Join-Path $root 'formatting.ini'
    $untouched = Join-Path $root 'must-not-install'
    $sid = 'formatting-fixture-sheet-0001'
    $script = Join-Path $PSScriptRoot '../windows/refresh-all.ps1'
    & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $script -ReadAutomationFormatting -FormattingWorkbook $book -FormattingSheetId $sid -FormattingOutput $output -InstallRoot $untouched
    if ($LASTEXITCODE -ne 0) { throw 'Formatting reader failed.' }
    $result = Get-Content $output -Raw
    foreach ($id in @('dell.plan-navigation', 'dell.mse', 'clipboard.paste')) {
        if ($result -notmatch ([regex]::Escape($id) + '=1')) { throw "Missing disabled fixture ID: $id" }
    }
    foreach ($id in @('zoom.join', 'dell.sid', 'zoom.end', 'teams.call-clipboard', 'cmd.exe')) {
        if ($result -match ([regex]::Escape($id) + '=')) { throw "An active/invalid fixture action was disabled: $id" }
    }
    if (Test-Path $untouched) { throw 'Formatting mode must not install, update, lock, or change Startup.' }
    if ($LiveSheetId) {
        $live = Join-Path $root 'live.ini'
        & "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $script -ReadAutomationFormatting -FormattingSheetId $LiveSheetId -FormattingOutput $live
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $live)) { throw 'Live public formatting export could not be verified.' }
        if ((Get-Content $live -Raw) -notmatch 'verified=1') { throw 'Live public formatting export was invalid.' }
        Write-Output 'PASS: live public formatting export parsed successfully (no cell contents logged).'
    }
    Write-Output 'PASS: full-cell and rich-text strike, explicit unstrike, duplicate precedence, ID cells, worksheet relationships, no install side effects.'
} finally { Remove-Item $root -Recurse -Force }
