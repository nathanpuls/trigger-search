$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Load function definitions only; never run the installer or touch real Startup.
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../windows/refresh-all.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($fn in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
$fixture = Join-Path $env:TEMP ('trigger-startup-test-' + [guid]::NewGuid().ToString())
$root = Join-Path $fixture 'managed'
$legacy = Join-Path $fixture 'original Dell scripts'
$startup = Join-Path $fixture 'startup'
$shell = New-Object -ComObject WScript.Shell
function New-TestLink($Name, $Target, $Arguments = '') {
    $link = $shell.CreateShortcut((Join-Path $startup $Name))
    $link.TargetPath = $Target
    $link.Arguments = $Arguments
    $link.Save()
}
try {
    New-Item -ItemType Directory -Path $root, $legacy, $startup | Out-Null
    Set-Content (Join-Path $root 'Start-Trigger-Search.cmd') '@exit /b'
    Set-Content (Join-Path $legacy 'Start_All_My_Scripts.ahk') '; fixture, never executed'
    Set-Content (Join-Path $legacy 'launch AMD.ahk') '; fixture, never executed'
    Set-Content (Join-Path $legacy 'unrelated.ahk') '; fixture, never executed'
    New-TestLink 'Start all.lnk' (Join-Path $legacy 'Start_All_My_Scripts.ahk')
    New-TestLink 'Login.lnk' "$env:WINDIR\notepad.exe" ('"' + (Join-Path $legacy 'launch AMD.ahk') + '"')
    New-TestLink 'Unrelated.lnk' (Join-Path $legacy 'unrelated.ahk')
    $original = (Get-FileHash (Join-Path $startup 'Start all.lnk')).Hash
    $other = (Get-FileHash (Join-Path $startup 'Unrelated.lnk')).Hash
    $paths = @(Get-LegacyScriptPaths $legacy)
    if (Test-LegacyCommand ('"' + (Join-Path ($legacy + '-other') 'launch AMD.ahk') + '"') $paths) { throw 'Another folder matched.' }
    Set-LauncherOnlyStartup $root $startup $legacy
    if ((Test-Path (Join-Path $startup 'Start all.lnk')) -or (Test-Path (Join-Path $startup 'Login.lnk'))) { throw 'Legacy links were not backed up.' }
    if (-not (Test-Path (Join-Path $legacy 'Start_All_My_Scripts.ahk'))) { throw 'Original script moved.' }
    if ((Get-FileHash (Join-Path $startup 'Unrelated.lnk')).Hash -ne $other) { throw 'Unrelated shortcut changed.' }
    $journal = Join-Path $root 'startup-backup/state.json'
    $snapshot = Get-Content $journal -Raw
    Set-LauncherOnlyStartup $root $startup $legacy
    if ((Get-Content $journal -Raw) -ne $snapshot) { throw 'Repeated setup overwrote snapshot.' }
    # A new entry in the old location must block restoration without overwriting it.
    Set-Content (Join-Path $startup 'Start all.lnk') 'new shortcut to preserve'
    $blocked = $false
    try { Restore-StandaloneStartup $root } catch { $blocked = $true }
    if (-not $blocked -or -not (Test-Path $journal) -or (Get-Content (Join-Path $startup 'Start all.lnk') -Raw) -notmatch 'preserve') { throw 'Collision was not preserved.' }
    Remove-Item (Join-Path $startup 'Start all.lnk')
    Restore-StandaloneStartup $root
    if ((Get-FileHash (Join-Path $startup 'Start all.lnk')).Hash -ne $original) { throw 'Original shortcut bytes were not restored.' }
    if (-not (Test-Path (Join-Path $startup 'Login.lnk'))) { throw 'Argument-targeted shortcut not restored.' }
    if (Test-Path (Join-Path $startup 'Trigger Search (managed).lnk')) { throw 'Managed link was not removed.' }
    if ((Get-FileHash (Join-Path $startup 'Unrelated.lnk')).Hash -ne $other) { throw 'Restoration changed unrelated shortcut.' }
    Write-Host 'PASS: isolated Startup setup, path scope, repeated setup, collision protection, exact restoration.'
} finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
