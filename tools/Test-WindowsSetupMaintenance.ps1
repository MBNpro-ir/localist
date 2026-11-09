param([Parameter(Mandatory=$true)][string]$Compiler)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$relative = '.runlogs/capture-setup-fix/setup'
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
    $code = 'using System; using System.IO; using System.Reflection; [assembly: AssemblyFileVersion("' + $Version + '")] class Fixture { static void Main(string[] a) { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"launched-by-updater.txt"),string.Join(" ",a)); } }'
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
foreach ($arch in @(32,64)) { foreach ($slot in @('','-2','-3','-4')) { [IO.File]::WriteAllText((Join-Path $payload "LocalistCamera$arch$slot-$version.$build.dll"),'fixture') } }
& (Join-Path $PSScriptRoot 'Build-WindowsSetup.ps1') -Qa -Compiler $Compiler -Bundle "$relative/payload" -Output "$relative/output"
$core = Join-Path $project 'build/windows-installer-qa/install-core.exe'
$wrapper = Join-Path $root 'output/Localist-Setup-QA.exe'
$sentinel = Join-Path $destination 'user-owned.keep'
try {
    Execute $core @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',('/DIR="'+$destination+'"'),'/TASKS=!desktopicon')
    [IO.File]::WriteAllText($sentinel,'preserve-user-data')
    Fixture (Join-Path $destination 'Localist.exe') "$version.0"
    Execute $wrapper @('--silent-update','--path',('"'+$destination+'"'))
    Require (([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $destination 'Localist.exe'))).FileVersion -eq "$version.$build") 'Setup maintenance did not upgrade'
    Remove-Item -LiteralPath (Join-Path $destination 'data/app.so')
    Execute $wrapper @('--silent-update','--path',('"'+$destination+'"'))
    Require (Test-Path -LiteralPath (Join-Path $destination 'data/app.so')) 'Repair did not restore payload'
    $download = Join-Path $root "Localist-Windows-Setup-x64-$version.exe"
    $launchMarker = Join-Path $destination 'launched-by-updater.txt'
    if (Test-Path -LiteralPath $launchMarker) { Remove-Item -LiteralPath $launchMarker }
    Copy-Item -LiteralPath $wrapper -Destination $download -Force
    $waiter = Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList '-NoProfile -NonInteractive -Command Start-Sleep -Seconds 30' -WindowStyle Hidden -PassThru
    $native = Join-Path $project 'build/windows-capture-receiver-qa/runner/Release/LocalistUpdater.exe'
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
    Fixture (Join-Path $destination 'Localist.exe') '99.0.0.0'
    Execute $wrapper @('--silent-update','--path',('"'+$destination+'"')) $false
    Require (([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $destination 'Localist.exe'))).FileVersion -eq '99.0.0.0') 'Downgrade changed installed version'
} finally {
    $uninstaller = Join-Path $destination 'unins000.exe'
    if ((Test-Path -LiteralPath $registry) -and (Test-Path -LiteralPath $uninstaller)) { Execute $uninstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') }
}
Require (-not (Test-Path -LiteralPath $registry)) 'QA uninstall registry remained'
Require ((Get-Content -LiteralPath $sentinel -Raw) -eq 'preserve-user-data') 'Uninstall removed user data'
Write-Output 'SETUP_MAINTENANCE_OK: real install, headless Setup update, repair, native updater handoff/relaunch, downgrade rejection, uninstall and user data preservation'
