$cs = Get-CimInstance Win32_ComputerSystem
$mfr = $cs.Manufacturer.Trim()

switch -Wildcard ($mfr) {
    '*Dell*'      { $oem = 'Dell' }
    '*HP*'        { $oem = 'HP' }
    '*Lenovo*'    { $oem = 'Lenovo' }
    '*Microsoft*' { $oem = 'Microsoft' }
    '*Surface*'   { $oem = 'Microsoft' }
    default       { $oem = 'Unknown' }
}

if ($oem -eq 'Unknown') { exit 0 }

$pat = @{
    Dell='SupportAssist.*Business|Dell.*SupportAssist|Dell.*OS Recovery'
    HP='HP Cloud Recovery'
    Lenovo='Commercial Vantage|E046963F.LenovoSettingsforEnterprise'
    Microsoft='Microsoft.SurfaceHub'
}[$oem]

$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$toolInstalled = $false
foreach ($k in $keys) { Get-ItemProperty $k -EA 0 | ForEach-Object { if ($_.DisplayName -match $pat) { $toolInstalled = $true } } }
if (-not $toolInstalled -and $oem -eq 'Microsoft') { $toolInstalled = [bool](Get-AppxPackage 'Microsoft.SurfaceHub' -EA 0) }
if (-not $toolInstalled -and $oem -eq 'Lenovo') { $toolInstalled = [bool](Get-AppxPackage 'E046963F.LenovoSettingsforEnterprise' -EA 0) }

$winreOk = (& reagentc.exe /info 2>&1) -join '' -match 'Windows RE status.*Enabled'

if ($toolInstalled -and $winreOk) { exit 0 }
exit 1
