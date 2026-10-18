# Shared settings and helpers for install.ps1, guard.ps1 and uninstall.ps1.
$OrigHash    = 'F7833895191630412D25A9C3773284F6303AEDA8E7256689526EC4A91B0274BB'  # API_Power Supply Unit.dll 1.0.0.38
$PatchedHash = '6535FEB9E45D195A2B5243680EB369F5408349DD4CEDA9D1A1BF6A77155D2B46'
$TaskName    = 'MSI PSU GET_ALL fix guard'
$InstallDir  = Join-Path $env:ProgramFiles 'MsiPsuGetAllFix'
$DllName     = 'API_Power Supply Unit.dll'
$ServiceName = 'MSI_Center_Service'

function Get-LiveDll([string]$MsiCenterDir) { Join-Path $MsiCenterDir "Power Supply Unit\$DllName" }

function Write-Log([string]$text) {
    if (-not (Test-Path -LiteralPath $InstallDir)) { return }
    Add-Content -LiteralPath (Join-Path $InstallDir 'guard.log') -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $text" -Encoding utf8
}

function Show-Toast([string]$title, [string]$text) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$([Security.SecurityElement]::Escape($title))</text><text>$([Security.SecurityElement]::Escape($text))</text></binding></visual></toast>")
        $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch { Write-Log "toast failed: $($_.Exception.Message)" }
}

# The running MSI.CentralServer keeps the DLL loaded: it can be renamed but not overwritten.
# Rename the live file aside, put the new one in place, then restart the service so the
# server releases and reloads all components. The renamed file is removed afterwards.
function Replace-LiveDll([string]$live, [string]$source) {
    $aside = "$live.old"
    if (Test-Path -LiteralPath $aside) { Remove-Item -LiteralPath $aside -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $aside) { $aside = "$live.old-$(Get-Date -Format yyyyMMddHHmmss)" }
    Rename-Item -LiteralPath $live -NewName (Split-Path $aside -Leaf)
    Copy-Item -LiteralPath $source -Destination $live
    Stop-Service $ServiceName
    Start-Service $ServiceName
    Start-Sleep -Seconds 15
    Remove-Item -LiteralPath $aside -Force -ErrorAction SilentlyContinue
}

function Assert-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this script as administrator.' }
}
