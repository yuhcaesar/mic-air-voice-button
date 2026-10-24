# AirKey

[中文](README.md) | **English**

Turn the **Volume Up signal from an Insta360 Mic Air receiver** into a voice-input shortcut for Doubao IME.

For Intel / AMD **Windows x64**. The standalone EXE does not require a separate AutoHotkey installation for everyday use.

Original project code is MIT-licensed. The bundled Interception drivers and installer are subject to the upstream non-commercial-use conditions. Commercial use requires separate upstream authorization; see the [third-party notices](THIRD_PARTY_NOTICES.en.md).

[Download for Windows](https://github.com/yuhcaesar/mic-air-voice-button/releases/latest) · [User guide](assets/README.en.txt) · [Report an issue](https://github.com/yuhcaesar/mic-air-voice-button/issues)

<table>
  <tr>
    <td align="center"><img src="assets/mic-air-original.png" width="128" alt="Round microphone illustration with Insta360 lettering and a visible side button"><br>Press the Mic Air side button</td>
    <td align="center">→</td>
    <td align="center"><img src="assets/voice-illustration.png" width="112" alt="Voice-input illustration"><br>Start Doubao IME voice input</td>
  </tr>
</table>

At runtime, AirKey prefers the icon from Doubao IME already installed on the user's computer. That brand icon is not included in this repository or the download. The microphone is a project illustration; the added “Insta360” text identifies the compatible device. It is not an official product photograph.

## Features

- Enable or pause with one button; a green status indicates that mapping is enabled.
- Sends **Right Alt + Space** by default. You can record another shortcut, distinguishing left and right Alt, Ctrl and Shift.
- Automatically selects a connection for sending keys, without asking you to choose a keyboard number.
- Saves settings locally and restores the previous enabled state when reopened.
- Chinese by default, with an **English / 中文** button at the bottom right of the main window. The language choice is saved; switching keeps the voice button running.
- Minimizes to the system tray. Click the tray icon to restore the window, or right-click for the menu.
- Includes **Repair Button Response** and **Uninstall & Restore**.

## First use

1. Download and open `AirKey.exe` from [Releases](https://github.com/yuhcaesar/mic-air-voice-button/releases), then connect the Mic Air receiver.
2. Click **Install & Enable** and approve the Windows administrator prompt.
3. After installation, save your work and **restart Windows manually**, then reopen the app.
4. In Doubao IME, set the hands-free voice-input shortcut (免按模式) to **Right Alt + Space**.
5. Click **Enable Voice Button**, focus a text field and press the Mic Air button.

If the required driver is already installed and loaded, you can enable the button directly. Minimizing hides the window in the system tray while the app keeps running. Click the tray icon to restore it; Windows may place it in the hidden-icons area. Opening the EXE again restores the existing window instead of starting a second instance.

Closing the window or choosing **Exit** in the tray menu stops mapping and exits. AirKey does not restart Windows automatically or configure startup at sign-in.

### Language and upgrades

AirKey starts in Chinese by default. Click **English** at the bottom right of the main window to switch to English; click **中文** in the same place to switch back. The choice is saved. You do not need to open Settings, restart the app or pause an enabled voice button.

The main window, tray menu, shortcut recorder and app messages are available in both languages. **User Guide** opens the guide for the selected language. Windows-provided dialogs, such as permission prompts, follow the system language.

The English window title is **AirKey — Insta360 Mic Air**; the Chinese title is **AirKey · 语音键 — Insta360 Mic Air**.

To upgrade, quit the old app and replace its EXE with `AirKey.exe`. The existing driver does not need to be reinstalled. Your shortcut, enabled state and connection settings continue to use `%LOCALAPPDATA%\MicAirDoubao`; the folder name is retained for compatibility. The repository remains at `yuhcaesar/mic-air-voice-button`.

### Change the shortcut

Open **Settings → Edit → Start Recording**, press the shortcut configured in Doubao IME, then save.

**AirKey and Doubao IME must use the same shortcut.** This changes the keys sent by AirKey; it does not change Doubao IME's own settings.

### Restore Volume Up / uninstall

- Temporarily restore normal Volume Up behavior: click **Pause Voice Button**. The change is immediate.
- Remove the driver: click **Uninstall & Restore**, restart Windows manually after completion, then delete the EXE.
- Settings, logs and extracted components are stored in `%LOCALAPPDATA%\MicAirDoubao`. After uninstalling the driver and quitting the app, you may delete this app-specific folder.

Do not manually delete driver files from the Windows system directory. Uninstalling Interception also affects other applications using that driver.

## Limitations

- AirKey handles every **Volume Up** event it receives, not just Mic Air events. A keyboard's Volume Up key can also start voice input.
- Triggers are spaced at least approximately 1.5 seconds apart to avoid repeated activation from one press.
- AirKey only sends a shortcut. It does not record audio, upload data, log ordinary typing or detect whether Doubao is currently recording.
- Driver installation and removal need administrator permission and a subsequent restart.
- The button has been tested successfully with a Mic Air receiver on one Windows 11 x64 computer. Other devices, long sleep cycles and repeated hot-plugging have not been comprehensively tested.
- Interception v1.0.1 is old. [Kanata's Windows known issues](https://github.com/jtroo/kanata/blob/main/docs/platform-known-issues.adoc) document sleep and device hot-plugging problems with the driver on some systems.
- Windows on ARM is not supported. The EXE is not code-signed. If Windows blocks the driver, stop installation or uninstall it and keep system security protections enabled.

## Why a driver is needed

In this project's test environment, Mic Air reported Volume Up through its receiver, but ordinary software-generated shortcuts did not start Doubao voice input. AirKey uses AutoHotkey to receive the Volume Up event and Interception to send keyboard scan codes.

The default Right Alt + Space uses the sequence that worked in testing. The app does not use Interception to intercept raw keyboard input and does not modify the Doubao application.

## Build from source

Install [AutoHotkey v2 x64](https://www.autohotkey.com/) and [Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe), then run this in the repository folder:

```powershell
.\build.ps1
```

The output is `dist\AirKey.exe`. Use `-Runtime` and `-Compiler` to specify tool paths, or set the `AHK_RUNTIME` / `AHK_COMPILER` environment variables. Building does not install a driver or run the resulting EXE.

This release uses AutoHotkey **2.0.30 x64** and Ahk2Exe **1.1.37.02a2**. See [THIRD_PARTY_NOTICES.en.md](THIRD_PARTY_NOTICES.en.md) for dependency versions, licenses and sources.

### Third-party source and rebuilding

Each binary Release provides `ThirdParty-Sources.zip` on the same release page. It contains the matching AutoHotkey and Interception upstream source. Together with this repository's source, it supplies the source materials needed to rebuild; install each upstream toolchain according to its instructions.

To modify the Interception API DLL, first build an x64 DLL from the upstream source. Replace `assets/interception.dll`, update that DLL's SHA256 value in `Main.ahk` to match the new file, then run `build.ps1`. To modify AutoHotkey, build an x64 interpreter using the supplied upstream instructions and select it with `build.ps1 -Runtime <path>`. Source changes and rebuilding do not require additional permission from this project; third-party components remain subject to their own licenses.

The EXE extracts and verifies its embedded components, so directly replacing the DLL in its runtime folder will be overwritten. Use the rebuilding method above. This project does not prohibit lawful reverse engineering to debug user modifications.

### Tests

```powershell
.\tests\run.ps1
```

Tests cover syntax, shortcut parsing, send order, key release after failures, settings persistence and stopping behavior. Sends are replaced with in-memory mocks. Tests do not install a driver, send real shortcuts or alter everyday settings.

The physical Mic Air button, Doubao voice activation and driver installation/removal need manual verification on a compatible Windows computer.

## Project layout

| File | Purpose |
| --- | --- |
| `Main.ahk` | Main UI, configuration, Volume Up mapping and lifecycle |
| `NativeOutput.ahk` | Interception output and connection selection |
| `DriverManager.ahk` | Driver status, official installer invocation and integrity checks |
| `ShortcutConfig.ahk` | Shortcut parsing, key sequence and release recovery |
| `ShortcutRecorder.ahk` | Shortcut recording window |
| `ModernControls.ahk` | Native button drawing |
| `AppArtwork.ahk` | Locally installed IME icon discovery and original artwork fallback |
| `TrayWindow.ahk` | Minimize to tray, click to restore and existing-instance activation |
| `assets/` | UI artwork, dependencies and their original licenses |
| `tests/` | Local checks without real key sends |

## License and attribution

Original project code is available under the [MIT License](LICENSE). Third-party components retain their own licenses. The project's MIT license grants no Insta360 or other third-party trademark rights. See [THIRD_PARTY_NOTICES.en.md](THIRD_PARTY_NOTICES.en.md).

The complete [Chinese notices](THIRD_PARTY_NOTICES.md) are also available; the supplied original upstream licenses are unchanged.

AirKey is an independent project with no official affiliation with or endorsement by Insta360 or Doubao.
