param(
    [string]$Cargo = '',
    [Parameter(Mandatory = $true)][string]$VcpkgRoot,
    [string]$SourceRoot = 'C:\dev\localist-native-source',
    [string]$LibClangPath = '',
    [string]$Proxy = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$packageRoot = Join-Path $projectRoot 'third_party\localist_remote'
$sourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
if (!$Cargo) { $Cargo = (Get-Command cargo -ErrorAction Stop).Source }
if (!(Test-Path -LiteralPath (Join-Path $VcpkgRoot 'vcpkg.exe'))) {
    throw 'VcpkgRoot must contain an initialized vcpkg checkout.'
}
if ($sourceRoot.Contains(' ') -or $VcpkgRoot.Contains(' ')) {
    throw 'Use short paths without spaces for SourceRoot and VcpkgRoot (a junction is supported).'
}
New-Item -ItemType Directory -Force -Path $sourceRoot | Out-Null
& tar.exe -xzf (Join-Path $packageRoot 'native-source.tar.gz') -C $sourceRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the corresponding native source.' }
$engineSource = Join-Path $sourceRoot 'native-source'
$env:VCPKG_ROOT = (Resolve-Path -LiteralPath $VcpkgRoot).Path
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
if ($LibClangPath) { $env:LIBCLANG_PATH = $LibClangPath }
if ($Proxy) {
    $env:HTTP_PROXY = $Proxy
    $env:HTTPS_PROXY = $Proxy
    $env:CARGO_HTTP_PROXY = $Proxy
    $env:CARGO_HTTP_MULTIPLEXING = 'false'
}
Push-Location $engineSource
try {
    & (Join-Path $env:VCPKG_ROOT 'vcpkg.exe') install --triplet x64-windows-static --host-triplet x64-windows-static "--x-install-root=$env:VCPKG_ROOT\installed"
    if ($LASTEXITCODE -ne 0) { throw 'Native codec dependencies did not build.' }
    # Software capture remains portable across Windows machines. Hardware
    # codec support is an optional upstream accelerator and is packaged on
    # Android; keeping this DLL software-only avoids the MSVC CRT mismatch
    # caused by the upstream AMF/NVENC static libraries.
    & $Cargo build --locked --lib --release --features flutter
    if ($LASTEXITCODE -ne 0) { throw 'The native engine did not build.' }
    Copy-Item -LiteralPath 'target\release\librustdesk.dll' -Destination (Join-Path $packageRoot 'windows\runtime\librustdesk.dll') -Force
} finally {
    Pop-Location
}
Write-Output 'Built the embedded Windows engine. Refresh UPSTREAM.json hashes before packaging.'
