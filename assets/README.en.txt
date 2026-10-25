AirKey v1.3.0
English window title: AirKey — Insta360 Mic Air
中文：README.txt

Purpose
Turn the Volume Up signal sent by a Mic Air receiver into a shortcut that starts Doubao IME voice input.
The default is Right Alt + Space. You can change it in Settings.
The default sequence and standalone volume guard have been tested by the user, including unchanged volume on another computer. The integrated app still needs confirmation on the target computer.
AirKey does not record audio, upload data or log ordinary typing.

First use
1. Put AirKey.exe somewhere you want to keep it, then double-click it.
   The EXE includes its runtime components; no separate AutoHotkey installation is needed.
2. Click Install & Enable, then approve the Windows administrator prompt.
3. After installation succeeds, save your work, restart Windows manually and reopen the EXE.
   The button setup wizard opens automatically when the driver is ready.
4. In Doubao IME, set the hands-free voice-input shortcut (免按模式) to Right Alt + Space.
5. Press the Mic Air button once so AirKey can detect it.
6. Click the wizard's input box, then press the Mic Air button again to try starting Doubao voice input.
7. If it starts, volume stays unchanged and no volume overlay appears, click Both work, finish setup. Only then is this computer's configuration saved and enabled.
   Otherwise, click Voice failed, try another, then try the button again in the input box.
   AirKey tries the available local connections in turn; you do not need to choose a device number.
If the required driver is already installed and loaded, skip reinstallation and complete the wizard.
Setup counts as successful only after a real button event, a trial and your confirmation that voice input started without changing volume or showing the volume overlay.
Choose Volume still changes if volume changes; that result will not be saved. Initial detection may change volume once; the later trial activates the guard.
AirKey does not automatically detect whether Doubao has started recording or save the contents of the trial input box.
After cancelling, click Set Up Voice Button to start again.
The main window illustrates “Mic Air button → Doubao IME” using the project microphone illustration
with Insta360 lettering and an icon read from a locally installed copy of Doubao IME.
It also shows the current shortcut and enabled state. Use the same main button to enable or pause.

Language and upgrades
Chinese is the default. Click English at the bottom right of the main window to switch to English,
or click 中文 in the same place to switch back. The choice is saved.
Switching needs no settings window or restart and does not pause an enabled voice button.
The main window, button setup wizard, tray menu, shortcut recorder and app messages support both languages.
The wizard keeps the language it had when opened; close it before switching.
User Guide opens the file for the current language. Windows permission and other system dialogs follow the system language.
The Chinese window title is AirKey · 语音键 — Insta360 Mic Air.
To upgrade, quit the old app and standalone volume probe, then replace its EXE with AirKey.exe. An installed, working driver does not need to be reinstalled.
Upgrading to v1.3.0 requires confirming voice starts without changing volume; older voice-only confirmation is not sufficient.
Existing shortcut and language settings remain in %LOCALAPPDATA%\MicAirDoubao; the folder name is retained for compatibility.
Each computer saves its own verified configuration. Repeat setup on a new computer, when the previous connection disappears,
or when the saved connection can no longer be identified reliably. Copying the EXE or old settings does not replace that verification.

Everyday use
After confirmation in the wizard, the app saves its local configuration. It attempts to restore the enabled state on the next launch if the connection remains valid.
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
After changing the shortcut, complete button setup again to confirm the new combination starts Doubao voice input.

Set Up Button Again: choose this in Settings if the button does not respond or you need to set it up again.
It detects the button again and lets you try the available connections, leaving your chosen shortcut unchanged.
A trial shortcut is sent only when you press Mic Air with the wizard's input box focused.
The new result is saved only after you click Both work, finish setup. If it did not start, click Voice failed, try another.
AirKey does not automatically decide whether Doubao started. If setup still fails, check that the manual shortcut works,
that both shortcut settings match, and that the receiver is connected.
Expanding or collapsing Settings does not interrupt an enabled voice button.

Restore and uninstall
To stop voice activation temporarily, click Pause Voice Button. This works immediately with no restart;
the volume guard is stopped and normal Volume Up behavior is restored as well.
To remove the driver, click Uninstall & Restore, approve the administrator prompt,
wait for completion, then restart Windows manually. Afterward, quit and delete the EXE if no longer needed.
Settings, logs and extracted components are stored in %LOCALAPPDATA%\MicAirDoubao.
After uninstalling the driver and quitting the app, you may delete this app-specific folder.
Use the app or the official installer to uninstall; do not delete Windows system driver files manually.
Uninstalling Interception affects other applications on this computer that use the same driver.

Limitations
- This build is for Intel/AMD Windows x64. Windows on ARM is not supported.
- Setup chooses the input method automatically; you do not need to select it.
  In keyboard-key mode, every received Volume Up event can trigger voice input, including the keyboard's Volume Up key.
  Raw device input starts the built-in volume guard; the standalone probe is no longer needed.
  The guard handles all volume-up commands reaching its channel, not just Mic Air; use the system slider to adjust volume.
- Triggers are spaced at least approximately 1.5 seconds apart to avoid repeated activation from one press.
- The app only sends the start shortcut; it does not detect whether Doubao is recording.
- On another computer, prepare the driver there and complete the wizard again. If the button stops responding, use Settings → Set Up Button Again.
- Compatibility with every computer is not guaranteed. Setup succeeds only after a button event and your confirmation that Doubao voice input started without changing volume on that computer.
- Interception v1.0.1 is old; its upstream tested-system list goes up to Windows 10.
  Kanata documents input failures after repeated sleep or device hot-plugging on Windows 11.
  Long-term sleep/hot-plug behavior and all app scenarios are not comprehensively verified; some apps may bypass the volume guard.
- This EXE is not code-signed, so Windows may show an unknown publisher.
  The wizard cannot automatically resolve a driver blocked by Windows. If this happens, stop installation or uninstall it. Do not disable system security protections.

How the button is received
Setup checks registered hotkeys, keyboard hooks and raw device input, selecting only after an event. Raw input also activates the built-in volume-command guard.
All methods use Interception to send your configured shortcut; Interception does not intercept raw keyboard input.
Driver installation and removal still require administrator permission and a manual restart. The wizard cannot bypass these requirements.

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
