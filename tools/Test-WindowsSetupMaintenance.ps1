param(
    [Parameter(Mandatory=$true)][string]$Compiler,
    [string]$Workspace = '.runlogs/capture-setup-fix/setup',
    [string]$UpdaterBinary = 'build/windows/x64/runner/Release/LocalistUpdater.exe'
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$relative = $Workspace
$root = Join-Path $project $relative
$payload = Join-Path $root 'payload'
$destination = Join-Path $root 'نصب آزمایشی با فاصله'
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PRS.Localist.Windows.InstallerQA_is1'
if (Test-Path -LiteralPath $registry) { throw 'Existing QA install left untouched' }
$spec = Get-Content -LiteralPath (Join-Path $project 'pubspec.yaml') -Raw
if ($spec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)') { throw 'Version missing' }
$version = $Matches[1]; $build = [int]$Matches[2]
New-Item -ItemType Directory -Path (Join-Path $payload 'data') -Force | Out-Null
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
function Fixture([string]$Path, [string]$Version) {
    $source = Join-Path $root 'fixture.cs'
    $code = 'using System; using System.IO; using System.Reflection; [assembly: AssemblyFileVersion("' + $Version + '")] class Fixture { static void Main(string[] a) { var integration=Array.IndexOf(a,"--install-windows-integration")>=0; File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,integration?"integration-args.txt":"launched-by-updater.txt"),string.Join(" ",a)); } }'
    [IO.File]::WriteAllText($source,$code,[Text.UTF8Encoding]::new($false))
    & $csc /nologo /target:winexe /platform:x64 "/out:$Path" $source
    if ($LASTEXITCODE -ne 0) { throw 'Fixture compile failed' }
}
function Require([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Execute([string]$Exe,[string[]]$Arguments,[bool]$Success=$true) {
    $process = Start-Process -FilePath $Exe -ArgumentList $Arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'QA maintenance timed out' }
    $process.Refresh()
    if ($Success) { Require ($process.ExitCode -eq 0) "Maintenance failed: $($process.ExitCode)" }
    else { Require ($process.ExitCode -ne 0) 'Downgrade was not rejected' }
}
Fixture (Join-Path $payload 'Localist.exe') "$version.$build"
Copy-Item -LiteralPath (Join-Path $payload 'Localist.exe') -Destination (Join-Path $payload 'LocalistRemote.exe')
foreach ($file in @('LocalistUpdater.exe','librustdesk.dll','flutter_windows.dll','data/app.so','data/icudtl.dat')) { [IO.File]::WriteAllText((Join-Path $payload $file),'fixture') }
# Deliberately stale build-tree settings must never overwrite the user's slots.
[IO.File]::WriteAllText((Join-Path $payload 'capture-devices.ini'),"[Devices]`r`nCameras=1`r`nMicrophones=1`r`n")
foreach ($arch in @(32,64)) { foreach ($slot in @('','-2','-3','-4')) { [IO.File]::WriteAllText((Join-Path $payload "LocalistCamera$arch$slot-$version.$build.dll"),'fixture') } }
& (Join-Path $PSScriptRoot 'Build-WindowsSetup.ps1') -Qa -QaIntegrationProbe -Compiler $Compiler -Bundle "$relative/payload" -Output "$relative/output"
$core = Join-Path $project 'build/windows-installer-qa/install-core.exe'
$wrapper = Join-Path $root 'output/Localist-Setup-QA.exe'
$sentinel = Join-Path $destination 'user-owned.keep'
try {
    Execute $core @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',('/DIR="'+$destination+'"'),'/TASKS=!desktopicon','/CameraCount=4','/MicrophoneCount=3',('/CablePackages="'+(Join-Path $root 'licensed packages with spaces')+'"'))
    $firstIntegration = Get-Content -LiteralPath (Join-Path $destination 'integration-args.txt') -Raw
    Require ($firstIntegration -match '--camera-count=4 --microphone-count=3') 'Selected device counts were not expanded'
    Require ($firstIntegration.Contains((Join-Path $root 'licensed packages with spaces'))) 'Licensed package path was not expanded/quoted'
    [IO.File]::WriteAllText($sentinel,'preserve-user-data')
    $devices = Join-Path $destination 'capture-devices.ini'
    $configuration = "[Devices]`r`nCameras=4`r`nMicrophones=3`r`n"
    [IO.File]::WriteAllText($devices,$configuration)
    $oldCamera = Join-Path $destination 'LocalistCamera64-7.0.0.1.dll'
    [IO.File]::WriteAllText($oldCamera,'registered-previous-camera-module')
    Fixture (Join-Path $destination 'Localist.exe') "$version.0"
    Execute $wrapper @('--silent-update','--path',('"'+$destination+'"'))
    Require (([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $destination 'Localist.exe'))).FileVersion -eq "$version.$build") 'Setup maintenance did not upgrade'
    Require ((Get-Content -LiteralPath $devices -Raw) -eq $configuration) 'Update reset camera/microphone counts'
    Require ((Get-Content -LiteralPath (Join-Path $destination 'integration-args.txt') -Raw) -match '--camera-count=0 --microphone-count=0') 'Update did not retain integration counts'
    Require ((Get-Content -LiteralPath $oldCamera -Raw) -eq 'registered-previous-camera-module') 'Update removed previous camera module before migration'
    Remove-Item -LiteralPath (Join-Path $destination 'data/app.so')
    Execute $wrapper @('--silent-update','--path',('"'+$destination+'"'))
    Require (Test-Path -LiteralPath (Join-Path $destination 'data/app.so')) 'Repair did not restore payload'
    Require ((Get-Content -LiteralPath $devices -Raw) -eq $configuration) 'Repair reset device configuration'
    $download = Join-Path $root "Localist-Windows-Setup-x64-$version.exe"
    $launchMarker = Join-Path $destination 'launched-by-updater.txt'
    if (Test-Path -LiteralPath $launchMarker) { Remove-Item -LiteralPath $launchMarker }
    Copy-Item -LiteralPath $wrapper -Destination $download -Force
    $waiter = Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList '-NoProfile -NonInteractive -Command Start-Sleep -Seconds 30' -WindowStyle Hidden -PassThru
    $native = Join-Path $project $UpdaterBinary
    $updater = Start-Process -FilePath $native -ArgumentList @('--wait-pid',$waiter.Id,'--archive',('"'+$download+'"'),'--target',('"'+$destination+'"'),'--launch',('"'+(Join-Path $destination 'Localist.exe')+'"'),'--version',$version) -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 400
    Require (-not $updater.HasExited) 'Updater did not wait for application exit'
    $waiter.Kill(); $waiter.WaitForExit()
    Require ($updater.WaitForExit(120000)) 'Native Setup handoff timed out'
    $updater.Refresh(); Require ($updater.ExitCode -eq 0) 'Native Setup handoff failed'
    Require (-not (Test-Path -LiteralPath $download)) 'Applied Setup download not removed'
    $until = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath (Join-Path $destination 'launched-by-updater.txt')) -and [DateTime]::UtcNow -lt $until) { Start-Sleep -Milliseconds 50 }
    Require ((Get-Content -LiteralPath (Join-Path $destination 'launched-by-updater.txt') -Raw) -match $version) 'Updated application not relaunched'
    Require ((Get-Content -LiteralPath $sentinel -Raw) -eq 'preserve-user-data') 'Maintenance changed user data'
    Require (Test-Path -LiteralPath $registry) 'Setup uninstall manifest missing'
    Require ((Get-Content -LiteralPath $devices -Raw) -eq $configuration) 'Native handoff reset device configuration'
    Fixture (Join-Path $destination 'Localist.exe') '99.0.0.0'
    Execute $wrapper @('--silent-update','--path',('"'+$destination+'"')) $false
    Require (([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $destination 'Localist.exe'))).FileVersion -eq '99.0.0.0') 'Downgrade changed installed version'
} finally {
    if (Test-Path -LiteralPath $registry) {
        $uninstaller = (Get-ItemProperty -LiteralPath $registry).MBNUninstallCore
        Require ([IO.Path]::GetDirectoryName($uninstaller) -eq $destination -and
            [IO.Path]::GetFileName($uninstaller) -match '^unins\d{3}\.exe$') 'Unexpected QA uninstaller target'
        if (Test-Path -LiteralPath $uninstaller) { Execute $uninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') }
    }
}
Require (-not (Test-Path -LiteralPath $registry)) 'QA uninstall registry remained'
Require ((Get-Content -LiteralPath $sentinel -Raw) -eq 'preserve-user-data') 'Uninstall removed user data'
Write-Output 'SETUP_MAINTENANCE_OK: real install, headless Setup update, repair, native updater handoff/relaunch, preserved device counts/previous camera modules, post-install integration handoff, downgrade rejection, uninstall and user data preservation'
