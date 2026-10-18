# Patches API_Power Supply Unit.dll 1.0.0.38 and installs the guard task. Run as administrator.
#   -MsiCenterDir  MSI Center folder, if not in the default location
#   -NoGuard       patch only, do not register the scheduled task
param(
    [string]$MsiCenterDir = (Join-Path ${env:ProgramFiles(x86)} 'MSI\MSI Center'),
    [switch]$NoGuard
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-Admin

$live = Get-LiveDll $MsiCenterDir
if (-not (Test-Path -LiteralPath $live)) { throw "Not found: $live. Is the Power Supply Unit component installed? Use -MsiCenterDir if MSI Center is elsewhere." }
$liveHash = (Get-FileHash -LiteralPath $live).Hash
if ($liveHash -ne $OrigHash -and $liveHash -ne $PatchedHash) {
    $ver = (Get-Item -LiteralPath $live).VersionInfo.FileVersion
    throw "Unsupported module version $ver ($liveHash). Only 1.0.0.38 is supported; nothing was changed."
}

New-Item -ItemType Directory -Force $InstallDir | Out-Null
foreach ($f in 'common.ps1', 'guard.ps1', 'uninstall.ps1') { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination $InstallDir -Force }
Set-Content -LiteralPath (Join-Path $InstallDir 'msi-center-dir.txt') -Value $MsiCenterDir -Encoding utf8

$backup  = Join-Path $InstallDir "$DllName.orig"
$patched = Join-Path $InstallDir "$DllName.patched"

if ($liveHash -eq $OrigHash) {
    Copy-Item -LiteralPath $live -Destination $backup -Force
    $project = Join-Path $PSScriptRoot '..\patcher\patcher.csproj'
    $out = Join-Path $env:TEMP 'msi-psu-getall-fix-patcher'
    & dotnet build $project -c Release -o $out --nologo -v quiet
    if ($LASTEXITCODE -ne 0) { throw 'Patcher build failed. Is the .NET 10 SDK installed?' }
    & dotnet (Join-Path $out 'patcher.dll') $backup $patched $OrigHash
    if ($LASTEXITCODE -ne 0) { throw "Patcher failed (exit $LASTEXITCODE); nothing was changed." }
    if ((Get-FileHash -LiteralPath $patched).Hash -ne $PatchedHash) { throw 'Patched file hash differs from the expected one; nothing was changed.' }
    Replace-LiveDll $live $patched
    Write-Log 'install: patch applied'
    'Patch applied, MSI Center service restarted.'
} else {
    if (-not (Test-Path -LiteralPath $patched)) { Copy-Item -LiteralPath $live -Destination $patched }
    'Module is already patched.'
}
if (-not (Test-Path -LiteralPath $backup)) { Write-Warning "No backup of the original in $InstallDir; uninstall will not be able to restore it." }

if (-not $NoGuard) {
    $user   = "$env:USERDOMAIN\$env:USERNAME"
    $script = Join-Path $InstallDir 'guard.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
    $logon  = New-ScheduledTaskTrigger -AtLogOn -User $user
    $logon.Delay = 'PT2M'
    $daily  = New-ScheduledTaskTrigger -Daily -At '12:00'
    $settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $logon, $daily -Settings $settings -Principal $principal -Description 'Re-applies the MSI Center PSU GET_ALL fix if an update restores the original module.' -Force | Out-Null
    "Guard task '$TaskName' registered (at logon and daily). Log: $InstallDir\guard.log"
}
