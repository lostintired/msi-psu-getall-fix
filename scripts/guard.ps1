# Run by the scheduled task from the install folder.
# Patched module in place -> nothing to do. Original 1.0.0.38 back -> patch again.
# Any other version -> leave it alone and notify: MSI may have fixed the bug, or the patcher needs an update.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$MsiCenterDir = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'msi-center-dir.txt') -TotalCount 1).Trim()
$live    = Get-LiveDll $MsiCenterDir
$patched = Join-Path $PSScriptRoot "$DllName.patched"

if (-not (Test-Path -LiteralPath $live)) { Write-Log 'module not found - component removed?'; Show-Toast 'MSI PSU fix' 'Power Supply Unit module not found.'; exit 1 }
$liveHash = (Get-FileHash -LiteralPath $live).Hash

if ($liveHash -eq $PatchedHash) { Write-Log 'ok: patch in place'; exit 0 }

if ($liveHash -ne $OrigHash) {
    $ver = (Get-Item -LiteralPath $live).VersionInfo.FileVersion
    Write-Log "new module version $ver ($liveHash) - not patching"
    Show-Toast 'MSI PSU fix' "MSI updated the PSU module to $ver. Patch not applied: check whether GET_ALL errors are still logged."
    exit 2
}

if ((Get-FileHash -LiteralPath $patched).Hash -ne $PatchedHash) { Write-Log 'stored patched file is damaged'; exit 3 }
Replace-LiveDll $live $patched
Write-Log 'patch re-applied, service restarted'
Show-Toast 'MSI PSU fix' 'PSU module patch re-applied.'
exit 0
