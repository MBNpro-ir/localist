param([Parameter(Mandatory=$true)][string]$Package, [string]$SignTool)
$ErrorActionPreference = 'Stop'
foreach ($name in @('LocalistAudio.inf', 'LocalistAudio.sys', 'localistaudio.cat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Package $name) -PathType Leaf)) {
        throw "Signed Localist microphone driver package missing: $name. Public Setup build blocked."
    }
}
if (-not $SignTool) {
    $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    $SignTool = (Get-ChildItem -LiteralPath $sdk -Directory | Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'x64/signtool.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}
if (-not $SignTool) { throw 'Windows SDK SignTool is required for production driver verification.' }
foreach ($member in @('LocalistAudio.inf', 'LocalistAudio.sys')) {
    & $SignTool verify /kp /v /c (Join-Path $Package 'localistaudio.cat') (Join-Path $Package $member)
    if ($LASTEXITCODE -ne 0) { throw "Microsoft kernel-policy signature or catalog membership invalid: $member" }
}
Write-Output 'LOCALIST_SIGNED_AUDIO_PACKAGE_OK'
