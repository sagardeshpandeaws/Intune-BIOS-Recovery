# Intune BIOS Recovery Configuration

Cloud-based OS corruption recovery for Dell, HP, Lenovo & Microsoft Surface.

```
Phase 1 ─► Download OEM installers (admin workstation)
Phase 2 ─► Deploy EXE/MSI as Intune Win32 App
Phase 3 ─► Configure BIOS + WinRE via Proactive Remediation (fail if tool missing → reported in Intune)
```

---

## Phase 1 — Download Installers

Run on an admin workstation with internet access:

```powershell
.\Phase1-Download-Installers\Get-OEMInstallers.ps1
```

Downloads into `Phase2-Win32-App-Deploy\Installers\OEM\`.  
Lenovo & Microsoft require manual download (script prints the URLs).

---

## Phase 2 — Deploy as Intune Win32 App

### Package

Use [Microsoft Win32 Content Prep Tool](https://go.microsoft.com/fwlink/?linkid=2065730):

```
IntuneWinAppUtil.exe -c "Phase2-Win32-App-Deploy" -s "Install-OEMRecoveryTool.ps1" -o "Output"
```

### Create App in Intune

**Endpoint Manager > Apps > Windows > Add > Windows app (Win32)**

| Field | Value |
|-------|-------|
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Install-OEMRecoveryTool.ps1"` |
| Uninstall command | `powershell.exe -NoProfile -Command "Write-Host 'Use Programs & Features'"` |
| Detection rule | Custom script → upload `Phase2-Win32-App-Deploy\Test-OEMRecoveryToolInstalled.ps1` |
| Run as 64-bit | Yes |
| System context | Yes |
| Restart behavior | Determine behavior based on exit codes (3010 = soft reboot) |

### What it does

- Detects OEM (Dell/HP/Lenovo/Microsoft)
- Runs the matching silent installer
- Deploys DellBIOSProvider / HP.ClientManagement modules to `C:\Program Files\WindowsPowerShell\Modules\`
- Detection checks both app + module are present

---

## Phase 3 — Configure BIOS + WinRE (Proactive Remediation)

**Endpoint Manager > Reports > Endpoint Analytics > Proactive Remediations > Create script package**

| Field | Value |
|-------|-------|
| Name | `BIOS Recovery Configuration` |
| Detection script | upload `Phase3-Settings-Remediation\Detect.ps1` |
| Remediation script | upload `Phase3-Settings-Remediation\Remediate.ps1` |
| Run 64-bit | Yes |
| Assignments | All devices |

### Phase 3 logic

```
Detect.ps1 (no password needed)    Remediate.ps1
┌───────────────────────┐         ┌──────────────────────────────────┐
│ App installed?        │         │ App missing?          → exit 1   │
│ WinRE enabled?        │         │ App installed:                   │
│ Both yes → exit 0     │         │  Enable WinRE                    │
│ Either no → exit 1    │         │  Enable BIOS settings:           │
└───────────────────────┘         │   No password + locked → log skip│
                                  │   Password provided → apply      │
                                  │  Exit 0                          │
                                  └──────────────────────────────────┘
```

| OEM | App deployed (Phase 2) | Module deployed (Phase 2) | BIOS settings applied |
|-----|----------------------|--------------------------|-----------------------|
| Dell | SupportAssist for Business PCs | DellBIOSProvider | BiosConnect, SupportAssistOSRecovery |
| HP | HP Cloud Recovery Client | HP.ClientManagement | HP Cloud Recovery, Recovery Manager Boot |
| Lenovo | Commercial Vantage | Built-in WMI | RecoveryBoot, BootToCloud |
| Microsoft | Surface App | None | WinRE only |

Modules are downloaded in Phase 1 and deployed to `C:\Program Files\WindowsPowerShell\Modules\` in Phase 2. Phase 3 just uses them.

---

## File Structure

```
Intune BIOS Setup\
├── README.md
├── Phase1-Download-Installers\
│   └── Get-OEMInstallers.ps1           Download helper
├── Phase2-Win32-App-Deploy\
│   ├── Install-OEMRecoveryTool.ps1     Install command for Win32 App
│   ├── Test-OEMRecoveryToolInstalled.ps1  Detection for Win32 App
│   └── Installers\                      Created by Phase 1
│       ├── Dell\SupportAssistBusinessInstaller.exe
│       ├── HP\sp156169.exe
│       ├── Lenovo\VantageInstaller.exe
│       │   ├── DellBIOSProvider\
│       │   └── HP.ClientManagement\
│       └── Microsoft\Microsoft.SurfaceHub_*.msixbundle
└── Phase3-Settings-Remediation\
    ├── Detect.ps1                       Proactive Remediation — detection script
    └── Remediate.ps1                    Proactive Remediation — remediation script
```

## BIOS Password Handling

If a BIOS admin password is deployed, pass it to Phase 3 so BIOS settings are applied:

### Option A — Registry key (recommended for Proactive Remediation)

Deploy a registry key via Intune **Configuration Profile** (OMA-URI) or a separate script:

```
Path:   HKLM\SOFTWARE\IntuneBIOSRecovery
Value:  BiosPassword (REG_SZ)
```

The script reads this automatically when `-BiosPassword` is not passed.

### Option B — Script parameter (for Win32 App)

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Remediate.ps1" -BiosPassword "YourPassword"
```

### Security

- Password is used **only in-memory** — never written to logs
- Variable is cleared (`Remove-Variable`) immediately after use
- Registry key should be restricted to SYSTEM (default for HKLM)
- The password is a shared fleet secret, same as any enterprise BIOS management tool

### If no password is provided

Script detects the lock, logs a clear warning, skips BIOS config. **WinRE is still enabled.**

## Requirements

- Windows 10/11 1809+
- PowerShell 5.1+
- Physical OEM hardware
- Run as SYSTEM (Intune context)
