param([Parameter(Mandatory)][string]$AutoHotkeyPath, [Parameter(Mandatory)][string]$Ref)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('trigger-search-test-' + [guid]::NewGuid().ToString())
$updater = Join-Path $PSScriptRoot '../windows/refresh-all.ps1'
function Invoke-Refresh([string[]]$Extra, [bool]$ShouldPass = $true) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updater -InstallRoot $root -AutoHotkeyPath $AutoHotkeyPath -Ref $Ref -NoStart @Extra
    if (($LASTEXITCODE -eq 0) -ne $ShouldPass) { throw "Unexpected updater exit: $LASTEXITCODE" }
}
try {
    # Download pinned code, validate all files and self-tests, install without opening a launcher.
    Invoke-Refresh @()
    $statePath = Join-Path $root 'current.json'
    $initial = Get-Content $statePath -Raw
    $state = $initial | ConvertFrom-Json
    Invoke-Refresh @()
    if ((Get-Content $statePath -Raw) -ne $initial) { throw 'Repeated refresh changed installation state.' }
    if (-not (Test-Path (Join-Path $root 'Refresh-All.cmd'))) { throw 'Refresh shortcut missing.' }
    if (Test-Path (Join-Path $root 'previous.json')) { throw 'Unchanged refresh created a rollback snapshot.' }
    # A local edit is detected and left untouched. Failed refresh keeps current.json unchanged.
    $script = Join-Path $root "releases/$($state.commit)/windows/autocomplete.ahk"
    $original = [IO.File]::ReadAllBytes($script)
    Add-Content $script "`n; local change to preserve"
    Invoke-Refresh @() $false
    if ((Get-Content $statePath -Raw) -ne $initial) { throw 'Failure changed active state.' }
    if ((Get-Content $script -Raw) -notmatch 'local change to preserve') { throw 'Local edit was overwritten.' }
    [IO.File]::WriteAllBytes($script, $original)
    # A held updater lock fails without changing state.
    $lock = [IO.File]::Open((Join-Path $root '.refresh.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try { Invoke-Refresh @() $false } finally { $lock.Dispose() }
    # Fixture for a previously validated release; verify rollback swaps the active pointer.
    $prior = '0000000000000000000000000000000000000001'
    Copy-Item (Join-Path $root "releases/$($state.commit)") (Join-Path $root "releases/$prior") -Recurse
    $previous = @{ commit = $prior; ref = $Ref; autoHotkeyPath = $AutoHotkeyPath }
    $previous | ConvertTo-Json | Set-Content (Join-Path $root 'previous.json') -Encoding UTF8
    Invoke-Refresh @('-Rollback')
    $rolled = Get-Content $statePath -Raw | ConvertFrom-Json
    if ($rolled.commit -ne $prior) { throw 'Rollback did not activate previous release.' }
    Invoke-Refresh @('-Rollback')
    if ((Get-Content $statePath -Raw | ConvertFrom-Json).commit -ne $state.commit) { throw 'Rollback could not switch back.' }
    Write-Host 'PASS: install, repeated refresh, edit protection, concurrency lock, rollback.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
