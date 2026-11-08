param([string]$Compiler)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$spec = Get-Content -LiteralPath (Join-Path $project 'pubspec.yaml') -Raw
if ($spec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)') { throw 'Missing version' }
$version = $Matches[1]
$build = [int]$Matches[2]
$product = 'Localist'
$exe = 'Localist.exe'
$appId = 'PRS.Localist.Windows.InstallerQA'
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${appId}_is1"
$appKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Localist-InstallerQA.exe'
if (Test-Path -LiteralPath $uninstallKey) { throw 'Existing QA installation left untouched.' }
$relative = 'build/windows-setup-test-' + [guid]::NewGuid().ToString('N')
$root = Join-Path $project $relative
$payload = Join-Path $root 'payload'
$destination = Join-Path $root 'نصب آزمایشی با فاصله'
New-Item -ItemType Directory -Path (Join-Path $payload 'data') -Force | Out-Null
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
function Write-Fixture([string]$Target, [string]$FileVersion) {
    $code = 'using System.Reflection; [assembly: AssemblyFileVersion("' + $FileVersion + '")] class Fixture { static void Main() {} }'
    $sourceFile = Join-Path $root 'fixture.cs'
    [IO.File]::WriteAllText($sourceFile, $code)
    & $csc /nologo /target:winexe /platform:x64 "/out:$Target" $sourceFile
    if ($LASTEXITCODE -ne 0) { throw 'Fixture compilation failed' }
}
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Wait-Setup([Diagnostics.Process]$Process, [string]$Stage) {
    Write-Output "SETUP_TEST_STAGE $Stage"
    if (-not $Process.WaitForExit(120000)) {
        $Process.Kill()
        throw "Installer test timed out: $Stage"
    }
    $Process.Refresh()
    $diagnostic = Join-Path $root 'output/verification-error.txt'
    if ($Process.ExitCode -ne 0 -and (Test-Path -LiteralPath $diagnostic)) { Get-Content -LiteralPath $diagnostic | Write-Output }
}
function Run-Core([string]$Name, [bool]$Success = $true) {
    $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',('/DIR="' + $destination + '"'),'/TASKS=!desktopicon',('/LOG="' + (Join-Path $root "$Name.log") + '"'))
    $process = Start-Process -FilePath $core -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Wait-Setup $process $Name
    if ($Success) { Require ($process.ExitCode -eq 0) "$Name failed: $($process.ExitCode)" }
    else { Require ($process.ExitCode -ne 0) "$Name did not reject a downgrade" }
}
Write-Fixture (Join-Path $payload $exe) "$version.$build"
foreach ($file in @('flutter_windows.dll','LocalistUpdater.exe', 'LocalistRemote.exe', 'librustdesk.dll',"LocalistCamera64-$version.$build.dll","LocalistCamera32-$version.$build.dll",'data/app.so','data/icudtl.dat')) {
    [IO.File]::WriteAllText((Join-Path $payload $file), 'installer fixture')
}
$parameters = @{ Bundle = "$relative/payload"; Output = "$relative/output"; Qa = $true }
if ($Compiler) { $parameters.Compiler = $Compiler }
& (Join-Path $PSScriptRoot 'Build-WindowsSetup.ps1') @parameters
$core = Join-Path $root 'core.exe'
Copy-Item -LiteralPath (Join-Path $project 'build/windows-installer-qa/install-core.exe') -Destination $core
$wrapper = Join-Path $root "output/$product-Setup-QA.exe"
$verification = Start-Process -FilePath $wrapper -ArgumentList '--verify-ui' -WindowStyle Hidden -PassThru
Wait-Setup $verification 'font, RTL, theme and rounded window'
Require ($verification.ExitCode -eq 0) 'Font, RTL, theme or native rounded-window check failed'
try {
    # Exercise the real wrapper: embedded payload extraction, hash verification,
    # child-process progress and completion, rather than the preview simulation.
    $installArguments = '--verify-install --path "' + $destination + '"'
    $process = Start-Process -FilePath $wrapper -ArgumentList $installArguments -WindowStyle Hidden -PassThru
    Wait-Setup $process 'wrapper install'
    Require ($process.ExitCode -eq 0) 'Wrapper installation failed'
    Require (Test-Path -LiteralPath (Join-Path $destination $exe)) 'Executable missing'
    Require (Test-Path -LiteralPath $uninstallKey) 'Uninstall registration missing'
    Require ((Get-ItemProperty -LiteralPath $uninstallKey).InstallLocation.TrimEnd('\') -eq $destination) 'Install location mismatch'
    $removeUi = Join-Path $destination 'MBNUninstall.exe'
    Require (Test-Path -LiteralPath $removeUi) 'Branded uninstaller missing'
    Require ((Get-ItemProperty -LiteralPath $uninstallKey).UninstallString -eq ('"' + $removeUi + '"')) 'Windows Settings must open the branded uninstaller'
    Require ((Get-ItemProperty -LiteralPath $uninstallKey).MBNUninstallCore -eq (Join-Path $destination 'unins000.exe')) 'Uninstaller core registration mismatch'
    $verification = Start-Process -FilePath $removeUi -ArgumentList '--verify-ui' -WindowStyle Hidden -PassThru
    Wait-Setup $verification 'uninstaller font, RTL, theme, rounded window and progress layout'
    Require ($verification.ExitCode -eq 0) 'Branded uninstaller UI check failed'
    Require (Test-Path -LiteralPath $appKey) 'App Paths registration missing'
    $sentinel = Join-Path $destination 'my-settings-keep.txt'
    [IO.File]::WriteAllText($sentinel, 'user-owned-file')
    Write-Fixture (Join-Path $destination $exe) "$version.0"
    Run-Core 'upgrade'
    Require (([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $destination $exe))).FileVersion -eq "$version.$build") 'Upgrade did not replace old version'
    Remove-Item -LiteralPath (Join-Path $destination 'data/app.so')
    Run-Core 'repair'
    Require (Test-Path -LiteralPath (Join-Path $destination 'data/app.so')) 'Repair did not restore missing file'
    Require ((Get-Content -LiteralPath $sentinel -Raw) -eq 'user-owned-file') 'Update changed user file'
    Write-Fixture (Join-Path $destination $exe) '99.0.0.0'
    $before = (Get-FileHash -LiteralPath (Join-Path $destination $exe)).Hash
    Run-Core 'reject-downgrade' $false
    Require ((Get-FileHash -LiteralPath (Join-Path $destination $exe)).Hash -eq $before) 'Downgrade overwrote newer executable'
    # Run the actual branded UI from outside its install directory, as its
    # production launcher does, allowing Inno to remove the installed shell.
    $removeCopy = Join-Path $root 'remove-ui.exe'
    Copy-Item -LiteralPath $removeUi -Destination $removeCopy
    $registeredCore = (Get-ItemProperty -LiteralPath $uninstallKey).MBNUninstallCore
    try {
        Set-ItemProperty -LiteralPath $uninstallKey -Name MBNUninstallCore -Value $core
        $process = Start-Process -FilePath $removeCopy -ArgumentList '--verify-uninstall' -WindowStyle Hidden -PassThru
        Wait-Setup $process 'reject uninstaller outside registered install directory'
        Require ($process.ExitCode -ne 0) 'Uninstaller accepted an unrelated core executable'
        Require (Test-Path -LiteralPath (Join-Path $destination $exe)) 'Rejected removal changed the install'
    } finally {
        Set-ItemProperty -LiteralPath $uninstallKey -Name MBNUninstallCore -Value $registeredCore
    }
    $process = Start-Process -FilePath $removeCopy -ArgumentList '--verify-uninstall' -WindowStyle Hidden -PassThru
    Wait-Setup $process 'branded wrapper uninstall'
    Require ($process.ExitCode -eq 0) 'Branded uninstaller failed'
    Require (-not (Test-Path -LiteralPath $removeUi)) 'Installed uninstaller was left locked'
} finally {
    $uninstaller = Join-Path $destination 'unins000.exe'
    if ((Test-Path -LiteralPath $uninstaller) -and (Test-Path -LiteralPath $uninstallKey)) {
        $process = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -WindowStyle Hidden -PassThru
        Wait-Setup $process 'uninstall'
        Require ($process.ExitCode -eq 0) 'QA uninstall failed'
    }
}
Require (-not (Test-Path -LiteralPath (Join-Path $destination $exe))) 'Uninstall left the installed executable'
Require (-not (Test-Path -LiteralPath $uninstallKey)) 'Uninstall registration remains'
Require (-not (Test-Path -LiteralPath $appKey)) 'App Paths registration remains'
Require ((Get-Content -LiteralPath $sentinel -Raw) -eq 'user-owned-file') 'Uninstall deleted user-owned data'
Write-Output "SETUP_LIFECYCLE_OK $product : install, upgrade, repair, downgrade rejection, branded uninstall, registered removal, preserved user data, Persian path, font, RTL, colors, rounded HWND, separate percent/text"
