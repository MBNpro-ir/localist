param([Parameter(Mandatory=$true)][string]$Probe)
$ErrorActionPreference = 'Stop'
$directory = Split-Path (Resolve-Path -LiteralPath $Probe).Path -Parent
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run the isolated test once as administrator.' }
if ((Split-Path $directory -Leaf) -ne 'remote-privilege-qa') { throw 'Unexpected probe workspace' }
foreach ($case in @('legacy','upstream')) {
    $env:LOCALIST_PRIVILEGE_REPORT = Join-Path $directory "$case.json"
    $arguments = if ($case -eq 'legacy') { @('--localist-host','--no-server') } else { @('--noinstall','--no-server') }
    $process = Start-Process -FilePath $Probe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(35000)) { $process.Kill(); throw "Probe timed out: $case" }
    if ($process.ExitCode -ne 0) { throw "Native privilege probe failed: $case ($($process.ExitCode))" }
}
[IO.File]::WriteAllText((Join-Path $directory 'privilege-test-complete.txt'), 'PRIVILEGE_TEST_OK')
