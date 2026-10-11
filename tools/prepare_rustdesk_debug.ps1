$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
& python (Join-Path $projectRoot 'tools\verify_remote_runtime.py')
if ($LASTEXITCODE -ne 0) { throw 'The packaged native engines failed verification.' }
Write-Output 'Localist builds use the verified embedded runtime. No external client download or installation is needed.'