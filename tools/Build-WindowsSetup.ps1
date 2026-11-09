param(
    [string]$Bundle = 'build/windows/x64/runner/Release',
    [string]$Output = 'release-assets',
    [string]$Compiler,
    [switch]$Qa
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$bundlePath = (Resolve-Path -LiteralPath (Join-Path $project $Bundle)).Path
$outputPath = [IO.Path]::GetFullPath((Join-Path $project $Output))
$source = Join-Path $project 'windows/installer'
$spec = Get-Content -LiteralPath (Join-Path $project 'pubspec.yaml') -Raw
if ($spec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)') { throw 'Version metadata missing' }
$version = $Matches[1]
$build = [int]$Matches[2]
$product = 'Localist'
$exe = 'Localist.exe'
$otherExe = 'mbnime.exe'
$appId = 'PRS.Localist.Windows'
$displayName = 'Localist'
$registryExe = $exe
$accent = '#9DCCFF'
# Production packages contain the unmodified signed vendor driver.
# QA Setup is a separate installer identity and never installs system devices.
if (-not $Qa) {
    & (Join-Path $PSScriptRoot 'Verify-VbCablePackage.ps1') -Package (Join-Path $bundlePath 'drivers/VBCABLE')
}
if ($Qa) { $appId += '.InstallerQA'; $displayName += ' Installer QA'; $registryExe = "$product-InstallerQA.exe" }
foreach ($required in @($exe, 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'LocalistUpdater.exe', 'LocalistRemote.exe', 'librustdesk.dll', "LocalistCamera64-$version.$build.dll", "LocalistCamera32-$version.$build.dll")) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundlePath $required))) { throw "Bundle missing: $required" }
}
foreach ($arch in @(32, 64)) {
    foreach ($slotSuffix in @('', '-2', '-3', '-4')) {
        $camera = "LocalistCamera$arch$slotSuffix-$version.$build.dll"
        if (-not (Test-Path -LiteralPath (Join-Path $bundlePath $camera))) { throw "Bundle missing: $camera" }
    }
}
if ((Get-FileHash -LiteralPath (Join-Path $bundlePath $exe)).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $bundlePath 'LocalistRemote.exe')).Hash) {
    throw 'Remote IPC requires byte-identical main and helper executables.'
}
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$stage = Join-Path $project 'build/windows-installer'
if ($Qa) { $stage += '-qa' }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

if (-not $Compiler -and $env:LOCALIST_INNO_COMPILER) { $Compiler = $env:LOCALIST_INNO_COMPILER }
if (-not $Compiler) {
    $toolsRoot = if ($env:MBN_BUILD_TOOLS) { $env:MBN_BUILD_TOOLS } else { Join-Path $project '.ci-cache/build-tools' }
    $toolRoot = Join-Path $toolsRoot 'Inno-7.1.0'
    $Compiler = Join-Path $toolRoot 'compiler/ISCC.exe'
    if (-not (Test-Path -LiteralPath $Compiler)) {
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
        $package = Join-Path $toolRoot 'innosetup-7.1.0-x64.exe'
        Invoke-WebRequest -Uri 'https://github.com/jrsoftware/issrc/releases/download/is-7_1_0/innosetup-7.1.0-x64.exe' -OutFile $package
        if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne '0362A383ED217D4C4239B5933866DD96D3EB2102737DA92F80F6057A4B40DF2F') { throw 'Inno compiler digest mismatch' }
        $signature = Get-AuthenticodeSignature -LiteralPath $package
        if ($signature.Status -ne 'Valid') { throw 'Inno compiler signature invalid' }
        $install = Start-Process -FilePath $package -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',('/DIR="' + (Join-Path $toolRoot 'compiler') + '"')) -WindowStyle Hidden -Wait -PassThru
        if ($install.ExitCode -ne 0) { throw 'Compiler installation failed' }
    }
}
$parts = $version.Split('.') | ForEach-Object { [int]$_ }
$versionHigh = $parts[0] * 65536 + $parts[1]
$versionLow = $parts[2] * 65536 + $build
$icon = Join-Path $project 'windows/runner/resources/app_icon.ico'
$qaValue = if ($Qa) { 'true' } else { 'false' }
$framework = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$csc = Join-Path $framework 'csc.exe'
$references = @('System.dll', 'System.Core.dll', 'System.Xaml.dll', 'WPF/WindowsBase.dll', 'System.Windows.Forms.dll', 'System.Drawing.dll', 'WPF/PresentationCore.dll', 'WPF/PresentationFramework.dll') | ForEach-Object { '/reference:' + (Join-Path $framework $_) }
function Build-Shell([string]$Target, [bool]$Uninstaller, [string]$Payload, [string]$Digest) {
    $removeValue = if ($Uninstaller) { 'true' } else { 'false' }
    $title = if ($Uninstaller) { "$product Uninstall" } else { "$product Setup" }
    $config = @"
using System.Reflection;
[assembly: AssemblyTitle("$title")]
[assembly: AssemblyProduct("$product")]
[assembly: AssemblyCompany("MBN")]
[assembly: AssemblyVersion("$version.$build")]
[assembly: AssemblyFileVersion("$version.$build")]
namespace MbnSetup { internal static class Config {
 public const string Product = "$product", DisplayName = "$displayName", Version = "$version", NumericVersion = "$version.$build";
 public const string AppId = "$appId", Executable = "$exe", RegistryExe = "$registryExe", OtherExecutable = "$otherExe";
 public const string Accent = "$accent", PayloadHash = "$Digest";
 public static readonly bool IsUninstaller = $removeValue;
 public static readonly bool IsQa = $qaValue;
} }
"@
    $configPath = Join-Path $stage "Config-$removeValue.cs"
    [IO.File]::WriteAllText($configPath, $config, [Text.UTF8Encoding]::new($false))
    $resources = @(
        ('/resource:' + (Join-Path $source 'Setup.xaml') + ',MBN.Layout'),
        ('/resource:' + (Join-Path $project 'ico/logo.png') + ',MBN.Logo')
    )
    if ($Payload) { $resources += '/resource:' + $Payload + ',MBN.Payload' }
    foreach ($weight in @('Regular','Medium','Bold')) { $resources += '/resource:' + (Join-Path $project "windows/installer/fonts/Vazirmatn-$weight.ttf") + ',MBN.Font.' + $weight }
    $manifest = Join-Path $source 'setup.manifest'
    if ($Qa) {
        $manifest = Join-Path $stage 'qa.manifest'
        [IO.File]::WriteAllText($manifest, (Get-Content -LiteralPath (Join-Path $source 'setup.manifest') -Raw).Replace('requireAdministrator', 'asInvoker'), [Text.UTF8Encoding]::new($false))
    }
    & $csc /nologo /target:winexe /platform:x64 /optimize+ /utf8output ("/out:$Target") ("/win32icon:$icon") ("/win32manifest:" + $manifest) @references @resources (Join-Path $source 'Setup.cs') $configPath
    if ($LASTEXITCODE -ne 0) { throw 'Persian maintenance shell compilation failed' }
}
$uninstallShell = Join-Path $stage 'MBNUninstall.exe'
Build-Shell $uninstallShell $true '' ''
$defines = @("/DProduct=$product", "/DDisplayName=$displayName", "/DVersion=$version", "/DBuildNumber=$build", "/DAppId=$appId", "/DExecutable=$exe", "/DRegistryExe=$registryExe", "/DBundleDir=$bundlePath", "/DOutputDir=$stage", "/DIconFile=$icon", "/DVersionHigh=$versionHigh", "/DVersionLow=$versionLow", "/DUninstallShell=$uninstallShell")
$defines += if ($Qa) { '/DIsQa=1' } else { '/DIsQa=0' }
& $Compiler @defines (Join-Path $source 'Installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer core compilation failed' }
$core = Join-Path $stage 'install-core.exe'
$digest = (Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash.ToLowerInvariant()
$filename = "$product-Windows-Setup-x64-$version.exe"
if ($Qa) { $filename = "$product-Setup-QA.exe" }
$target = Join-Path $outputPath $filename
Build-Shell $target $false $core $digest
$checksum = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($target + '.sha256', "$checksum  $filename`n", [Text.UTF8Encoding]::new($false))
Write-Output "SETUP_READY $target"
