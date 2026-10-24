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

- `ShortcutConfigTest.ahk`: parsing, left/right modifiers, extended scan codes, exact default output sequence, failure cleanup and release retry. Sends go to an in-memory mock.
- `LifecycleTest.ahk`: extracts an explicit allowlist of application functions into a generated worker with a mock output and mock enable function. Covers failed sends, stopping, persistence errors, editor cancellation and driver-state guards. No installer, native output class, startup code or real enable function is included.
- `ModernControlsTest.ahk`: constructs hidden controls and draws into a memory bitmap, checking native button properties and GDI resource cleanup. It does not send keyboard input.
- `AppArtworkTest.ahk`: checks local installation icon discovery and loads the original fallback when an icon is missing or invalid. Installed artwork is read in place, never copied into the project or app data.

Each run writes its own settings, logs and reports under `tests/.results/<run-id>/`. It does not touch `%LOCALAPPDATA%\MicAirDoubao`, start keyboard hooks, register hotkeys, load the driver DLL or install/uninstall drivers. `-ResultsDirectory` can choose another dedicated test-output folder.

Lifecycle tests intentionally respect existing physical key presses. Cases can be reported as `SKIP` if a modifier or the configured main key is held; release the keys and rerun those checks when needed. Passing mocks do not prove that a particular receiver, keyboard, Windows version or input-method shortcut works end to end.

Build tooling lives in `scripts/Resolve-AhkTools.ps1`. `build.ps1` accepts `-Runtime`, `-Compiler` and `-OutputPath`, recognizes `AHK_RUNTIME`, `AHK_COMPILER` and `AUTOHOTKEY_HOME`, and otherwise checks standard installation directories and `PATH`. Its default output is `dist/MicAirDoubao.exe`. It does not download dependencies or change drivers.
