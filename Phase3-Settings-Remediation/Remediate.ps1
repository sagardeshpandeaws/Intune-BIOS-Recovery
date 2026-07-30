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

function AppInstalled {
    param($oem)
    $pat = @{ Dell='SupportAssist|Dell.*OS Recovery'; HP='HP Cloud Recovery'; Lenovo='Commercial Vantage|E046963F.LenovoSettingsforEnterprise'; Microsoft='Microsoft.SurfaceHub' }[$oem]
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) { Get-ItemProperty $k -EA 0 | ForEach-Object { if ($_.DisplayName -match $pat) { return $true } } }
    if ($oem -eq 'Microsoft' -and (Get-AppxPackage 'Microsoft.SurfaceHub' -EA 0)) { return $true }
    if ($oem -eq 'Lenovo' -and (Get-AppxPackage 'E046963F.LenovoSettingsforEnterprise' -EA 0)) { return $true }
    return $false
}

if (-not (AppInstalled $oem)) {
    Log "$oem recovery tool NOT installed — exit 1"
    exit 1
}

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

# ── BIOS settings (modules deployed by Phase 2) ──
switch ($oem) {

    'Dell' {
        if (-not (Get-Module -ListAvailable DellBIOSProvider)) {
            Log 'DellBIOSProvider not found — skipping BIOS config. Check Phase 2 deployment.'
        } else {
            Import-Module DellBIOSProvider -Force -EA Stop
            'SupportAssistSystemResolution\BiosConnect', 'SupportAssistSystemResolution\SupportAssistOSRecovery' | ForEach-Object {
                $fp = "DellSmbios:\$_"
                $cur = Get-Item $fp -EA Stop
                if ($cur.CurrentValue -ne 'Enabled') {
                    Set-Item $fp -Value 'Enabled' -EA Stop
                    Log "Dell BIOS: $_ = Enabled"
                } else { Log "Dell BIOS: $_ already Enabled" }
            }
        }
    }

    'HP' {
        if (-not (Get-Module -ListAvailable HP.ClientManagement)) {
            Log 'HP.ClientManagement not found — skipping BIOS config. Check Phase 2 deployment.'
        } else {
            Import-Module HP.ClientManagement -Force -EA Stop
            'HP Cloud Recovery', 'Recovery Manager Boot' | ForEach-Object {
                $cur = Get-HPBIOSSetting -Name $_ -EA Stop
                if ($cur.Value -ne 'Enabled') {
                    Set-HPBIOSSetting -Name $_ -Value 'Enabled' -EA Stop
                    Log "HP BIOS: $_ = Enabled"
                } else { Log "HP BIOS: $_ already Enabled" }
            }
        }
    }

    'Lenovo' {
        'RecoveryBoot=Enable', 'BootToCloud=Enable' | ForEach-Object {
            $n = $_.Split('=')[0]
            $cur = Get-CimInstance -Namespace 'root\wmi' -ClassName Lenovo_BiosSetting -Filter "CurrentSetting like '$n%'" -EA 0
            if (-not $cur -or $cur.CurrentSetting -ne $_) {
                Invoke-CimMethod -Namespace 'root\wmi' -ClassName Lenovo_BiosSetting -MethodName SetBiosSetting -Arguments @{ Setting = $_ } -EA Stop | Out-Null
                Invoke-CimMethod -Namespace 'root\wmi' -ClassName Lenovo_BiosSetting -MethodName SaveBiosSettings -EA Stop | Out-Null
                Log "Lenovo BIOS: $_"
            } else { Log "Lenovo BIOS: $_ already set" }
        }
    }

}

Log 'Done'
exit 0
