# Removes the guard task, restores the original module and deletes the install folder. Run as administrator.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Admin

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
$cfg = Join-Path $InstallDir 'msi-center-dir.txt'
$MsiCenterDir = if (Test-Path -LiteralPath $cfg) { (Get-Content -LiteralPath $cfg -TotalCount 1).Trim() } else { Join-Path ${env:ProgramFiles(x86)} 'MSI\MSI Center' }
$live   = Get-LiveDll $MsiCenterDir
$backup = Join-Path $InstallDir "$DllName.orig"

if ((Test-Path -LiteralPath $live) -and (Get-FileHash -LiteralPath $live).Hash -eq $PatchedHash) {
    if (-not (Test-Path -LiteralPath $backup) -or (Get-FileHash -LiteralPath $backup).Hash -ne $OrigHash) {
        throw "Backup $backup is missing or not the original 1.0.0.38. Reinstall the Power Supply Unit component from MSI Center to restore it."
    }
    Replace-LiveDll $live $backup
    'Original module restored, MSI Center service restarted.'
} else {
    'Live module is not the patched one; left unchanged.'
}
Set-Location $env:TEMP
Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
'Guard task and install folder removed.'
