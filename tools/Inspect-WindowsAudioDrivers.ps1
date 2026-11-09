param(
    [string]$NamePattern = 'Iriun|DroidCam|VB-Audio|Virtual Audio',
    [string]$Output,
    [string]$SignTool
)
# Read-only diagnostic. Does not execute installers, import certificates, write
# registry keys, or change boot/signing policy. Optional output parent must exist.
$ErrorActionPreference = 'Stop'
if ($Output) {
    $Output = [IO.Path]::GetFullPath($Output)
    if (-not (Test-Path -LiteralPath (Split-Path $Output -Parent) -PathType Container)) {
        throw 'Create and announce the diagnostic output folder before running this tool.'
    }
}
if (-not $SignTool) {
    $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    if (Test-Path -LiteralPath $sdk) {
        $SignTool = Get-ChildItem -LiteralPath $sdk -Directory | Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64/signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
}
$services = @(Get-CimInstance Win32_SystemDriver)
$installed = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
    $_.DeviceName -match $NamePattern -and $_.DriverName
})
function SignatureInfo([string]$File) {
    $signature = Get-AuthenticodeSignature -LiteralPath $File
    [ordered]@{
        file = Split-Path $File -Leaf
        status = $signature.Status.ToString()
        publisher = $signature.SignerCertificate.Subject
        issuer = $signature.SignerCertificate.Issuer
        sha256 = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$report = foreach ($driver in $installed) {
    $service = $services | Where-Object { (Split-Path $_.PathName.Trim('"') -Leaf) -eq $driver.DriverName } | Select-Object -First 1
    $path = if ($service) { $service.PathName.Trim('"') } else { Join-Path $env:WINDIR ('System32/drivers/' + $driver.DriverName) }
    $path = $path -replace '^\\SystemRoot', $env:WINDIR
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $folder = Split-Path $path -Parent
    $catalogs = @(Get-ChildItem -LiteralPath $folder -File -Filter '*.cat' | ForEach-Object { SignatureInfo $_.FullName })
    $kernel = $null
    if ($SignTool) {
        $null = & $SignTool verify /kp $path 2>&1
        $kernel = $LASTEXITCODE -eq 0
    }
    [ordered]@{
        name = $driver.DeviceName
        version = $driver.DriverVersion
        provider = $driver.DriverProviderName
        windowsReportedSigned = [bool]$driver.IsSigned
        windowsReportedSigner = $driver.Signer
        embeddedSignature = SignatureInfo $path
        embeddedKernelPolicyValid = $kernel
        catalogs = $catalogs
        # A false embedded result alone does not reject a catalog-signed driver;
        # package verification must additionally check member hashes with /kp /c.
        embeddedCheckOnly = $true
    }
}
$json = ConvertTo-Json -InputObject @($report) -Depth 8
if ($Output) { [IO.File]::WriteAllText($Output, $json, [Text.UTF8Encoding]::new($false)) }
$json
