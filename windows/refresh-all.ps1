# Manual updater/installer. Never scheduled and never called by a refresh timer.
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Trigger Search'),
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')][string]$Ref = '',
    [string]$AutoHotkeyPath = '',
    [switch]$Rollback,
    [switch]$StartOnly,
    [switch]$ValidateOnly,
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$allowed = @(
    'windows/autocomplete.ahk', 'windows/refresh-all.ps1',
    'automations/advancedmd/follow-up-office.ahk',
    'automations/advancedmd/follow-up-tele.ahk',
    'automations/advancedmd/intake-office.ahk',
    'automations/dell/helpers.ahk'
)
function Read-State([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    return $null
}
function Get-ReleasePath([string]$Commit) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'Invalid saved commit.' }
    return Join-Path $InstallRoot "releases\$Commit"
}
function Test-Release([string]$Directory) {
    $manifest = Get-Content -LiteralPath (Join-Path $Directory 'windows/release-manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or @($manifest.files).Count -lt 5 -or @($manifest.files).Count -gt $allowed.Count) { throw 'Unexpected release manifest.' }
    $seen = @{}
    foreach ($file in $manifest.files) {
        if ($file.path -cnotin $allowed -or $seen.ContainsKey($file.path) -or $file.sha256 -notmatch '^[0-9a-f]{64}$') {
            throw 'Unapproved or duplicate release file.'
        }
        $seen[$file.path] = $true
        $path = Join-Path $Directory $file.path
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.sha256) {
            throw "Release hash mismatch: $($file.path). Local edits are preserved; no files were replaced."
        }
    }
    foreach ($required in $allowed | Where-Object { $_ -ne 'automations/dell/helpers.ahk' }) {
        if (-not $seen.ContainsKey($required)) { throw 'Required release file is missing.' }
    }
}
function Invoke-AhkCheck([string]$Directory, [switch]$SelfTest) {
    foreach ($relative in $allowed | Where-Object { $_ -like '*.ahk' -and (Test-Path -LiteralPath (Join-Path $Directory $_)) }) {
        $path = Join-Path $Directory $relative
        $arguments = if ($SelfTest) { '"' + $path + '" --self-test' } else { '/ErrorStdOut=UTF-8 /validate "' + $path + '"' }
        $out = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.txt')
        $err = $out + '.err'
        try {
            $proc = Start-Process -FilePath $AutoHotkeyPath -ArgumentList $arguments -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
            # Cache the native handle before exit (Windows PowerShell 5.1 otherwise loses ExitCode).
            $null = $proc.Handle
            if (-not $proc.WaitForExit(30000)) { $proc.Kill(); throw "Validation timed out: $relative" }
            if ($proc.ExitCode -ne 0) {
                $detail = (Get-Content $out, $err -Raw -ErrorAction SilentlyContinue) -join "`n"
                throw "Validation failed: $relative (exit $($proc.ExitCode))`n$detail"
            }
        } finally { Remove-Item $out, $err -Force -ErrorAction SilentlyContinue }
    }
}
function Get-ManagedProcesses {
    $prefix = [regex]::Escape((Join-Path $InstallRoot 'releases'))
    return @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine -match ($prefix + '[\\/][0-9a-f]{40}[\\/](windows[\\/]autocomplete\.ahk|automations[\\/](advancedmd|dell)[\\/][a-z-]+\.ahk)(["\s]|$)')
    })
}
function Stop-ManagedLauncher {
    $processes = @(Get-ManagedProcesses)
    if (@($processes | Where-Object { $_.CommandLine -match 'automations[\\/](advancedmd|dell)' }).Count) {
        throw 'An AdvancedMD automation is running. Wait until it finishes, then refresh again.'
    }
    foreach ($item in $processes) { Stop-Process -Id $item.ProcessId -ErrorAction Stop }
}
function Start-Release($State) {
    $directory = Get-ReleasePath $State.commit
    Test-Release $directory
    Start-Process -FilePath $AutoHotkeyPath -ArgumentList ('"' + (Join-Path $directory 'windows/autocomplete.ahk') + '"') | Out-Null
}
function Write-State($State, [string]$Path) {
    $temporary = "$Path.tmp"
    $State | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Get-RemoteFile([string]$Commit, [string]$Relative, [string]$Destination) {
    $url = "https://raw.githubusercontent.com/nathanpuls/trigger-search/$Commit/$Relative"
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -TimeoutSec 25
    if ((Get-Item -LiteralPath $Destination).Length -gt 2097152) { throw 'Unexpectedly large code file.' }
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
if ($InstallRoot.Contains('"') -or $InstallRoot.Contains("`n") -or $InstallRoot.Contains('%')) { throw 'Unsupported install path.' }
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
$lock = $null
$stage = $null
$statePath = Join-Path $InstallRoot 'current.json'
$previousPath = Join-Path $InstallRoot 'previous.json'
try {
    $lock = [IO.File]::Open((Join-Path $InstallRoot '.refresh.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $current = Read-State $statePath
    if (-not $AutoHotkeyPath -and $current) { $AutoHotkeyPath = $current.autoHotkeyPath }
    if (-not $AutoHotkeyPath) {
        $candidates = @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
        $AutoHotkeyPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $AutoHotkeyPath -or -not (Test-Path -LiteralPath $AutoHotkeyPath -PathType Leaf) -or $AutoHotkeyPath.Contains('"')) {
        throw 'AutoHotkey v2 was not found. Pass -AutoHotkeyPath with the full path to AutoHotkey64.exe.'
    }
    if ($StartOnly) {
        if (-not $current) { throw 'No installed release. Run Refresh-All.cmd first.' }
        Start-Release $current
        return
    }
    if ($Rollback) {
        $previous = Read-State $previousPath
        if (-not $previous -or -not $current) { throw 'No previous release is available.' }
        $directory = Get-ReleasePath $previous.commit
        Test-Release $directory
        Invoke-AhkCheck $directory
        Invoke-AhkCheck $directory -SelfTest
        Stop-ManagedLauncher
        Write-State $previous $statePath
        Write-State $current $previousPath
        Copy-Item -LiteralPath (Join-Path $directory 'windows/refresh-all.ps1') -Destination (Join-Path $InstallRoot 'refresh-all.ps1') -Force
        if (-not $NoStart) { Start-Release $previous }
        Write-Host "Rolled back to $($previous.commit)."
        return
    }
    if (-not $Ref) { $Ref = if ($current) { $current.ref } else { 'main' } }
    if ($current) { Test-Release (Get-ReleasePath $current.commit) }
    $encodedRef = [uri]::EscapeDataString($Ref)
    $metadata = Invoke-RestMethod -Uri "https://api.github.com/repos/nathanpuls/trigger-search/commits/$encodedRef" -Headers @{ 'User-Agent' = 'Trigger-Search-Manual-Refresh' } -TimeoutSec 25
    $commit = [string]$metadata.sha
    $release = Get-ReleasePath $commit
    $stage = Join-Path $InstallRoot ('staging-' + [guid]::NewGuid().ToString())
    Get-RemoteFile $commit 'windows/release-manifest.json' (Join-Path $stage 'windows/release-manifest.json')
    # Validate allowed paths before downloading anything named by a manifest.
    $manifest = Get-Content (Join-Path $stage 'windows/release-manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or @($manifest.files).Count -lt 5 -or @($manifest.files).Count -gt $allowed.Count) { throw 'Unexpected release manifest.' }
    foreach ($file in $manifest.files) {
        if ($file.path -cnotin $allowed) { throw 'Manifest requested an unapproved file.' }
        Get-RemoteFile $commit $file.path (Join-Path $stage $file.path)
    }
    Test-Release $stage
    Invoke-AhkCheck $stage
    Invoke-AhkCheck $stage -SelfTest
    if ($ValidateOnly) { Write-Host "Validated release $commit. Installation unchanged."; return }
    if (Test-Path -LiteralPath $release) { Test-Release $release }
    else {
        New-Item -ItemType Directory -Path (Split-Path $release) -Force | Out-Null
        Move-Item -LiteralPath $stage -Destination $release
        $stage = $null
    }
    $next = [ordered]@{ commit = $commit; ref = $Ref; autoHotkeyPath = $AutoHotkeyPath }
    Stop-ManagedLauncher
    try {
        if ($current -and $current.commit -ne $commit) { Write-State $current $previousPath }
        Write-State $next $statePath
        # Stable shortcuts keep working when switching releases. All code remains under releases/.
        $bootstrap = '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0refresh-all.ps1" -InstallRoot "%~dp0."'
        Set-Content -LiteralPath (Join-Path $InstallRoot 'Refresh-All.cmd') -Value ($bootstrap + "`r`npause") -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $InstallRoot 'Start-Trigger-Search.cmd') -Value ($bootstrap + ' -StartOnly') -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $InstallRoot 'Rollback.cmd') -Value ($bootstrap + " -Rollback`r`npause") -Encoding ASCII
        Copy-Item -LiteralPath (Join-Path $release 'windows/refresh-all.ps1') -Destination (Join-Path $InstallRoot 'refresh-all.ps1') -Force
        if (-not $NoStart) { Start-Release $next }
    } catch {
        if ($current) {
            Write-State $current $statePath
            if (-not $NoStart) { Start-Release $current }
        } else { Remove-Item -LiteralPath $statePath -ErrorAction SilentlyContinue }
        throw
    }
    Write-Host "Trigger Search ready: $commit"
    Write-Host 'Snippets/configuration are unchanged. Code updates run only when you request them.'
} catch {
    Write-Error $_
    exit 1
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if ($lock) { $lock.Dispose() }
}
