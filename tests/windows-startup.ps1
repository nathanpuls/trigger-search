param([Parameter(Mandatory)][string]$AutoHotkeyPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Load functions only, never the updater body or any real Startup directory.
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../windows/refresh-all.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($fn in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) { . ([scriptblock]::Create($fn.Extent.Text)) }
$fixture = Join-Path $env:TEMP ('original-controls-test-' + [guid]::NewGuid().ToString())
$root = Join-Path $fixture 'managed'; $legacy = Join-Path $fixture 'original scripts'
$startup = Join-Path $fixture 'Startup'; $foreign = Join-Path $fixture 'unrelated scripts'
$shell = New-Object -ComObject WScript.Shell
$dummy = "#Requires AutoHotkey v2.0`n#NoTrayIcon`n#SingleInstance Off`nPersistent`n"
function New-TestLink($Name, $Target, $Arguments = '') {
    $link = $shell.CreateShortcut((Join-Path $startup $Name)); $link.TargetPath = $Target
    $link.Arguments = $Arguments; $link.Save()
}
function Start-TestScript($Path, $Extra = '') {
    Start-Process -FilePath $AutoHotkeyPath -ArgumentList ('"' + $Path + '" ' + $Extra) -PassThru
}
function Assert-Test($Condition, $Message) { if (-not $Condition) { throw $Message } }
$protected = @()
try {
    New-Item -ItemType Directory -Path $root, $legacy, $startup, $foreign | Out-Null
    foreach ($name in @('MSE.ahk', 'follow-up-office.ahk', 'test-esc.ahk', 'Start_All_My_Scripts.ahk', 'autocomplete.ahk', 'unrelated.ahk', 'HPI.ahk')) { Set-Content -LiteralPath (Join-Path $legacy $name) -Value $dummy -Encoding UTF8 }
    Set-Content -LiteralPath (Join-Path $foreign 'MSE.ahk') -Value $dummy -Encoding UTF8
    $config = New-OriginalConfig $root $legacy $startup $AutoHotkeyPath
    $production = @(Get-OriginalPaths $config -Production)
    Assert-Test ($production.Count -eq 2) 'ON must exclude launcher, startup-only helpers, wildcard, debug, and unknown files.'
    $quoted = '"' + $AutoHotkeyPath + '" "' + (Join-Path $legacy 'MSE.ahk') + '"'
    Assert-Test ((Get-AhkCommandScript $quoted) -in $production) 'Windows short/long paths must resolve to the same script.'
    $foreignCommand = '"' + $AutoHotkeyPath + '" "' + (Join-Path $foreign 'MSE.ahk') + '" "' + (Join-Path $legacy 'MSE.ahk') + '"'
    Assert-Test ((Get-AhkCommandScript $foreignCommand) -notin $production) 'Mentioning a legacy path as data must not select an unrelated process.'
    New-TestLink 'Trigger Search (managed).lnk' (Join-Path $legacy 'autocomplete.ahk')
    New-TestLink 'Start everything.lnk' (Join-Path $legacy 'Start_All_My_Scripts.ahk')
    New-TestLink 'Office production.lnk' $AutoHotkeyPath ('"' + (Join-Path $legacy 'follow-up-office.ahk') + '"')
    New-TestLink 'Unrelated.lnk' (Join-Path $foreign 'MSE.ahk')
    $launcherHash = (Get-FileHash (Join-Path $startup 'Trigger Search (managed).lnk')).Hash
    $otherHash = (Get-FileHash (Join-Path $startup 'Unrelated.lnk')).Hash
    $originalHash = (Get-FileHash (Join-Path $startup 'Office production.lnk')).Hash
    # Import an existing 0.16.7 snapshot without altering its launcher link/journal.
    New-Item -ItemType Directory -Path (Join-Path $root 'startup-backup') | Out-Null
    $saved = Join-Path $root 'startup-backup/old-wildcard.lnk'
    Copy-Item -LiteralPath (Join-Path $startup 'Start everything.lnk') -Destination $saved
    @{ legacyFolder = $legacy; entries = @(@{ original = (Join-Path $startup 'Start everything.lnk'); backup = $saved; hash = (Get-FileHash $saved).Hash }) } | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'startup-backup/state.json')
    $oldJournalHash = (Get-FileHash (Join-Path $root 'startup-backup/state.json')).Hash
    New-Item -ItemType Directory -Path (Split-Path $config.statePath) | Out-Null
    Import-OriginalStartupBackup $config $root
    $protected += Start-TestScript (Join-Path $legacy 'autocomplete.ahk')
    $protected += Start-TestScript (Join-Path $legacy 'unrelated.ahk') ('"' + (Join-Path $legacy 'MSE.ahk') + '"')
    $protected += Start-TestScript (Join-Path $foreign 'MSE.ahk')
    $null = Start-TestScript (Join-Path $legacy 'test-esc.ahk')
    $null = Start-TestScript (Join-Path $legacy 'MSE.ahk')
    Start-Sleep -Milliseconds 500
    Set-OriginalScriptsMode $config OFF
    Set-OriginalScriptsMode $config OFF
    Assert-Test (@(Get-OriginalProcesses $config).Count -eq 0) 'OFF must stop known originals and remain safe to repeat.'
    foreach ($p in $protected) { Assert-Test (-not $p.HasExited) 'OFF stopped Trigger Search or an unrelated script.' }
    Assert-Test (-not (Test-Path (Join-Path $startup 'Start everything.lnk'))) 'Wildcard startup was not disabled.'
    # Invalid original syntax prevents all launches and startup restoration.
    Set-Content -LiteralPath (Join-Path $legacy 'MSE.ahk') -Value 'this is invalid {{{' -Encoding UTF8
    $blocked = $false; try { Set-OriginalScriptsMode $config ON } catch { $blocked = $true }
    Assert-Test $blocked 'ON accepted invalid original syntax.'
    Assert-Test (@(Get-OriginalProcesses $config).Count -eq 0) 'Failed ON started a script.'
    Set-Content -LiteralPath (Join-Path $legacy 'MSE.ahk') -Value $dummy -Encoding UTF8
    Set-OriginalScriptsMode $config ON
    Start-Sleep -Milliseconds 500
    $first = @(Get-OriginalProcesses $config)
    Set-OriginalScriptsMode $config ON
    $second = @(Get-OriginalProcesses $config)
    Assert-Test ($first.Count -eq 2 -and $second.Count -eq 2 -and (@($first.Id | Sort-Object) -join ',') -eq (@($second.Id | Sort-Object) -join ',')) 'Repeated ON created duplicates or launched excluded files.'
    Assert-Test ((Get-FileHash (Join-Path $startup 'Office production.lnk')).Hash -eq $originalHash) 'Production shortcut was not restored byte for byte.'
    Assert-Test (-not (Test-Path (Join-Path $startup 'Start everything.lnk'))) 'ON restored the wildcard launcher.'
    # Changed shortcuts block OFF before any original process is stopped.
    $generated = $config.generated[0]
    $bytes = [IO.File]::ReadAllBytes($generated.path)
    Add-Content -LiteralPath $generated.path -Value 'preserve my edit'
    $blocked = $false; try { Set-OriginalScriptsMode $config OFF } catch { $blocked = $true }
    Assert-Test $blocked 'OFF overwrote an edited shortcut.'
    Assert-Test (@(Get-OriginalProcesses $config).Count -eq 2) 'Failed OFF stopped scripts before preflight.'
    [IO.File]::WriteAllBytes($generated.path, $bytes)
    Set-OriginalScriptsMode $config OFF
    Assert-Test ((Get-FileHash (Join-Path $startup 'Trigger Search (managed).lnk')).Hash -eq $launcherHash) 'Trigger Search startup changed.'
    Assert-Test ((Get-FileHash (Join-Path $startup 'Unrelated.lnk')).Hash -eq $otherHash) 'Unrelated Startup changed.'
    Assert-Test ((Get-FileHash (Join-Path $root 'startup-backup/state.json')).Hash -eq $oldJournalHash) 'Old startup journal changed.'
    Assert-Test ((Get-Content -LiteralPath (Join-Path $legacy 'MSE.ahk') -Raw).Trim() -eq $dummy.Trim()) 'Original source changed.'
    Write-Host 'PASS: scoped live OFF/ON, repetition, startup persistence, old-backup import, syntax/collision protection, launcher and unrelated process preservation.'
} finally {
    # Only dummy processes from this random fixture are cleaned up.
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'")) {
        $script = Get-AhkCommandScript $p.CommandLine
        if ($script -and $script.StartsWith((Get-OriginalPath $fixture) + '\', [StringComparison]::OrdinalIgnoreCase)) { Stop-Process -Id $p.ProcessId -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
