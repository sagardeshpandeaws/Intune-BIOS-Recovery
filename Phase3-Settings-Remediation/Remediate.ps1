param([string]$BiosPassword = '')

$logFile = "$env:TEMP\BIOSRecovery_Remediate.log"
function Log { param([string]$m) $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$t $m" | Out-File $logFile -Append; Write-Host "$t $m" }

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

if (-not $BiosPassword) {
    $regVal = Get-ItemProperty -Path 'HKLM:\SOFTWARE\IntuneBIOSRecovery' -Name 'BiosPassword' -EA 0
    if ($regVal -and $regVal.BiosPassword) { $BiosPassword = $regVal.BiosPassword }
}

function AppInstalled {
    param($oem)
    $pat = @{ Dell='SupportAssist|Dell.*OS Recovery'; HP='HP Cloud Recovery'; Lenovo='Commercial Vantage|E046963F.LenovoSettingsforEnterprise'; Microsoft='Microsoft.SurfaceHub' }[$oem]
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) { Get-ItemProperty $k -EA 0 | ForEach-Object { if ($_.DisplayName -match $pat) { return $true } } }
    if ($oem -eq 'Microsoft' -and (Get-AppxPackage 'Microsoft.SurfaceHub' -EA 0)) { return $true }
    if ($oem -eq 'Lenovo' -and (Get-AppxPackage 'E046963F.LenovoSettingsforEnterprise' -EA 0)) { return $true }
    return $false
}

if (-not (AppInstalled $oem)) { Log "$oem recovery tool NOT installed — exit 1"; exit 1 }
Log "$oem recovery tool installed"

# ── WinRE ──
$output = & reagentc.exe /info 2>&1
if (($output -join '') -match 'Windows RE status.*Enabled') {
    Log 'WinRE already enabled'
} else {
    Log 'Enabling WinRE...'
    & reagentc.exe /enable 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Log 'WinRE enabled' } else { Log 'WinRE enable failed' }
}

# ── BIOS settings ──
switch ($oem) {

    'Dell' {
        if (-not (Get-Module -ListAvailable DellBIOSProvider)) { Log 'DellBIOSProvider not found — BIOS settings skipped. Deploy via Phase 2.'; break }
        Import-Module DellBIOSProvider -Force -EA Stop
        'SupportAssistSystemResolution\BiosConnect', 'SupportAssistSystemResolution\SupportAssistOSRecovery' | ForEach-Object {
            $fp = "DellSmbios:\$_"
            try {
                $cur = Get-Item $fp -EA Stop
                if ($cur.CurrentValue -ne 'Enabled') {
                    if ($BiosPassword) { Set-Item $fp -Value 'Enabled' -Password $BiosPassword -EA Stop }
                    else { Set-Item $fp -Value 'Enabled' -EA Stop }
                    Log "Dell BIOS: $_ = Enabled"
                } else { Log "Dell BIOS: $_ already Enabled" }
            } catch { Log "Dell BIOS: $_ failed — $($_.Exception.Message)" }
        }
    }

    'HP' {
        if (-not (Get-Module -ListAvailable HP.ClientManagement)) { Log 'HP.ClientManagement not found — BIOS settings skipped. Deploy via Phase 2.'; break }
        Import-Module HP.ClientManagement -Force -EA Stop
        'HP Cloud Recovery', 'Recovery Manager Boot' | ForEach-Object {
            try {
                $cur = Get-HPBIOSSetting -Name $_ -EA Stop
                if ($cur.Value -ne 'Enabled') {
                    if ($BiosPassword) { Set-HPBIOSSetting -Name $_ -Value 'Enabled' -Password $BiosPassword -EA Stop }
                    else { Set-HPBIOSSetting -Name $_ -Value 'Enabled' -EA Stop }
                    Log "HP BIOS: $_ = Enabled"
                } else { Log "HP BIOS: $_ already Enabled" }
            } catch { Log "HP BIOS: $_ failed — $($_.Exception.Message)" }
        }
    }

    'Lenovo' {
        $pwSuffix = if ($BiosPassword) { ",password,$BiosPassword" } else { '' }
        'RecoveryBoot=Enable', 'BootToCloud=Enable' | ForEach-Object {
            $n = $_.Split('=')[0]
            try {
                $cur = Get-CimInstance -Namespace 'root\wmi' -ClassName Lenovo_BiosSetting -Filter "CurrentSetting like '$n%'" -EA 0
                if (-not $cur -or $cur.CurrentSetting -ne $_) {
                    Invoke-CimMethod -Namespace 'root\wmi' -ClassName Lenovo_BiosSetting -MethodName SetBiosSetting -Arguments @{ Setting = "$_$pwSuffix" } -EA Stop | Out-Null
                    Invoke-CimMethod -Namespace 'root\wmi' -ClassName Lenovo_BiosSetting -MethodName SaveBiosSettings -EA Stop | Out-Null
                    Log "Lenovo BIOS: $_"
                } else { Log "Lenovo BIOS: $_ already set" }
            } catch { Log "Lenovo BIOS: $_ failed — $($_.Exception.Message)" }
        }
    }

}

Remove-Variable BiosPassword -Force -EA 0
Log 'Done'
exit 0
