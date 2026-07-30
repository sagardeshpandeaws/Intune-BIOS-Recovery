param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\Phase2-Win32-App-Deploy\Installers')
)

$sources = @(
    @{
        OEM      = 'Dell'
        URL      = 'https://downloads.dell.com/serviceability/catalog/SupportAssistBusinessInstaller.exe'
        FileName = 'SupportAssistBusinessInstaller.exe'
    }
    @{
        OEM      = 'HP'
        URL      = 'https://ftp.hp.com/pub/softpaq/sp156001-156500/sp156169.exe'
        FileName = 'sp156169.exe'
    }
    @{
        OEM      = 'Lenovo'
        URL      = $null
        FileName = 'VantageInstaller.exe'
        Note     = 'Download from: https://support.lenovo.com/us/en/solutions/hf003321'
    }
    @{
        OEM      = 'Microsoft'
        URL      = $null
        FileName = 'Microsoft.SurfaceHub_*.msixbundle'
        Note     = 'Download from: https://www.microsoft.com/en-us/download/details.aspx?id=105302'
    }
)

$modules = @(
    @{ Name = 'DellBIOSProvider' }
    @{ Name = 'HP.ClientManagement' }
)

Write-Host '===========================================' -ForegroundColor Cyan
Write-Host '  OEM Recovery Tool Installer Downloader' -ForegroundColor Cyan
Write-Host '===========================================' -ForegroundColor Cyan
Write-Host "Output: $OutputPath`n" -ForegroundColor Gray

foreach ($s in $sources) {
    $dir = Join-Path $OutputPath $s.OEM
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    if ($s.URL) {
        $out = Join-Path $dir $s.FileName
        if (Test-Path $out) {
            Write-Host "[$($s.OEM)] Already exists" -ForegroundColor Green
        } else {
            Write-Host "[$($s.OEM)] Downloading..." -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $s.URL -OutFile $out -UseBasicParsing -ErrorAction Stop
                Write-Host "[$($s.OEM)] Saved: $out" -ForegroundColor Green
            } catch {
                Write-Host "[$($s.OEM)] FAILED: $_" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "[$($s.OEM)] Manual download:" -ForegroundColor Yellow
        Write-Host "        $($s.Note)" -ForegroundColor Gray
        Write-Host "        Place in: $dir" -ForegroundColor Gray
    }
}

# ── PowerShell modules ──
$moduleDir = Join-Path $OutputPath 'Modules'
New-Item -ItemType Directory -Path $moduleDir -Force | Out-Null

foreach ($m in $modules) {
    $installed = Get-Module -ListAvailable $m.Name -ErrorAction SilentlyContinue
    if (-not $installed) {
        Write-Host "[$($m.Name)] NOT found on this machine. Install it first:" -ForegroundColor Yellow
        Write-Host "        Install-Module $($m.Name) -Force -Scope CurrentUser" -ForegroundColor Gray
        Write-Host "        Then re-run this script." -ForegroundColor Gray
        continue
    }

    $latest = $installed | Sort-Object Version -Descending | Select-Object -First 1
    $target = Join-Path $moduleDir $m.Name
    if (Test-Path (Join-Path $target $latest.Version)) {
        Write-Host "[$($m.Name)] Already saved in modules" -ForegroundColor Green
        continue
    }

    Write-Host "[$($m.Name)] Saving v$($latest.Version)..." -ForegroundColor Yellow
    try {
        Save-Module -Name $m.Name -Path $moduleDir -Force -ErrorAction Stop
        Write-Host "[$($m.Name)] Saved to $target" -ForegroundColor Green
    } catch {
        Write-Host "[$($m.Name)] FAILED: $_" -ForegroundColor Red
    }
}

Write-Host "`nDone. Files ready in: $OutputPath" -ForegroundColor Cyan
