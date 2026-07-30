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
Detect.ps1                       Remediate.ps1
┌───────────────────────┐        ┌──────────────────────────────┐
│ App installed?        │        │ App missing?   → exit 1      │
│ WinRE enabled?        │        │ App installed:               │
│ Both yes → exit 0     │        │  Enable WinRE                │
│ Either no → exit 1    │        │  Enable BIOS with modules    │
└───────────────────────┘        │  (deployed by Phase 2)       │
                                 │  Exit 0                      │
                                 └──────────────────────────────┘
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

If a BIOS admin password is deployed, Phase 3 detects it and **skips BIOS settings gracefully**:

| OEM | Detection method | Behavior |
|-----|-----------------|----------|
| Dell | `IsAdminPasswordSet` via DellBIOSProvider | Logs warning, skips BIOS config |
| HP | `Setup Password` via HP.ClientManagement | Logs warning, skips BIOS config |
| Lenovo | `IsAdminPasswordSet` via WMI | Logs warning, skips BIOS config |

**WinRE is still enabled.** OS corruption recovery (WinRE + cloud recovery boot) remains functional — only programmatic BIOS setting changes are blocked. No password is ever stored, passed, or embedded in the scripts.

## Requirements

- Windows 10/11 1809+
- PowerShell 5.1+
- Physical OEM hardware
- Run as SYSTEM (Intune context)
