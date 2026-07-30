$scriptRoot = $PSScriptRoot
$logFile = "$env:TEMP\OEMToolInstall.log"
function Log { param([string]$m) $t = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; "$t $m" | Out-File $logFile -Append; Write-Host "$t $m" }

function Get-OEM {
    $cs = Get-CimInstance Win32_ComputerSystem
    $m = $cs.Manufacturer.Trim()
    switch -Wildcard ($m) {
        '*Dell*'      { return 'Dell' }
        '*HP*'        { return 'HP' }
        '*Lenovo*'    { return 'Lenovo' }
        '*Microsoft*' { return 'Microsoft' }
        '*Surface*'   { return 'Microsoft' }
    }
    return 'Unknown'
}

function AlreadyInstalled($oem) {
    $patterns = @{
        Dell   = 'SupportAssist.*Business|Dell.*SupportAssist'
        HP     = 'HP Cloud Recovery'
        Lenovo = 'Lenovo.*Commercial.*Vantage|Commercial Vantage|E046963F.LenovoSettingsforEnterprise'
        Microsoft = 'Microsoft.SurfaceHub|Microsoft Surface'
    }
    $pat = $patterns[$oem]
    if (-not $pat) { return $false }
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) { Get-ItemProperty $k -EA 0 | ForEach-Object { if ($_.DisplayName -match $pat) { return $true } } }
    if ($oem -eq 'Microsoft') { if (Get-AppxPackage -Name 'Microsoft.SurfaceHub' -EA 0) { return $true } }
    if ($oem -eq 'Lenovo') { if (Get-AppxPackage -Name 'E046963F.LenovoSettingsforEnterprise' -EA 0) { return $true } }
    return $false
}

function Deploy-Module($name) {
    $src = Join-Path $scriptRoot 'Installers\Modules' $name
    if (-not (Test-Path $src)) { Log "Module source not found: $src — skipping"; return }
    $dst = "C:\Program Files\WindowsPowerShell\Modules\$name"
    if (Test-Path $dst) { Log "Module $name already deployed at $dst"; return }
    try {
        Copy-Item -Path $src -Destination $dst -Recurse -Force -EA Stop
        Log "Module $name deployed to $dst"
    } catch { Log "Failed to deploy module $name : $_" }
}

try {
    $oem = Get-OEM
    Log "Device OEM: $oem"
    if ($oem -eq 'Unknown') { Log 'Unknown OEM — nothing to install.'; exit 0 }

    if (-not (AlreadyInstalled $oem)) {
        Log "$oem recovery tool not found. Installing..."
        $instDir = Join-Path $scriptRoot 'Installers'
        $exitCode = 0
        switch ($oem) {
            'Dell' {
                $exe = Join-Path $instDir 'Dell\SupportAssistBusinessInstaller.exe'
                if (-not (Test-Path $exe)) { throw "Missing: $exe" }
                Log "Running: $exe /s /v`"/qn /norestart`""
                $p = Start-Process $exe -ArgumentList '/s /v"/qn /norestart"' -Wait -PassThru -NoNewWindow
                $exitCode = $p.ExitCode
            }
            'HP' {
                $exe = Get-ChildItem "$instDir\HP\sp*.exe" | Select-Object -First 1 -ExpandProperty FullName
                if (-not $exe) { throw "Missing HP SoftPaq in $instDir\HP\" }
                Log "Running: $exe /s"
                $p = Start-Process $exe -ArgumentList '/s' -Wait -PassThru -NoNewWindow
                $exitCode = $p.ExitCode
            }
            'Lenovo' {
                $exe = Join-Path $instDir 'Lenovo\VantageInstaller.exe'
                if (-not (Test-Path $exe)) { throw "Missing: $exe" }
                Log "Running: $exe Install -Vantage -SuHelper"
                $p = Start-Process $exe -ArgumentList 'Install', '-Vantage', '-SuHelper' -Wait -PassThru -NoNewWindow
                $exitCode = $p.ExitCode
            }
            'Microsoft' {
                $msix = Get-ChildItem "$instDir\Microsoft\*.msixbundle" | Select-Object -First 1 -ExpandProperty FullName
                if (-not $msix) { throw "Missing MSIXBUNDLE in $instDir\Microsoft\" }
                Log "Installing: $msix"
                Add-AppxPackage -Path $msix -EA Stop | Out-Null
                $exitCode = 0
            }
        }
        Log "Install exit code: $exitCode"
        if ($exitCode -notin @(0,3010,1641)) { throw "Install failed (exit: $exitCode)" }
        Log "$oem recovery tool installed."
    } else {
        Log "$oem recovery tool already installed."
    }

    # ── Deploy matching PowerShell module ──
    $moduleMap = @{ Dell = 'DellBIOSProvider'; HP = 'HP.ClientManagement' }
    $moduleName = $moduleMap[$oem]
    if ($moduleName) { Deploy-Module $moduleName }

    Log 'Phase 2 complete.'
    exit 0
} catch {
    Log "FATAL: $_"
    exit 1
}
