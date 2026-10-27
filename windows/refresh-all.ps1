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
    [switch]$InstallOriginalControls,
    [ValidateSet('ON', 'OFF')][string]$OriginalScriptsMode = '',
    [ValidateSet('zoom.join')][string]$Automation = '',
    [switch]$ReadAutomationFormatting,
    [ValidatePattern('^[A-Za-z0-9_-]{20,}$')][string]$FormattingSheetId = '',
    [string]$FormattingOutput = '',
    [string]$FormattingWorkbook = ''
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
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Get-RemoteFile([string]$Commit, [string]$Relative, [string]$Destination) {
    $url = "https://raw.githubusercontent.com/nathanpuls/trigger-search/$Commit/$Relative"
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -TimeoutSec 25
    if ((Get-Item -LiteralPath $Destination).Length -gt 2097152) { throw 'Unexpectedly large code file.' }
}
# Backup controls are local and independent of the running Trigger Search launcher.
function Initialize-OriginalNative {
    if (-not ('TriggerOriginalNative' -as [type])) {
        Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class TriggerOriginalNative {
    [DllImport("shell32.dll", SetLastError=true)] static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string text, out int count);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr ptr);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern uint GetLongPathName(string path, StringBuilder buffer, uint size);
    public static string[] Split(string text) {
        int count; IntPtr ptr = CommandLineToArgvW(text, out count);
        if (ptr == IntPtr.Zero) throw new Exception("Cannot inspect a Windows command line.");
        try { string[] args = new string[count]; for (int i=0; i<count; i++) args[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(ptr, i * IntPtr.Size)); return args; }
        finally { LocalFree(ptr); }
    }
    public static string LongPath(string path) {
        var buffer = new StringBuilder(32768);
        uint length = GetLongPathName(path, buffer, (uint)buffer.Capacity);
        return length > 0 && length < buffer.Capacity ? buffer.ToString() : path;
    }
}
'@
    }
}
function Get-OriginalPath([string]$Path) {
    Initialize-OriginalNative
    return [TriggerOriginalNative]::LongPath([IO.Path]::GetFullPath($Path)).TrimEnd('\')
}
function Get-OriginalNames([switch]$Production) {
    $resident = @('blueprint.ahk', 'clipboard-special.ahk', 'copy back.ahk', 'copy paste cut etc.ahk',
        'F2-nat-enter.ahk', 'F3-charge slip.ahk', 'F4-timestamp for note.ahk', 'F8-send-schedule-for-next-day.ahk',
        'Follow Up MSE.ahk', 'follow-up-office.ahk', 'follow-up-tele.ahk', 'intake-office.ahk',
        'launch AMD.ahk', 'MSE.ahk', 'MSE2.ahk', 'open_espanso.ahk', 'pageDwn.ahk', 'sid.ahk', 'window.ahk')
    if ($Production) { return $resident }
    # OFF can also stop known old/debug/autostart copies; ON never launches them.
    # autocomplete.ahk is deliberately absent: never stop any Trigger Search copy.
    return $resident + @('copilot.ahk', 'follow up tele debug.ahk', 'follow-up-office-old.ahk',
        'follow-up-tele-old.ahk', 'fu-test - Copy.ahk', 'HPI.ahk', 'IT ticket-old.ahk',
        'IT ticket.ahk', 'Morning Start Up.ahk', 'Start_All_My_Scripts.ahk', 'test-esc.ahk')
}
function Get-OriginalPaths($Config, [switch]$Production) {
    foreach ($name in @(Get-OriginalNames -Production:$Production)) {
        $path = Join-Path $Config.folder $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Get-OriginalPath $path }
    }
}
function Get-AhkCommandScript([string]$Command) {
    if (-not $Command) { return '' }
    Initialize-OriginalNative
    $tokens = [TriggerOriginalNative]::Split($Command)
    # Inspect the script actually executed, not paths mentioned in its arguments.
    for ($i = 1; $i -lt $tokens.Length; $i++) {
        if ($tokens[$i].StartsWith('/')) {
            if ($tokens[$i] -match '(?i)^/(r|restart|f|force|ErrorStdOut(?:=.*)?|CP\d+)$') { continue }
            return '' # Unknown options may consume another path (e.g. /include).
        }
        if ($tokens[$i] -notmatch '(?i)\.ahk$' -or -not [IO.Path]::IsPathRooted($tokens[$i])) { return '' }
        return Get-OriginalPath $tokens[$i]
    }
    return ''
}
function Get-OriginalProcesses($Config) {
    $paths = @(Get-OriginalPaths $Config)
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'")) {
        $script = Get-AhkCommandScript $process.CommandLine
        if ($script -and $script -in $paths) {
            [pscustomobject]@{ Id = $process.ProcessId; Script = $script; Executable = $process.ExecutablePath }
        }
    }
}
function Get-OriginalLinks($Config, [string]$Folder = '') {
    if (-not $Folder) { $Folder = $Config.startup }
    if (-not (Test-Path -LiteralPath $Folder)) { return }
    $paths = @(Get-OriginalPaths $Config)
    $shell = New-Object -ComObject WScript.Shell
    foreach ($file in Get-ChildItem -LiteralPath $Folder -Filter '*.lnk' -File) {
        $link = $shell.CreateShortcut($file.FullName)
        $script = ''
        if ($link.TargetPath -match '(?i)\.ahk$') { $script = Get-OriginalPath $link.TargetPath }
        elseif ((Split-Path $link.TargetPath -Leaf) -match '(?i)^AutoHotkey.*\.exe$') {
            $script = Get-AhkCommandScript ('"' + $link.TargetPath + '" ' + $link.Arguments)
        }
        if ($script -in $paths) { [pscustomobject]@{ Path = $file.FullName; Script = $script } }
    }
}
function Get-OtherOriginalStartup($Config) {
    # Read-only audit. Never modify registry entries, all-users entries, or tasks.
    $folder = $Config.folder
    $knownPaths = @(Get-OriginalPaths $Config)
    $pattern = [regex]::Escape($folder)
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
        if (Test-Path $key) {
            $item = Get-Item $key
            foreach ($name in $item.GetValueNames()) {
                $value = [Environment]::ExpandEnvironmentVariables([string]$item.GetValue($name))
                # Launcher-only entries must remain outside the backup controls.
                if (($value -match $pattern -or (Get-AhkCommandScript $value) -in $knownPaths) -and (Get-AhkCommandScript $value) -ne (Join-Path $Config.folder 'autocomplete.ahk')) { "Registry: $key / $name" }
            }
        }
    }
    $common = [Environment]::GetFolderPath('CommonStartup')
    foreach ($link in @(Get-OriginalLinks $Config $common)) { 'All-users Startup: ' + (Split-Path $link.Path -Leaf) }
    foreach ($file in @(Get-ChildItem -LiteralPath $Config.startup -File | Where-Object { $_.Extension -ne '.lnk' })) {
        if ($file.Extension -in @('.cmd', '.bat', '.ps1', '.vbs')) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            if ($text -match $pattern) { 'Inspect Startup wrapper: ' + $file.Name }
        }
    }
    try {
        foreach ($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' })) {
            foreach ($action in @($task.Actions)) {
                if ($action.CimClass.CimClassName -ne 'MSFT_TaskExecAction') { continue }
                $command = [Environment]::ExpandEnvironmentVariables('"' + [string]$action.Execute + '" ' + [string]$action.Arguments)
                if (($command -match $pattern -or (Get-AhkCommandScript $command) -in $knownPaths) -and (Get-AhkCommandScript $command) -ne (Join-Path $Config.folder 'autocomplete.ahk')) { 'Scheduled task: ' + $task.TaskPath + $task.TaskName }
            }
        }
    } catch { 'Scheduled task audit unavailable; inspect Task Scheduler before using OFF.' }
}
function New-OriginalConfig([string]$Root, [string]$Folder, [string]$Startup, [string]$Ahk) {
    $folderPath = Get-OriginalPath $Folder
    $rootPath = Get-OriginalPath $Root
    if ($folderPath -eq $rootPath -or $folderPath.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Choose the ORIGINAL AutoHotkey folder, not the managed installation.'
    }
    $config = [pscustomobject]@{ schema = 1; folder = $folderPath; startup = (Get-OriginalPath $Startup); ahk = $Ahk;
        statePath = (Join-Path $Root 'original-scripts/state.json'); entries = @(); generated = @(); mode = 'Unchanged' }
    if (-not @(Get-OriginalPaths $config -Production).Count) { throw 'No recognized production scripts were found in this folder.' }
    return $config
}
function Save-OriginalConfig($Config) {
    New-Item -ItemType Directory -Path (Split-Path $Config.statePath) -Force | Out-Null
    Write-State $Config $Config.statePath
}
function Import-OriginalStartupBackup($Config, [string]$Root) {
    # 0.16.7 backups may already contain the old shortcuts. Import copies only;
    # its Trigger Search startup shortcut and journal are NEVER changed.
    $old = Read-State (Join-Path $Root 'startup-backup/state.json')
    if (-not $old -or (Get-OriginalPath $old.legacyFolder) -ne $Config.folder) { return }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($entry in @($old.entries)) {
        if (-not (Test-Path -LiteralPath $entry.backup)) { continue }
        if ((Get-FileHash -LiteralPath $entry.backup).Hash -ne $entry.hash) { throw 'An older Startup backup was edited; it was left unchanged.' }
        $link = $shell.CreateShortcut($entry.backup)
        $script = if ($link.TargetPath -match '(?i)\.ahk$') { Get-OriginalPath $link.TargetPath } elseif ((Split-Path $link.TargetPath -Leaf) -match '(?i)^AutoHotkey.*\.exe$') { Get-AhkCommandScript ('"' + $link.TargetPath + '" ' + $link.Arguments) } else { '' }
        if ($script -notin @(Get-OriginalPaths $Config)) { continue }
        $copy = Join-Path (Split-Path $Config.statePath) ([guid]::NewGuid().ToString() + '.lnk')
        Copy-Item -LiteralPath $entry.backup -Destination $copy
        $Config.entries += [pscustomobject]@{ original = $entry.original; backup = $copy; hash = $entry.hash; script = $script }
    }
}
function Save-OriginalLinks($Config) {
    foreach ($link in @(Get-OriginalLinks $Config)) {
        if ($link.Path -in @($Config.generated | ForEach-Object { $_.path })) { continue }
        $hash = (Get-FileHash -LiteralPath $link.Path).Hash
        $existing = @($Config.entries | Where-Object { $_.original -eq $link.Path })
        if ($existing.Count) {
            if ($existing[0].hash -ne $hash) { throw 'A previously saved original Startup shortcut changed. It was left unchanged.' }
        } else {
            $copy = Join-Path (Split-Path $Config.statePath) ([guid]::NewGuid().ToString() + '.lnk')
            Copy-Item -LiteralPath $link.Path -Destination $copy
            $Config.entries += [pscustomobject]@{ original = $link.Path; backup = $copy; hash = $hash; script = $link.Script }
        }
    }
    Save-OriginalConfig $Config # Backups and recovery metadata precede removals.
}
function Test-OriginalStartupState($Config) {
    foreach ($entry in @($Config.entries)) {
        if (-not (Test-Path -LiteralPath $entry.backup) -or (Get-FileHash -LiteralPath $entry.backup).Hash -ne $entry.hash) { throw 'An original Startup backup is missing or changed.' }
        if ((Test-Path -LiteralPath $entry.original) -and (Get-FileHash -LiteralPath $entry.original).Hash -ne $entry.hash) { throw 'An original Startup location is occupied by a changed shortcut. Nothing was overwritten.' }
    }
    foreach ($entry in @($Config.generated)) {
        if ((Test-Path -LiteralPath $entry.path) -and (Get-FileHash -LiteralPath $entry.path).Hash -ne $entry.hash) { throw 'A backup-mode Startup shortcut was edited. It was left unchanged.' }
    }
}
function Set-OriginalScriptsMode($Config, [ValidateSet('ON', 'OFF')][string]$Mode) {
    Save-OriginalLinks $Config
    Test-OriginalStartupState $Config
    $production = @(Get-OriginalPaths $Config -Production)
    # Check every generated destination before any Startup removal or process stop.
    foreach ($script in $production) {
        $destination = Join-Path $Config.startup ('Original Scripts - ' + [IO.Path]::GetFileNameWithoutExtension($script) + '.lnk')
        if ((Test-Path -LiteralPath $destination) -and $destination -notin @($Config.generated | ForEach-Object { $_.path }) -and $destination -notin @($Config.entries | ForEach-Object { $_.original })) {
            throw ('Startup name collision; nothing overwritten: ' + (Split-Path $destination -Leaf))
        }
    }
    if ($Mode -eq 'ON') {
        # Parse every production script without executing it before starting any.
        foreach ($script in $production) {
            $proc = New-Object Diagnostics.Process
            $proc.StartInfo.FileName = $Config.ahk
            $proc.StartInfo.Arguments = '/ErrorStdOut /validate "' + $script + '"'
            $proc.StartInfo.UseShellExecute = $false
            $proc.StartInfo.CreateNoWindow = $true
            try {
                if (-not $proc.Start()) { throw 'Could not validate an original script.' }
                if (-not $proc.WaitForExit(15000)) { $proc.Kill(); throw 'Original script validation timed out.' }
                if ($proc.ExitCode -ne 0) { throw ('Original script needs a syntax fix before ON: ' + (Split-Path $script -Leaf)) }
            } finally { $proc.Dispose() }
        }
    }
    # Keep wildcard/debug/autostart-only shortcuts disabled in BOTH modes.
    foreach ($entry in @($Config.entries)) {
        if (Test-Path -LiteralPath $entry.original) { Remove-Item -LiteralPath $entry.original }
    }
    foreach ($entry in @($Config.generated)) {
        if (Test-Path -LiteralPath $entry.path) { Remove-Item -LiteralPath $entry.path }
    }
    if ($Mode -eq 'OFF') {
        # Terminate the wildcard spawner first, then inspect live children afresh.
        foreach ($process in @(Get-OriginalProcesses $Config | Where-Object { (Split-Path $_.Script -Leaf) -eq 'Start_All_My_Scripts.ahk' })) {
            Stop-Process -Id $process.Id -ErrorAction Stop
        }
        $count = 0
        foreach ($process in @(Get-OriginalProcesses $Config)) {
            # Recheck identity immediately before termination (PID reuse protection).
            $live = Get-CimInstance Win32_Process -Filter "ProcessId = $($process.Id)" -ErrorAction Stop
            if ($live -and (Get-AhkCommandScript $live.CommandLine) -eq $process.Script) {
                Stop-Process -Id $process.Id -ErrorAction Stop
                $count++
            }
        }
        $Config.mode = 'OFF'; Save-OriginalConfig $Config
        return "Original scripts OFF. Closed $count processes; original Startup shortcuts disabled. Trigger Search was left running."
    }
    $covered = @()
    foreach ($entry in @($Config.entries | Where-Object { $_.script -in $production })) {
        Copy-Item -LiteralPath $entry.backup -Destination $entry.original
        $covered += $entry.script
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($script in $production | Where-Object { $_ -notin $covered }) {
        $name = 'Original Scripts - ' + [IO.Path]::GetFileNameWithoutExtension($script) + '.lnk'
        $destination = Join-Path $Config.startup $name
        if (Test-Path -LiteralPath $destination) { throw ('Startup name collision; nothing overwritten: ' + $name) }
        $staged = Join-Path (Split-Path $Config.statePath) ([guid]::NewGuid().ToString() + '.lnk')
        $link = $shell.CreateShortcut($staged); $link.TargetPath = $Config.ahk
        $link.Arguments = '"' + $script + '"'; $link.WorkingDirectory = $Config.folder; $link.Save()
        $record = [pscustomobject]@{ path = $destination; hash = (Get-FileHash -LiteralPath $staged).Hash }
        $Config.generated = @($Config.generated | Where-Object { $_.path -ne $destination }) + $record
        Save-OriginalConfig $Config
        Move-Item -LiteralPath $staged -Destination $destination
    }
    $started = 0
    foreach ($script in $production) {
        if ($script -notin @(Get-OriginalProcesses $Config | ForEach-Object { $_.Script })) {
            Start-Process -FilePath $Config.ahk -ArgumentList ('"' + $script + '"') -WorkingDirectory $Config.folder | Out-Null
            $started++
        }
    }
    $Config.mode = 'ON'; Save-OriginalConfig $Config
    return "Original scripts ON. Started $started production scripts; production Startup restored. Trigger Search is still running; duplicate hotkeys may compete."
}
function Install-OriginalControls([string]$Root, [string]$Ahk) {
    Add-Type -AssemblyName System.Windows.Forms
    $statePath = Join-Path $Root 'original-scripts/state.json'
    $config = Read-State $statePath
    if (-not $config) {
        $folder = 'C:\Users\NathanPuls\OneDrive - LifeStance Health\Documents\AutoHotkey'
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            $picker = New-Object Windows.Forms.FolderBrowserDialog
            $picker.Description = 'The saved Dell AutoHotkey folder was not found. Select its current location.'
            $picker.ShowNewFolderButton = $false
            if ($picker.ShowDialog() -ne 'OK') { $picker.Dispose(); return }
            $folder = $picker.SelectedPath; $picker.Dispose()
        }
        $config = New-OriginalConfig $Root $folder ([Environment]::GetFolderPath('Startup')) $Ahk
        New-Item -ItemType Directory -Path (Split-Path $statePath) -Force | Out-Null
        Import-OriginalStartupBackup $config $Root
    }
    $processes = @(Get-OriginalProcesses $config)
    $links = @(Get-OriginalLinks $config)
    $other = @(Get-OtherOriginalStartup $config)
    $text = "Install Original Scripts ON and OFF in:`n$($config.folder)`n`nLive original processes: $($processes.Count)`n" +
        (($processes | ForEach-Object { (Split-Path $_.Script -Leaf) + ' (PID ' + $_.Id + ')' }) -join ", ") +
        "`n`nMatching Startup shortcuts:`n" + (($links | ForEach-Object { Split-Path $_.Path -Leaf }) -join ", ") +
        "`n`nON will launch these production scripts and enable their Startup shortcuts:`n" + ((Get-OriginalPaths $config -Production | ForEach-Object { Split-Path $_ -Leaf }) -join ", ") +
        "`n`nON can cause duplicate hotkeys. OFF can interrupt an original automation. Trigger Search and its startup are never changed."
    if ($other.Count) { $text += "`n`nAdditional startup paths need inspection before either control can run:`n" + ($other -join "`n") }
    if ([Windows.Forms.MessageBox]::Show($text, 'Original Scripts controls - review Dell audit', 'OKCancel', 'Question') -ne 'OK') { return }
    $controller = Join-Path $Root 'Original-Scripts-Control.ps1'
    $shell = New-Object -ComObject WScript.Shell
    # Never overwrite an existing file with the requested names unless it is ours.
    foreach ($mode in @('ON', 'OFF')) {
        $file = Join-Path $config.folder ("Original Scripts $mode.lnk")
        if (Test-Path -LiteralPath $file) {
            $existing = $shell.CreateShortcut($file)
            $expected = '-NoProfile -ExecutionPolicy Bypass -File "' + $controller + '" -InstallRoot "' + $Root + '" -OriginalScriptsMode ' + $mode
            if ($existing.Arguments -ne $expected -or (Split-Path $existing.TargetPath -Leaf) -ne 'powershell.exe') { throw 'A control-named file already exists; it was not replaced.' }
        }
    }
    Copy-Item -LiteralPath $PSCommandPath -Destination $controller -Force
    Save-OriginalConfig $config
    foreach ($mode in @('ON', 'OFF')) {
        $link = $shell.CreateShortcut((Join-Path $config.folder ("Original Scripts $mode.lnk")))
        $link.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $controller + '" -InstallRoot "' + $Root + '" -OriginalScriptsMode ' + $mode
        $link.WorkingDirectory = $config.folder; $link.WindowStyle = 7; $link.Save()
    }
    [Windows.Forms.MessageBox]::Show('Two controls installed in the original folder. No scripts or Startup entries have been changed. Double-click OFF to disable the originals, or ON to enable production scripts now and at sign-in.', 'Original Scripts controls') | Out-Null
}
function Invoke-OriginalControl([string]$Root, [string]$Mode) {
    Add-Type -AssemblyName System.Windows.Forms
    $config = Read-State (Join-Path $Root 'original-scripts/state.json')
    if (-not $config -or $config.schema -ne 1) { throw 'Install the Original Scripts ON/OFF controls first.' }
    $other = @(Get-OtherOriginalStartup $config)
    if ($other.Count) { throw ("No scripts were changed. Inspect these additional startup paths first; the controls will not modify them:`n" + ($other -join "`n")) }
    if ($Mode -eq 'ON' -and [Windows.Forms.MessageBox]::Show('Enable original production scripts now and at Windows sign-in? Trigger Search stays running. Duplicate hotkeys may compete while both are enabled.', 'Original Scripts ON', 'YesNo', 'Warning') -ne 'Yes') { return }
    $message = Set-OriginalScriptsMode $config $Mode
    [Windows.Forms.MessageBox]::Show($message, 'Original Scripts ' + $Mode) | Out-Null
}


# Read-only formatting bridge. Excel/Office and Google credentials are not used.
function Read-AutomationFormatting([string]$Book, [string]$SheetIdentity, [string]$Output) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $download = ''
    if (-not $Book) {
        $download = Join-Path ([IO.Path]::GetTempPath()) ('trigger-format-' + [guid]::NewGuid().ToString('N') + '.xlsx')
        $Book = $download
        try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 15 -Uri ("https://docs.google.com/spreadsheets/d/$SheetIdentity/export?format=xlsx&cacheBust=$([DateTime]::UtcNow.Ticks)") -Headers @{"Cache-Control"="no-cache"} -OutFile $Book }
        catch {
            if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
            throw
        }
    }
    $zip = $null
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Book)
        function Read-ZipXml([string]$Name) {
            $entry = $zip.GetEntry($Name)
            if (-not $entry) { throw 'Workbook formatting is incomplete.' }
            if ($entry.Length -gt 20000000) { throw 'Workbook formatting entry is too large.' }
            $reader = [IO.StreamReader]::new($entry.Open())
            try {
                $settings = [Xml.XmlReaderSettings]::new()
                $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
                $settings.XmlResolver = $null
                $xmlReader = [Xml.XmlReader]::Create($reader, $settings)
                try { $doc = [Xml.XmlDocument]::new(); $doc.XmlResolver = $null; $doc.Load($xmlReader); return ,$doc }
                finally { $xmlReader.Dispose() }
            } finally { $reader.Dispose() }
        }
        $bookXml = Read-ZipXml 'xl/workbook.xml'
        $tab = $bookXml.SelectSingleNode("//*[local-name()='sheet' and @name='Automations']")
        if (-not $tab) { throw 'Automations tab was not found in the formatting export.' }
        $relationId = $tab.GetAttribute('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
        $relations = Read-ZipXml 'xl/_rels/workbook.xml.rels'
        $target = ''
        foreach ($relation in $relations.DocumentElement.ChildNodes) {
            if ($relation.GetAttribute('Id') -eq $relationId) { $target = $relation.GetAttribute('Target'); break }
        }
        if ($target -match '^/xl/') { $target = $target.TrimStart('/') }
        elseif ($target -match '^worksheets/[^/]+\.xml$') { $target = 'xl/' + $target }
        else { throw 'Invalid automation worksheet relationship.' }
        $sheetXml = Read-ZipXml $target
        $styles = Read-ZipXml 'xl/styles.xml'
        $fonts = @($styles.SelectNodes("/*[local-name()='styleSheet']/*[local-name()='fonts']/*"))
        $formats = @($styles.SelectNodes("/*[local-name()='styleSheet']/*[local-name()='cellXfs']/*"))
        $strings = @()
        if ($zip.GetEntry('xl/sharedStrings.xml')) {
            $stringXml = Read-ZipXml 'xl/sharedStrings.xml'
            $strings = @($stringXml.SelectNodes("/*[local-name()='sst']/*[local-name()='si']"))
        }
        function Is-StrikeNode($Node) {
            if (-not $Node) { return $false }
            $value = $Node.GetAttribute('val')
            return $value -ne '0' -and $value -ne 'false'
        }
        function Read-Cell($Cell) {
            if (-not $Cell) { return @{ Text = ''; Strike = $false } }
            $payload = $null
            $type = $Cell.GetAttribute('t')
            $v = $Cell.SelectSingleNode("*[local-name()='v']")
            if ($type -eq 's' -and $v) {
                $index = [int]$v.InnerText
                if ($index -lt 0 -or $index -ge $strings.Count) { throw 'Invalid shared string.' }
                $payload = $strings[$index]
            } elseif ($type -eq 'inlineStr') { $payload = $Cell.SelectSingleNode("*[local-name()='is']") }
            $text = if ($payload) { ($payload.SelectNodes(".//*[local-name()='t']") | ForEach-Object { $_.InnerText }) -join '' } elseif ($v) { $v.InnerText } else { '' }
            $styleIndex = if ($Cell.HasAttribute('s')) { [int]$Cell.GetAttribute('s') } else { 0 }
            if ($styleIndex -ge $formats.Count) { throw 'Invalid cell style.' }
            $fontIndex = if ($formats[$styleIndex].HasAttribute('fontId')) { [int]$formats[$styleIndex].GetAttribute('fontId') } else { 0 }
            if ($fontIndex -ge $fonts.Count) { throw 'Invalid cell font.' }
            $strike = Is-StrikeNode ($fonts[$fontIndex].SelectSingleNode("*[local-name()='strike']"))
            if ($payload) {
                $runs = @($payload.SelectNodes("*[local-name()='r']"))
                if ($runs.Count) {
                    $baseStrike = $strike
                    $strike = $true
                    foreach ($run in $runs) {
                        $runText = $run.SelectSingleNode("*[local-name()='t']")
                        if (-not $runText -or -not $runText.InnerText) { continue }
                        $override = $run.SelectSingleNode("*[local-name()='rPr']/*[local-name()='strike']")
                        $runStrike = if ($override) { Is-StrikeNode $override } else { $baseStrike }
                        if (-not $runStrike) { $strike = $false; break }
                    }
                }
            }
            return @{ Text = [string]$text; Strike = [bool]$strike }
        }
        $rows = @($sheetXml.SelectNodes("//*[local-name()='sheetData']/*[local-name()='row']"))
        if (-not $rows.Count) { throw 'Automations formatting has no headers.' }
        $nameColumn = ''; $idColumn = ''
        foreach ($cell in $rows[0].ChildNodes) {
            $value = (Read-Cell $cell).Text.Trim().ToLowerInvariant()
            if ($value -eq 'name') { $nameColumn = $cell.GetAttribute('r') -replace '\d', '' }
            if ($value -eq 'script id') { $idColumn = $cell.GetAttribute('r') -replace '\d', '' }
        }
        if (-not $nameColumn -or -not $idColumn) { throw 'Automations formatting headers are invalid.' }
        $disabled = @{}
        foreach ($row in $rows | Select-Object -Skip 1) {
            $nameCell = $null; $idCell = $null
            foreach ($cell in $row.ChildNodes) {
                $column = $cell.GetAttribute('r') -replace '\d', ''
                if ($column -eq $nameColumn) { $nameCell = $cell }
                if ($column -eq $idColumn) { $idCell = $cell }
            }
            $nameValue = Read-Cell $nameCell; $idValue = Read-Cell $idCell
            $id = $idValue.Text.Trim()
            if ($id -match '^[A-Za-z0-9][A-Za-z0-9._-]+$' -and ($nameValue.Strike -or $idValue.Strike)) { $disabled[$id] = $true }
        }
        $lines = @('[formatting]', 'verified=1', "sheetId=$SheetIdentity", '[disabled]')
        $lines += @($disabled.Keys | Sort-Object | ForEach-Object { "$_=1" })
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Output))) | Out-Null
        $temporary = $Output + '.tmp'
        [IO.File]::WriteAllText($temporary, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Output -Force
    } finally {
        if ($zip) { $zip.Dispose() }
        if ($download -and (Test-Path -LiteralPath $download)) { Remove-Item -LiteralPath $download -Force }
    }
}
if ($ReadAutomationFormatting) {
    if (-not $FormattingSheetId -or -not $FormattingOutput) { throw 'Formatting requires a Sheet ID and output path.' }
    Read-AutomationFormatting $FormattingWorkbook $FormattingSheetId $FormattingOutput
    return
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
    if ($OriginalScriptsMode) { Invoke-OriginalControl $InstallRoot $OriginalScriptsMode; return }
    $current = Read-State $statePath
    if (-not $AutoHotkeyPath -and $current) { $AutoHotkeyPath = $current.autoHotkeyPath }
    if (-not $AutoHotkeyPath) {
        $candidates = @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
        $AutoHotkeyPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $AutoHotkeyPath -or -not (Test-Path -LiteralPath $AutoHotkeyPath -PathType Leaf) -or $AutoHotkeyPath.Contains('"')) {
        throw 'AutoHotkey v2 was not found. Pass -AutoHotkeyPath with the full path to AutoHotkey64.exe.'
    }
    if ($InstallOriginalControls) {
        Install-OriginalControls $InstallRoot $AutoHotkeyPath
        return
    }
    if ($Automation) {
        if (-not $current) { throw 'Install Trigger Search first.' }
        $directory = Get-ReleasePath $current.commit
        Test-Release $directory
        # Fixed dispatch only; no Sheet value is ever an executable command.
        $worker = Join-Path $directory 'automations/dell/helpers.ahk'
        Start-Process -FilePath $AutoHotkeyPath -ArgumentList ('"' + $worker + '" 0 join-zoom') | Out-Null
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
        Set-Content -LiteralPath (Join-Path $InstallRoot 'Join-Zoom.cmd') -Value ($bootstrap + ' -Automation zoom.join') -Encoding ASCII
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
    if ($InstallOriginalControls -or $OriginalScriptsMode) {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Trigger Search Startup') | Out-Null
    }
    Write-Error $_
    exit 1
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force }
    if ($lock) { $lock.Dispose() }
}
