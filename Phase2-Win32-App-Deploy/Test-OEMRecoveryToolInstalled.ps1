$cs = Get-CimInstance Win32_ComputerSystem
$mfr = $cs.Manufacturer.Trim()

switch -Wildcard ($mfr) {
    '*Dell*'      { $oem = 'Dell' }
    '*HP*'        { $oem = 'HP' }
    '*Lenovo*'    { $oem = 'Lenovo' }
    '*Microsoft*' { $oem = 'Microsoft' }
    '*Surface*'   { $oem = 'Microsoft' }
    default       { exit 0 }
}

$pat = @{
    Dell='SupportAssist.*Business|Dell.*SupportAssist'
    HP='HP Cloud Recovery'
    Lenovo='Commercial Vantage|E046963F.LenovoSettingsforEnterprise'
    Microsoft='Microsoft.SurfaceHub'
}[$oem]

$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$appOk = $false
foreach ($k in $keys) { Get-ItemProperty $k -EA 0 | ForEach-Object { if ($_.DisplayName -match $pat) { $appOk = $true } } }
if (-not $appOk -and $oem -eq 'Microsoft') { $appOk = [bool](Get-AppxPackage 'Microsoft.SurfaceHub' -EA 0) }
if (-not $appOk -and $oem -eq 'Lenovo') { $appOk = [bool](Get-AppxPackage 'E046963F.LenovoSettingsforEnterprise' -EA 0) }

$moduleOk = $true
if ($oem -eq 'Dell') { $moduleOk = [bool](Get-Module -ListAvailable DellBIOSProvider -EA 0) }
if ($oem -eq 'HP') { $moduleOk = [bool](Get-Module -ListAvailable HP.ClientManagement -EA 0) }

if ($appOk -and $moduleOk) { exit 0 }
exit 1
