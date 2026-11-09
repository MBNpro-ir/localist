param([Parameter(Mandatory=$true)][string]$Package, [string]$SignTool)
$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../third_party/vb_cable/package.json') -Raw | ConvertFrom-Json
foreach ($file in $manifest.files.PSObject.Properties) {
    $target = Join-Path $Package $file.Name
    if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
        (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.Value) {
        throw "Unmodified official VB-CABLE file missing or changed: $($file.Name)"
    }
}
if (-not $SignTool) {
    $SignTool = Get-ChildItem -LiteralPath (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin') -Directory |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'x64/signtool.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $SignTool) { throw 'Windows SDK SignTool is required.' }
foreach ($file in @('vbMmeCable64_win10.inf','vbaudio_cable64_win10.sys')) {
    & $SignTool verify /kp /c (Join-Path $Package 'vbaudio_cable64_win10.cat') (Join-Path $Package $file)
    if ($LASTEXITCODE -ne 0) { throw "VB-CABLE kernel signature or membership invalid: $file" }
}
Write-Output 'OFFICIAL_VB_CABLE_PACKAGE_VERIFIED'
