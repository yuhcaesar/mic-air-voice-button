# Safe local tests

Run on Windows with AutoHotkey v2 x64 installed:

```powershell
.\tests\run.ps1
```

For a portable runtime, pass `-Runtime` or set `AHK_RUNTIME`:

```powershell
.\tests\run.ps1 -Runtime 'D:\Tools\AutoHotkey\AutoHotkey64.exe'
```

The runner checks `Main.ahk` with `/Validate` and does **not** run the application's startup code. It then runs:

- `LocalizationTest.ahk`: Chinese defaults, English persistence, invalid-language fallback, failed writes and preservation of mapping/driver settings. Checks dynamic nested messages and both-language shortcut labels against the same exact mock scan-code sequence, including right-side modifiers and extended keys.
- `ShortcutConfigTest.ahk`: parsing, left/right modifiers, extended scan codes, exact default output sequence, failure cleanup and release retry. Sends go to an in-memory mock.
- `NativeOutputTest.ahk`: saved-device matching, missing/ambiguous matches and automatic selection using fake records only. It never constructs `NativeOutput` or loads the driver library.
- `MachineProfileTest.ahk`: synthetic machine identities, verified-profile persistence, copied-machine rejection, atomic-save failure, duplicate-HID topology checks and trying each valid output candidate once. Never reads the real machine identity.
- `MicSetupControllerTest.ahk`: runs the actual setup controller with mock dialogs, button listeners and key output. Detection alone cannot save; actual trials still require explicit confirmation. Covers focus guards, candidate advancement, cancellation, timeout, send cleanup, failed saves and changed connections. Diagnostic assertions exclude identifiers and paths.
- `ButtonInputTest.ahk`: isolated input-event learning and filtering checks with simulated events; no live receiver capture or keyboard hooks.
- `SetupWizardTest.ahk`: isolated wizard state/control checks; no application startup, real button input or native key output.
- `LifecycleTest.ahk`: extracts an explicit allowlist of application functions into a generated worker with a mock output and mock enable function, plus the declarative localization and shortcut modules. Covers failed sends, stopping, persistence errors, editor cancellation and driver-state guards. The real `SwitchLanguage` is checked in active/paused states, all four guards and write failures; rendering is counted without changing controls or the tray menu. No installer, native output class, startup code or real enable function is included.
- `ModernControlsTest.ahk`: constructs hidden controls and draws into a memory bitmap, checking native button properties and GDI resource cleanup. It does not send keyboard input.
- `TrayWindowTest.ahk`: checks minimize/restore and modal priority with mock windows, plus the native one-click tray notification and exact-identity restore between isolated processes. It only posts messages to its own hidden test window.
- `AppArtworkTest.ahk`: checks local installation icon discovery and loads the original fallback when an icon is missing or invalid. Installed artwork is read in place, never copied into the project or app data.

Each run writes its own settings, logs and reports under `tests/.results/<run-id>/`. It does not touch `%LOCALAPPDATA%\MicAirDoubao`, start keyboard hooks, register hotkeys, load the driver DLL or install/uninstall drivers. `-ResultsDirectory` can choose another dedicated test-output folder.

Lifecycle and setup-controller tests intentionally respect existing physical key presses. Cases can be reported as `SKIP` if a modifier or the configured main key is held; release the keys and rerun those checks when needed. Lifecycle tests also execute the extracted Main startup shortcut/profile check and actual shortcut-change invalidation. Passing mocks do not prove that a particular receiver, keyboard, Windows version or input-method shortcut works end to end.

Build tooling lives in `scripts/Resolve-AhkTools.ps1`. `build.ps1` accepts `-Runtime`, `-Compiler` and `-OutputPath`, recognizes `AHK_RUNTIME`, `AHK_COMPILER` and `AUTOHOTKEY_HOME`, and otherwise checks standard installation directories and `PATH`. Its default output is `dist/AirKey.exe`. It does not download dependencies or change drivers.
