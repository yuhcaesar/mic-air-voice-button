AirKey v1.1.0
English window title: AirKey — Insta360 Mic Air
中文：README.txt

Purpose
Turn the Volume Up signal sent by a Mic Air receiver into a shortcut that starts Doubao IME voice input.
The default is Right Alt + Space. You can change it in Settings.
The default driver-based sequence was tested successfully by the user on the development computer.
AirKey does not record audio, upload data or log ordinary typing.

First use
1. Put AirKey.exe somewhere you want to keep it, then double-click it.
   The EXE includes its runtime components; no separate AutoHotkey installation is needed.
2. Click Install & Enable, then approve the Windows administrator prompt.
3. After installation succeeds, save your work, restart Windows manually and reopen the EXE.
4. In Doubao IME, set the hands-free voice-input shortcut (免按模式) to Right Alt + Space.
5. The app automatically reuses an available connection. Click Enable Voice Button.
6. Focus a text field and press the Mic Air button to start Doubao voice input.
The main window illustrates “Mic Air button → Doubao IME” using the project microphone illustration
with Insta360 lettering and an icon read from a locally installed copy of Doubao IME.
It also shows the current shortcut and enabled state. Use the same main button to enable or pause.

Language and upgrades
Chinese is the default. Click English at the bottom right of the main window to switch to English,
or click 中文 in the same place to switch back. The choice is saved.
Switching needs no settings window or restart and does not pause an enabled voice button.
The main window, tray menu, shortcut recorder and app messages support both languages.
User Guide opens the file for the current language. Windows permission and other system dialogs follow the system language.
The Chinese window title is AirKey · 语音键 — Insta360 Mic Air.
To upgrade, quit the old app and replace its EXE with AirKey.exe. The installed driver does not need to be reinstalled.
Existing settings remain in %LOCALAPPDATA%\MicAirDoubao; the old folder name is retained for compatibility.

Everyday use
After enabling, the app saves its local configuration and attempts to restore the enabled state the next time it opens.
Pause Voice Button saves the paused state, which is also preserved on the next launch.
Minimizing hides the window in the system tray while the app keeps working.
Click the tray icon to restore the window; right-click for the menu.
The icon may be in Windows' hidden-icons area. Opening the EXE again also restores the existing window.
Closing the window or choosing Exit in the tray menu stops mapping and exits.
The app does not configure startup at sign-in or restart Windows automatically.
Do not run the old driver-bridge.ahk or another Volume Up mapping at the same time.
The app prevents multiple instances and asks you to close the known old test window if it is running.

Settings
Change shortcut: open Settings, find the shortcut for starting Doubao, click Edit,
then Start Recording. Press the combination you want and save it.
Recording distinguishes left/right modifiers and supports common main keys.
This changes the shortcut sent by AirKey, not Doubao IME's own configuration.
Set the same hands-free shortcut in Doubao IME; the two must match.

Repair Button Response: use this only when the button does not respond or the connection has changed.
It searches again for an available connection for sending shortcuts and leaves your saved shortcut unchanged.
Repair briefly pauses mapping and restores the previous enabled state if successful. It sends no test keystrokes.
If the button still does not work, reconnect the receiver or restart the computer and try again.
Expanding or collapsing Settings does not interrupt an enabled voice button.

Restore and uninstall
To restore normal Volume Up behavior temporarily, click Pause Voice Button. This works immediately with no restart.
To remove the driver, click Uninstall & Restore, approve the administrator prompt,
wait for completion, then restart Windows manually. Afterward, quit and delete the EXE if no longer needed.
Settings, logs and extracted components are stored in %LOCALAPPDATA%\MicAirDoubao.
After uninstalling the driver and quitting the app, you may delete this app-specific folder.
Use the app or the official installer to uninstall; do not delete Windows system driver files manually.
Uninstalling Interception affects other applications on this computer that use the same driver.

Limitations
- This build is for Intel/AMD Windows x64. Windows on ARM is not supported.
- Every Volume Up event received by the script can trigger voice input; the app cannot isolate Mic Air events.
- Triggers are spaced at least approximately 1.5 seconds apart to avoid repeated activation from one press.
- The app only sends the start shortcut; it does not detect whether Doubao is recording.
- On another computer, install the driver there. If the button stops responding, use Settings → Repair Button Response.
- Interception v1.0.1 is old; its upstream tested-system list goes up to Windows 10.
  Kanata documents input failures after repeated sleep or device hot-plugging on Windows 11.
  The trigger has worked on the tested computer; long-term sleep/hot-plug stability and other computers remain unverified.
- This EXE is not code-signed, so Windows may show an unknown publisher.
  If Windows blocks the driver, stop installation or uninstall it. Do not disable system security protections.

Component sources and licenses
AutoHotkey v2 / Ahk2Exe: https://github.com/AutoHotkey
Interception v1.0.1: https://github.com/oblitum/Interception/releases/tag/v1.0.1
Interception source: https://github.com/oblitum/Interception
Windows known issues: https://github.com/jtroo/kanata/blob/main/docs/platform-known-issues.adoc
The original license documents are extracted to the licenses folder. Their terms govern the components.
The Interception user-mode DLL and official installer are embedded unchanged.
SHA256 checks run after extraction and before the installer is invoked.
The official installer changes driver configuration; this app does not manually rewrite system keyboard/mouse filter entries.
Project source, build instructions and hashes are available in the accompanying source package and release materials.

UI artwork
The microphone and voice illustrations were originally generated from text descriptions without official product photos or renders as input.
Plain Insta360 lettering was added to the project microphone illustration to identify the compatible device.
It is not an official product photograph or an indication of manufacturer authorization or endorsement.
The project's MIT license grants no third-party trademark rights.
The Doubao IME icon is read at runtime from an already installed copy and is not embedded in the EXE.
An original generic voice illustration is used when no local icon is available.
See assets\ARTWORK.md in the source package for provenance and the full prompts.

Public source and licenses
Repository: https://github.com/yuhcaesar/mic-air-voice-button
Downloads and matching third-party source: https://github.com/yuhcaesar/mic-air-voice-button/releases
Original project code is MIT-licensed. The Interception API library uses LGPLv3;
its drivers and installer are subject to the upstream non-commercial-use conditions.
Commercial driver/installer use requires separate authorization from the upstream author.
The full Chinese and English notices are extracted to licenses\THIRD_PARTY_NOTICES.md
and licenses\THIRD_PARTY_NOTICES.en.md respectively.
Each binary Release includes ThirdParty-Sources.zip with matching AutoHotkey and Interception source.

Build and test from source
Install AutoHotkey v2 x64 and Ahk2Exe, then run .\build.ps1 in the source folder.
The output is dist\AirKey.exe. Use -Runtime and -Compiler to specify tool paths.
Building does not install a driver or run the result.
Run .\tests\run.ps1 for local checks. Key sends are mocked; everyday settings and drivers are not changed.
After modifying the Interception DLL, update its hash in Main.ahk and rebuild.
Replacing the DLL directly in the runtime folder will be overwritten by the embedded version.
See README.en.md and the matching Release for full rebuild instructions, upstream source and license details.
