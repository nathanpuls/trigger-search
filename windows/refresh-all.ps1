# Manual updater/installer. Never scheduled and never called by a refresh timer.
[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Trigger Search'),
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')][string]$Ref = '',
    [string]$AutoHotkeyPath = '',
    [switch]$Rollback,
    [switch]$StartOnly,
    [switch]$ValidateOnly,
    [switch]$NoStart,
    [switch]$ConfigureStartup
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
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo.FileName = $AutoHotkeyPath
        $proc.StartInfo.Arguments = $arguments
        $proc.StartInfo.UseShellExecute = $false
        $proc.StartInfo.RedirectStandardOutput = $true
        $proc.StartInfo.RedirectStandardError = $true
        try {
            # Start directly so the OS process handle is retained even for a very fast validator.
            if (-not $proc.Start()) { throw "Could not start validation: $relative" }
            $outputTask = $proc.StandardOutput.ReadToEndAsync()
            $errorTask = $proc.StandardError.ReadToEndAsync()
            if (-not $proc.WaitForExit(30000)) { $proc.Kill(); throw "Validation timed out: $relative" }
            if ($proc.ExitCode -ne 0) {
                $detail = $outputTask.Result + $errorTask.Result
                throw "Validation failed: $relative (exit $($proc.ExitCode))`n$detail"
            }
        } finally { $proc.Dispose() }
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
# These helpers touch shortcuts only. Original scripts are never moved or edited.
function Get-LegacyScriptPaths([string]$Folder) {
    $names = @('autocomplete.ahk', 'blueprint.ahk', 'clipboard-special.ahk', 'copilot.ahk',
        'copy back.ahk', 'copy paste cut etc.ahk', 'F2-nat-enter.ahk', 'F3-charge slip.ahk',
        'F4-timestamp for note.ahk', 'F8-send-schedule-for-next-day.ahk', 'Follow Up MSE.ahk',
        'follow up tele debug.ahk', 'follow-up-office-old.ahk', 'follow-up-office.ahk',
        'follow-up-tele-old.ahk', 'follow-up-tele.ahk', 'fu-test - Copy.ahk', 'HPI.ahk',
        'intake-office.ahk', 'IT ticket-old.ahk', 'IT ticket.ahk', 'launch AMD.ahk',
        'Morning Start Up.ahk', 'MSE.ahk', 'MSE2.ahk', 'open_espanso.ahk', 'pageDwn.ahk',
        'sid.ahk', 'Start_All_My_Scripts.ahk', 'test-esc.ahk', 'window.ahk')
    # WScript resolves short (8.3) directory names in shortcut targets. Include
    # its canonical spelling as well as the supplied spelling for comparisons.
    $shell = New-Object -ComObject WScript.Shell
    $probe = $shell.CreateShortcut((Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.lnk')))
    foreach ($name in $names) {
        $path = Join-Path $Folder $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $raw = $Folder.TrimEnd('\') + '\' + $name
            $raw
            $full = [IO.Path]::GetFullPath($path)
            if ($full -ne $raw) { $full }
            $probe.TargetPath = $full
            if ($probe.TargetPath -ne $full) { $probe.TargetPath }
        }
    }
}
function Test-LegacyCommand([string]$Command, [string[]]$Paths) {
    foreach ($path in $Paths) {
        # Match a complete path argument, never another folder or a filename substring.
        if ($Command -match ('(?i)(?:^|[\s"])' + [regex]::Escape($path) + '(?:"|\s*$)')) { return $true }
    }
    return $false
}
function Get-LegacyStartupLinks([string]$StartupFolder, [string[]]$Paths) {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($file in Get-ChildItem -LiteralPath $StartupFolder -Filter '*.lnk' -File) {
        $link = $shell.CreateShortcut($file.FullName)
        if ($link.TargetPath -in $Paths -or (Test-LegacyCommand $link.Arguments $Paths)) { $file.FullName }
    }
}
function Set-LauncherOnlyStartup([string]$Root, [string]$StartupFolder, [string]$LegacyFolder) {
    $journal = Join-Path $Root 'startup-backup/state.json'
    if (Test-Path -LiteralPath $journal) { return } # Never overwrite the original snapshot.
    $start = Join-Path $Root 'Start-Trigger-Search.cmd'
    if (-not (Test-Path -LiteralPath $start)) { throw 'Install Trigger Search before configuring Startup.' }
    $paths = @(Get-LegacyScriptPaths $LegacyFolder)
    if (-not $paths.Count) { throw 'No recognized Dell scripts were found in that folder.' }
    if ([IO.Path]::GetFullPath($LegacyFolder).TrimEnd('\').StartsWith([IO.Path]::GetFullPath($Root).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFullPath($LegacyFolder).TrimEnd('\') -eq [IO.Path]::GetFullPath($Root).TrimEnd('\')) {
        throw 'Select the original Dell scripts folder, not the managed Trigger Search installation.'
    }
    $managed = Join-Path $StartupFolder 'Trigger Search (managed).lnk'
    if (Test-Path -LiteralPath $managed) { throw 'A managed-named shortcut already exists. It was left unchanged.' }
    $backup = Join-Path $Root ('startup-backup/' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $entries = @(Get-LegacyStartupLinks $StartupFolder $paths | ForEach-Object {
        @{ original = $_; backup = (Join-Path $backup (Split-Path $_ -Leaf)); hash = (Get-FileHash -LiteralPath $_).Hash }
    })
    $staged = Join-Path $backup 'managed.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($staged)
    $link.TargetPath = $start
    $link.WorkingDirectory = $Root
    $link.WindowStyle = 7
    $link.Save()
    $state = @{ legacyFolder = $LegacyFolder; entries = $entries; managed = $managed; managedHash = (Get-FileHash -LiteralPath $staged).Hash }
    # Save the complete recovery plan before moving the first shortcut.
    Write-State $state $journal
    foreach ($entry in $entries) { Move-Item -LiteralPath $entry.original -Destination $entry.backup }
    Move-Item -LiteralPath $staged -Destination $managed
}
function Restore-StandaloneStartup([string]$Root) {
    $journal = Join-Path $Root 'startup-backup/state.json'
    $state = Read-State $journal
    if (-not $state) { throw 'There is no saved Startup configuration to restore.' }
    # Preflight every collision/hash before changing anything.
    if ((Test-Path -LiteralPath $state.managed) -and (Get-FileHash -LiteralPath $state.managed).Hash -ne $state.managedHash) {
        throw 'The managed Startup shortcut was edited. It was left unchanged.'
    }
    foreach ($entry in @($state.entries)) {
        if (Test-Path -LiteralPath $entry.backup) {
            if ((Test-Path -LiteralPath $entry.original) -or (Get-FileHash -LiteralPath $entry.backup).Hash -ne $entry.hash) {
                throw 'A saved Startup shortcut changed or its original location is occupied. Nothing was overwritten.'
            }
        } elseif (-not (Test-Path -LiteralPath $entry.original) -or (Get-FileHash -LiteralPath $entry.original).Hash -ne $entry.hash) {
            throw 'A saved Startup shortcut is missing or changed. Nothing was overwritten.'
        }
    }
    foreach ($entry in @($state.entries)) {
        if (Test-Path -LiteralPath $entry.backup) { Move-Item -LiteralPath $entry.backup -Destination $entry.original }
    }
    if (Test-Path -LiteralPath $state.managed) { Remove-Item -LiteralPath $state.managed }
    Move-Item -LiteralPath $journal -Destination ($journal + '.restored-' + [guid]::NewGuid().ToString())
}
function Show-StartupSetup([string]$Root) {
    Add-Type -AssemblyName System.Windows.Forms
    $journal = Join-Path $Root 'startup-backup/state.json'
    if (Test-Path -LiteralPath $journal) {
        $answer = [Windows.Forms.MessageBox]::Show('Trigger Search-only Startup is configured. Restore the previous Startup shortcuts? The originals will return at the next Windows sign-in.', 'Trigger Search Startup', 'YesNo', 'Question')
        if ($answer -eq 'Yes') {
            Restore-StandaloneStartup $Root
            [Windows.Forms.MessageBox]::Show('Previous Startup shortcuts restored. Trigger Search is still running now. No original scripts were started in this session.', 'Trigger Search Startup') | Out-Null
        }
        return
    }
    $picker = New-Object Windows.Forms.FolderBrowserDialog
    $picker.Description = 'Select the ORIGINAL Dell AutoHotkey folder (the one containing Start_All_My_Scripts.ahk).'
    $picker.ShowNewFolderButton = $false
    if ($picker.ShowDialog() -ne 'OK') { $picker.Dispose(); return }
    $folder = $picker.SelectedPath
    $picker.Dispose()
    $paths = @(Get-LegacyScriptPaths $folder)
    if (-not $paths.Count) { throw 'No recognized Dell scripts were found in that folder.' }
    $startup = [Environment]::GetFolderPath('Startup')
    $links = @(Get-LegacyStartupLinks $startup $paths)
    $processes = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'" | Where-Object {
        $_.CommandLine -and (Test-LegacyCommand $_.CommandLine $paths)
    })
    $message = "Keep Trigger Search at Windows sign-in?`n`nBack up these Startup shortcuts:`n" + (($links | ForEach-Object { Split-Path $_ -Leaf }) -join "`n") +
        "`n`nClose $($processes.Count) running original scripts from the selected folder. Finish any automation before continuing.`n`nYour scripts stay in their original folder. Use this menu again to restore the Startup shortcuts."
    if ([Windows.Forms.MessageBox]::Show($message, 'Trigger Search Startup', 'OKCancel', 'Question') -ne 'OK') { return }
    Set-LauncherOnlyStartup $Root $startup $folder
    # Stop the wildcard spawner first, then re-read so it cannot leave new children behind.
    foreach ($process in $processes | Where-Object { $_.CommandLine -match 'Start_All_My_Scripts\.ahk' }) {
        Stop-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
    }
    $failures = 0
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'")) {
        if ($process.CommandLine -and (Test-LegacyCommand $process.CommandLine $paths)) {
            try { Stop-Process -Id $process.ProcessId -ErrorAction Stop } catch { $failures++ }
        }
    }
    $common = [Environment]::GetFolderPath('CommonStartup')
    $other = if (Test-Path -LiteralPath $common) { @(Get-LegacyStartupLinks $common $paths).Count } else { 0 }
    $notice = "Trigger Search Startup shortcut added. Old user Startup shortcuts are backed up.`nOriginal scripts were left untouched."
    if ($failures) { $notice += "`n$failures original processes could not be closed. Exit their tray icons manually." }
    if ($other) { $notice += "`n$other matching all-users Startup shortcuts need administrator attention." }
    $notice += "`n`nRegistry Run entries and scheduled tasks were not changed. If originals return after sign-in, those need inspection; this setup only manages your Startup folder."
    [Windows.Forms.MessageBox]::Show($notice, 'Trigger Search Startup') | Out-Null
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
    if ($ConfigureStartup) {
        Show-StartupSetup $InstallRoot
        return
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
    if ($Ref -match '^[0-9a-f]{40}$') {
        $commit = $Ref
    } else {
        $encodedRef = [uri]::EscapeDataString($Ref)
        $metadata = Invoke-RestMethod -Uri "https://api.github.com/repos/nathanpuls/trigger-search/commits/$encodedRef" -Headers @{ 'User-Agent' = 'Trigger-Search-Manual-Refresh' } -TimeoutSec 25
        $commit = [string]$metadata.sha
    }
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
    if ($ConfigureStartup) {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Trigger Search Startup') | Out-Null
    }
    Write-Error $_
    exit 1
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if ($lock) { $lock.Dispose() }
}
