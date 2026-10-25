# AirKey Button Diagnostics

[中文](README.md) | **English**

A standalone Windows x64 tool for checking how a Mic Air button reaches Windows and whether an existing keyboard output channel can activate Doubao voice input. It records current observations to help distinguish input reception, legacy callback gating, and shortcut output. It cannot guarantee reconstruction of the cause of a past failure. The diagnostic interface and generated report are currently in Chinese.

## 0.1.1 correction

Fixes event timestamps, down/up states, and flags being written under incorrect event indices in 0.1.0. Aggregate counters and user confirmations remain usable, but old timelines cannot establish press spacing or repeated signals. Use 0.1.1 for a new capture; missing fields cannot be recovered from old reports. Output labels sharing one candidate index describe one trial under multiple selection rules, not independent trials.

## Use

1. Connect the Mic Air receiver. Exit AirKey from its tray menu and close any standalone volume experiment tool. Place `AirKey-Diagnostics.exe` in a writable local folder, double-click it, and choose **开始检测** (Start).
2. Complete four input phases in order. In **each phase**, press the Mic Air button **twice, about 3 seconds apart**, then click **已按两次，继续** (Pressed twice; continue). Some phases may change Windows volume.
3. Click the tool's text box and manually press the displayed shortcut to establish that Doubao voice input works. End any resulting recording before choosing the result. The default is Right Alt + Space; an existing AirKey shortcut is read without changing its settings.
4. If the manual shortcut works and an existing Interception driver is available, the tool selects candidate output channels in turn. Click **试发一次** (Try once), release the keyboard, keep focus in the tool's text box, and confirm whether Doubao actually started. You do not need to recognize device numbers. Remaining trials can be skipped.
5. Choose **打开检测报告** (Open report) or **复制报告内容** (Copy report). TXT files normally go in `AirKey-Reports` beside the EXE. If that folder is not writable, the fallback is `%LOCALAPPDATA%\AirKeyDiagnostics\Reports`. The actual path appears in the window. After closing the tool, you can reopen AirKey.

No observed event, a timeout, or an unfinished step does not prove a hardware or driver fault. Simulated send/gate counts do not mean that any shortcut was sent or Doubao started. Actual output trials record your confirmation separately.

## Scope and privacy

Each input phase runs in a fresh child process so that keyboard hook state from one phase cannot affect the next. The phases observe Raw Input, reproduce legacy input callbacks and gates without sending keys, test a registered system hotkey, and test keyboard hooks. The legacy phase is not a complete run of the old application.

Only Volume Up input is examined. Reports contain system/component versions, driver state, anonymous counts, event counters and relative timings, fixed error codes, and your confirmations. They exclude ordinary keys or text typed into the box, account names, computer names, full hardware IDs, device paths, and serial numbers. Device identifiers from existing settings are compared only in local memory; reports retain match results and anonymous indices.

The tool does not connect to the network, install or remove drivers, change normal AirKey settings, or automatically repair configuration. It uses temporary input listeners during diagnosis. Actual shortcut output occurs only after you click a trial button, targeting this tool's text box. Input diagnosis remains available without a usable driver; output trials are then skipped. Closing the tool ends its temporary listeners and child process.

## Build

Requires Windows x64, AutoHotkey v2 x64 (release builds use 2.0.30), and official Ahk2Exe. Scripts use installed tools and do not download or install dependencies.

```powershell
.\build.ps1
```

The default output is `dist\AirKey-Diagnostics.exe`. The script runs `/Validate`, then compiles with Ahk2Exe and compression disabled. It does not launch the resulting program. Build logs are stored in `.build`.

```powershell
.\build.ps1 -Runtime 'C:\Tools\AutoHotkey\v2\AutoHotkey64.exe' -Compiler 'C:\Tools\AutoHotkey\Compiler\Ahk2Exe.exe'
.\build.ps1 -OutputPath '.\dist\AirKey-Diagnostics.exe'
```

You can also set `AHK_RUNTIME`, `AHK_COMPILER`, or `AUTOHOTKEY_HOME`. Otherwise discovery checks common installation folders and PATH.

## Isolated tests

```powershell
.\tests\run.ps1
```

The runner validates the application and test syntax before executing isolated input, report, and process-communication tests. It also runs the controller test when present. Tests use fixtures and mocks without real input registration, shortcut transmission, driver changes, or writes to normal settings. Results go in `tests\.results`; `-Runtime` and `-ResultsDirectory` override the runtime and results location.

`tests\LiveRegistrationSmoke.ahk` is **excluded from the default test run**. This separate manual check briefly registers and removes Raw Input while its callbacks do not read any events. It sends no keys. Neither mocks nor the registration smoke prove how a physical Mic Air behaves on the target computer.

`tests\WorkerProcessSmoke.ahk` is also opt-in. It checks the compiled Raw Input child process during normal completion and parent-window loss, without sending keys or changing drivers/settings. `AirKey-Diagnostics.exe --self-test <output-directory>` only checks embedded component extraction and validation.

## Licenses and corresponding source

Original project scripts, tests, build scripts, documentation, and the application icon use [MIT](LICENSE). A compiled EXE also includes the GPL AutoHotkey interpreter and LGPL Interception API library, each under its own license. This tool distributes no Interception installer or drivers. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the complete license texts in `assets`.

Releases supply this tool's source and `ThirdParty-Sources.zip` alongside the EXE. The archive contains the corresponding AutoHotkey 2.0.30 and Interception v1.0.1 sources. To use a modified, compatible Interception API library, build its x64 DLL using upstream instructions, replace `assets\interception.dll`, update that DLL's SHA-256 check in `Main.ahk` to the replacement's hash, and run this project's build script. This project does not restrict reverse engineering for debugging modifications to the library.
