#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#MaxThreadsPerHotkey 1
#Include Localization.ahk
#Include DriverManager.ahk
#Include NativeOutput.ahk
#Include ModernControls.ahk
#Include ShortcutConfig.ahk
#Include ShortcutRecorder.ahk
#Include AppArtwork.ahk
#Include TrayWindow.ahk
#Include ButtonInput.ahk
#Include MachineProfile.ahk
#Include SetupWizard.ahk
#Include MicSetupController.ahk
;@Ahk2Exe-SetName AirKey
;@Ahk2Exe-SetDescription AirKey for Insta360 Mic Air and Doubao voice input
;@Ahk2Exe-SetVersion 1.3.0.0
;@Ahk2Exe-SetOrigFilename AirKey.exe

global PersonalEdition := false
global AppTitle := "AirKey · 语音键 — Insta360 Mic Air"
global DataDir := EnvGet("LOCALAPPDATA") "\MicAirDoubao"
global SelfTest := false, TestUI := false
global S := {enabled: false, busy: false, maintenance: false, advancedOpen: false,
    faulted: false, hotkey: false, armed: true, lastVolume: 0,
    held: {keys: []}, binding: 0, editing: false, editorResume: false,
    native: 0, devices: [], selected: 0, mutex: 0,
    button: 0, profile: 0, machine: "", settingUp: false, setup: 0,
    notice: N("启用后，按 Mic Air 按钮即可启动豆包语音。", "Enable the button, then press Mic Air to start Doubao voice input."),
    pendingReboot: false, savedHid: "", resume: false}
global UI := Map(), ConfigPath := "", LogPath := "", Driver := 0

try {
    ParseArguments()
    nativeMachine := 0, processMachine := 0
    try {
        if DllCall("Kernel32\IsWow64Process2", "Ptr", -1, "UShort*", &processMachine, "UShort*", &nativeMachine)
            && nativeMachine != 0x8664
            throw Error(L("本程序需要 Intel／AMD 的 64 位 Windows，当前系统架构不适用。", "This app requires 64-bit Windows on an Intel or AMD processor."))
    } catch as archError {
        if nativeMachine && nativeMachine != 0x8664
            throw archError
    }
    ConfigPath := DataDir "\settings.ini"
    LogPath := DataDir "\activity.log"
    LoadAppLanguage(ConfigPath)
    AppTitle := AppWindowTitle()
    if !SelfTest
        ClaimInstance()
    OnExit(Cleanup)
    ExtractAssets()
    if SelfTest {
        RunSelfTest()
        ExitApp(0)
    }
    ; Keep the tray available even when the window is hidden and mapping is paused.
    Persistent()
    S.savedHid := IniRead(ConfigPath, "Mapping", "HardwareId", "")
    S.resume := IniRead(ConfigPath, "Mapping", "EnableOnLaunch", "0") = "1"
    try S.binding := ParseShortcut(IniRead(ConfigPath, "Mapping", "Shortcut", "RAlt+Space"))
    catch {
        S.binding := ParseShortcut("RAlt+Space")
        S.resume := false
        Log("Invalid saved shortcut; default restored with mapping paused.")
    }
    S.machine := GetMachineProfileKey()
    S.profile := LoadMicProfile(ConfigPath, S.machine)
    if IsObject(S.profile) && S.profile.shortcut != S.binding.canonical
        S.profile := 0
    BuildGui()
    RefreshDriver()
    if !TestUI && !S.pendingReboot && DriverReady() {
        if !IsObject(S.profile) || !S.selected
            SetTimer(BeginMicSetup, -350)
        else if S.resume
            EnableMapping()
    }
} catch as err {
    if SelfTest {
        try FileAppend("FAIL: " err.Message "`n", DataDir "\self-test.txt", "UTF-8")
    } else
        MsgBox(L("程序无法启动：{1}", "Could not start the app: {1}", err.Message), AppTitle, "Icon!")
    ExitApp(2)
}

ParseArguments() {
    global DataDir, SelfTest, TestUI
    i := 1
    while i <= A_Args.Length {
        arg := A_Args[i]
        if arg = "--self-test"
            SelfTest := true
        else if arg = "--test-ui"
            TestUI := true
        else if arg = "--data-dir" && i < A_Args.Length {
            i++
            DataDir := RTrim(A_Args[i], "\/")
            if !RegExMatch(DataDir, "i)^[A-Z]:\\")
                throw Error(L("数据目录必须是本机绝对路径。", "The data directory must be an absolute local path."))
        } else
            throw Error(L("不支持的启动参数。", "Unsupported startup argument."))
        i++
    }
}

ClaimInstance() {
    global S, AppTitle
    S.mutex := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 0,
        "Str", "Local\MicAirDoubao.ControlPanel.v1", "Ptr")
    if !S.mutex
        throw Error(L("无法建立单实例保护。", "Could not check for an existing app instance."))
    if A_LastError = 183 {
        DllCall("Kernel32\CloseHandle", "Ptr", S.mutex)
        S.mutex := 0
        if !RequestExistingTrayWindow() && WinExist(AppTitle " ahk_class AutoHotkeyGUI") {
            WinRestore(AppTitle " ahk_class AutoHotkeyGUI")
            WinActivate(AppTitle " ahk_class AutoHotkeyGUI")
        }
        ExitApp(0)
    }
}

ExtractAssets() {
    global DataDir
    DirCreate(DataDir "\components")
    DirCreate(DataDir "\licenses")
    FileInstall "LICENSE", DataDir "\licenses\Project-MIT.txt", 1
    FileInstall "THIRD_PARTY_NOTICES.md", DataDir "\licenses\THIRD_PARTY_NOTICES.md", 1
    FileInstall "THIRD_PARTY_NOTICES.en.md", DataDir "\licenses\THIRD_PARTY_NOTICES.en.md", 1
    FileInstall "assets\interception.dll", DataDir "\components\interception.dll", 1
    FileInstall "assets\volume-guard.dll", DataDir "\components\volume-guard.dll", 1
    FileInstall "assets\install-interception.exe", DataDir "\components\install-interception.exe", 1
    FileInstall "assets\AutoHotkey-license.txt", DataDir "\licenses\AutoHotkey-license.txt", 1
    FileInstall "assets\LGPL-3.0.txt", DataDir "\licenses\LGPL-3.0.txt", 1
    FileInstall "assets\GPL-3.0.txt", DataDir "\licenses\GPL-3.0.txt", 1
    FileInstall "assets\Interception-API.pdf", DataDir "\licenses\Interception-API.pdf", 1
    FileInstall "assets\Interception.pdf", DataDir "\licenses\Interception.pdf", 1
    FileInstall "assets\README.txt", DataDir "\README.txt", 1
    FileInstall "assets\README.en.txt", DataDir "\README.en.txt", 1
    FileInstall "assets\mic-air-original.png", DataDir "\components\mic-air-original.png", 1
    FileInstall "assets\voice-illustration.png", DataDir "\components\voice-illustration.png", 1
    if SHA256File(DataDir "\components\interception.dll") != "AB88164C11B1B48488772D4C3BFAA4509D5B0AE9DBC5A691DC4F96F0260443C8"
        throw Error(L("按键发送组件校验失败。", "The key output component failed verification."))
    if SHA256File(DataDir "\components\volume-guard.dll") != "4074165CC363B2351C3D0AB9AF082FECCC373F8C6291C66095887CA65FA19C7D"
        throw Error(L("音量保护组件校验失败。", "The volume protection component failed verification."))
    if SHA256File(DataDir "\components\install-interception.exe") != "E137863A79DA797F08E7A137280FF2A123809044A888FD75CE9C973198915ABE"
        throw Error(L("驱动安装组件校验失败。", "The driver installer failed verification."))
}

BuildGui() {
    global UI, AppTitle, DataDir, S
    g := Gui(, AppTitle)
    UI["window"] := g
    UI["advancedControls"] := []
    g.BackColor := "F8FAF9"
    g.MarginX := 28
    g.MarginY := 24
    g.SetFont("s12 bold c63776D", "Segoe UI Variable Display")
    UI["brand"] := g.AddText("x28 y22 w300 h24", "")
    g.SetFont("s10 norm c71827B", "Microsoft YaHei UI")
    UI["mapping"] := g.AddText("x350 y24 w142 h24 Right", "")

    g.SetFont("s23 bold c172E2A")
    UI["headline"] := g.AddText("x28 y54 w464 h42", "")

    g.AddPicture("x70 y116 w128 h128", DataDir "\components\mic-air-original.png")
    doubaoIcon := FindDoubaoIcon()
    fallbackVoiceArt := DataDir "\components\voice-illustration.png"
    try g.AddPicture("x330 y124 w112 h112", doubaoIcon != "" ? doubaoIcon : fallbackVoiceArt)
    catch
        g.AddPicture("x330 y124 w112 h112", fallbackVoiceArt)
    g.SetFont("s23 norm cA8B9B0")
    g.AddText("x242 y161 w36 h42 Center", "→")
    g.SetFont("s11 bold c29433C")
    UI["micAction"] := g.AddText("x28 y249 w212 h28 Center", "")
    UI["voiceTarget"] := g.AddText("x280 y249 w212 h28 Center", "")
    g.SetFont("s9 norm c71827B")
    g.AddText("x28 y281 w212 h23 Center", "Insta360 Mic Air")
    UI["shortcutSummary"] := g.AddText("x260 y281 w250 h38 Center", ShortcutDisplayLabel(S.binding))

    g.SetFont("s11 bold cFFFFFF")
    UI["enable"] := ModernButton(g, "x28 y328 w464 h50", "启用语音按钮")
    UI["enable"].OnEvent("Click", TogglePower)
    g.SetFont("s10 norm c71827B")
    UI["notice"] := g.AddText("x30 y390 w462 h64", "")

    g.SetFont("s9 norm c71827B")
    UI["advanced"] := ModernButton(g, "x22 y458 w142 h32", "设置", "ghost")
    UI["advanced"].OnEvent("Click", (*) => ToggleAdvanced())
    UI["help"] := ModernButton(g, "x190 y458 w142 h32", "使用说明", "ghost")
    UI["help"].OnEvent("Click", ShowUserGuide)
    UI["uninstall"] := ModernButton(g, "x358 y458 w142 h32", "卸载并恢复", "ghost")
    UI["uninstall"].OnEvent("Click", (*) => DriverOperation("uninstall"))
    g.SetFont("s8 c8C9993")
    UI["trayHint"] := g.AddText("x30 y504 w350 h22 Center", "")
    g.SetFont("s9 norm c71827B")
    UI["language"] := ModernButton(g, "x398 y498 w102 h30", "English", "ghost")
    UI["language"].OnEvent("Click", SwitchLanguage)

    g.SetFont("s11 bold c29433C")
    UI["shortcutHeading"] := g.AddText("x30 y557 w420 h28 Hidden", "")
    UI["advancedControls"].Push(UI["shortcutHeading"])
    g.SetFont("s10 norm c29433C")
    UI["shortcutSetting"] := g.AddText("x30 y591 w340 h38 Hidden", ShortcutDisplayLabel(S.binding))
    UI["editShortcut"] := ModernButton(g, "x396 y587 w96 h38 Hidden", "修改", "secondary")
    UI["editShortcut"].OnEvent("Click", EditShortcut)
    UI["advancedControls"].Push(UI["shortcutSetting"], UI["editShortcut"])
    g.SetFont("s9 c71827B")
    UI["shortcutHint"] := g.AddText("x30 y632 w462 h23 Hidden", "")
    UI["advancedControls"].Push(UI["shortcutHint"])
    g.SetFont("s9 c29433C")
    UI["refresh"] := ModernButton(g, "x22 y672 w220 h34 Hidden", "重新识别按钮", "ghost")
    UI["refresh"].OnEvent("Click", Reconfigure)
    UI["advancedControls"].Push(UI["refresh"])

    g.OnEvent("Close", RequestExit)
    g.OnEvent("Escape", RequestExit)
    ApplyLanguage()
    ConfigureTrayWindow(g, RestoreMainWindow)
    A_IconTip := AppTitle
    ; Windows 11 uses rounded top-level corners when available.
    corner := 2
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 33, "Int*", &corner, "UInt", 4)
    captionColor := 0xF9FAF8
    captionText := 0x2A2E17
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 35, "UInt*", &captionColor, "UInt", 4)
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 36, "UInt*", &captionText, "UInt", 4)
    g.Show("w520 h548")
}

AppWindowTitle() {
    global PersonalEdition
    title := L("AirKey · 语音键 — Insta360 Mic Air", "AirKey — Insta360 Mic Air")
    return title (PersonalEdition ? L(" · 自用版", " · Personal") : "")
}

SwitchLanguage(*) {
    global S, ConfigPath
    if S.busy || S.editing || S.maintenance || S.held.keys.Length
        || (S.HasOwnProp("settingUp") && S.settingUp)
        return
    try SaveAppLanguage(AppLanguage.Current == "zh" ? "en" : "zh", ConfigPath)
    catch as err {
        S.notice := N("语言设置未保存：{1}", "Could not save the language setting: {1}", ErrorText(err))
        UpdateUI()
        return
    }
    ApplyLanguage()
}

ApplyLanguage() {
    global UI, S, AppTitle
    AppTitle := AppWindowTitle()
    UI["window"].Title := AppTitle
    UI["brand"].Text := L("AirKey · 语音键", "AirKey")
    UI["headline"].SetFont(L("s23", "s21"))
    UI["headline"].Text := L("一键开启豆包语音", "One press. Start speaking.")
    UI["micAction"].Text := L("按下侧边按钮", "Press the side button")
    UI["voiceTarget"].Text := L("豆包输入法", "Doubao IME")
    UI["advanced"].Text := S.advancedOpen ? L("收起设置", "Hide Settings") : L("设置", "Settings")
    UI["help"].Text := L("使用说明", "User Guide")
    UI["uninstall"].Text := L("卸载并恢复", "Uninstall && Restore")
    UI["trayHint"].Text := L("最小化到托盘 · 点击托盘图标恢复", "Minimize to tray · Click icon to reopen")
    UI["language"].Text := L("English", "中文")
    UI["shortcutHeading"].Text := L("启动豆包的快捷键", "Shortcut for Doubao voice input")
    UI["shortcutHint"].Text := L("请与豆包里的快捷键保持一致。", "Use the same shortcut as in your Doubao settings.")
    UI["refresh"].Text := L("重新识别按钮", "Set Up Button Again")
    UI["editShortcut"].Text := L("修改", "Edit")
    UpdateTrayMenu()
    UpdateUI()
}

UpdateTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add(L("打开界面", "Open AirKey"), RestoreMainWindow)
    A_TrayMenu.Add(L("停止并恢复音量键", "Pause and Restore Volume Key"), (*) => StopMapping(true))
    A_TrayMenu.Add()
    A_TrayMenu.Add(L("退出程序", "Exit"), RequestExit)
    A_TrayMenu.Default := L("打开界面", "Open AirKey")
}

ShowUserGuide(*) {
    global DataDir
    Run('"' DataDir L('\README.txt"', '\README.en.txt"'))
}

RestoreMainWindow(*) {
    global UI
    RestoreTrayWindow(UI["window"], CurrentShortcutWindow)
}

CurrentShortcutWindow() {
    if IsObject(MicSetupStore.Active) && !MicSetupStore.Active.closed
        return MicSetupStore.Active.window
    dialog := ShortcutRecorderStore.Active
    return IsObject(dialog) && !dialog.closed ? dialog.window : 0
}

ToggleAdvanced(forceOpen := false) {
    global UI, S
    S.advancedOpen := forceOpen || !S.advancedOpen
    for control in UI["advancedControls"]
        control.Visible := S.advancedOpen
    UI["advanced"].Text := S.advancedOpen ? L("收起设置", "Hide Settings") : L("设置", "Settings")
    ModernRedraw(UI["advanced"])
    UI["window"].Show(S.advancedOpen ? "w520 h728" : "w520 h548")
}

EditShortcut(*) {
    global S, UI
    if S.editing || S.busy || S.maintenance || S.held.keys.Length || MicSetupActive()
        return
    S.editorResume := S.enabled
    StopMapping(false)
    S.editing := true
    try ShowShortcutRecorder(UI["window"], S.binding, SaveShortcut, FinishShortcutEdit)
    catch as err {
        FinishShortcutEdit()
        S.notice := N("无法打开快捷键设置：{1}", "Could not open shortcut settings: {1}", ErrorText(err))
        UpdateUI()
    }
}

SaveShortcut(binding) {
    global S, ConfigPath
    validated := ParseShortcut(binding.canonical)
    IniWrite(validated.canonical, ConfigPath, "Mapping", "Shortcut")
    if S.HasOwnProp("profile") && IsObject(S.profile) && S.binding.canonical != validated.canonical {
        InvalidateMicProfile(ConfigPath)
        S.profile := 0
    }
    S.binding := validated
    UpdateUI()
}

FinishShortcutEdit(*) {
    global S, UI
    S.editing := false
    UI["window"].Opt("-Disabled")
    if S.editorResume
        EnableMapping()
    else {
        S.notice := N("请确保这里的快捷键与豆包设置一致。", "Make sure this shortcut matches your Doubao settings.")
        UpdateUI()
    }
}

TogglePower(*) {
    global S
    if S.enabled
        StopMapping(true)
    else
        InstallOrEnable()
}


RefreshDriver() {
    global S, Driver, ConfigPath, UI, DataDir
    if S.maintenance || S.busy
        return
    StopMapping(false)
    if !CloseNative() {
        UpdateUI()
        return
    }
    Driver := GetDriverStatus()
    pendingAction := IniRead(ConfigPath, "Driver", "PendingAction", "")
    previousBoot := IniRead(ConfigPath, "Driver", "BootId", "")
    S.pendingReboot := Driver.pending || (pendingAction != "" && (Driver.bootId = "" || previousBoot = Driver.bootId))
    if pendingAction && !S.pendingReboot {
        IniDelete(ConfigPath, "Driver", "PendingAction")
        IniDelete(ConfigPath, "Driver", "BootId")
    }
    S.devices := []
    S.selected := 0
    S.notice := S.pendingReboot ? N("驱动操作尚需重启。请保存工作，手动重启 Windows 后再打开本程序。", "Save your work and restart Windows to finish the driver change. Then reopen AirKey.") :
        DriverReady() ? N("已准备就绪。点击“启用语音按钮”即可使用。", "Ready. Click Enable Voice Button to begin.") : Driver.description
    if DriverReady() && !S.pendingReboot {
        try {
            S.native := NativeOutput(DataDir "\components\interception.dll")
            S.devices := S.native.Enumerate()
            index := FindProfileOutput(S.devices, S.profile)
            if index {
                S.selected := index
            } else if IsObject(S.profile)
                S.notice := N("电脑连接发生变化，请重新识别按钮。", "The connection changed. Please set up the button again.")
            else
                S.notice := N("首次使用，按引导识别 Mic Air 按钮。", "First time here? Follow the guide to set up your Mic Air button.")
        } catch as err {
            S.notice := ErrorText(err)
            CloseNative()
        }
    }
    UpdateUI()
    Log("refresh installed=" Driver.installed " running=" Driver.running " pending=" S.pendingReboot " keyboards=" S.devices.Length)
}

Reconfigure(*) {
    BeginMicSetup()
}

InstallOrEnable(*) {
    global Driver, S
    if S.maintenance || S.pendingReboot || MicSetupActive()
        return
    if DriverReady() {
        if !IsObject(S.profile) || !S.selected
            BeginMicSetup()
        else
            EnableMapping()
    }
    else
        DriverOperation("install")
}

EnableMapping(*) {
    global S, Driver, ConfigPath, DataDir
    if S.enabled || S.maintenance || S.pendingReboot || S.editing || S.held.keys.Length || !DriverReady() || MicSetupActive()
        return
    if !IsObject(S.profile) {
        BeginMicSetup()
        return
    }
    ; Re-resolve a verified output after reconnects or a cancelled setup. A stale
    ; array index must never silently select another keyboard.
    try {
        S.devices := IsObject(S.native) ? S.native.Enumerate() : []
        S.selected := FindProfileOutput(S.devices, S.profile)
    } catch {
        S.selected := 0
    }
    if S.selected < 1 || !IsObject(S.native) {
        S.notice := N("连接已发生变化，请重新识别按钮。", "The connection changed. Please set up the button again.")
        UpdateUI()
        ToggleAdvanced(true)
        return
    }
    if WinExist("Mic Air → 豆包：驱动发送测试 ahk_class AutoHotkeyGUI") {
        S.notice := N("旧版测试窗口仍在运行。请先关闭旧版窗口，再点击启用。", "An older test window is still running. Close it before enabling AirKey.")
        UpdateUI()
        return
    }
    try {
        InstallKeybdHook()
        if !IsObject(S.button)
            S.button := MicButtonInput(DataDir "\components\volume-guard.dll")
        S.button.Start(S.profile, VolumeTrigger, MicInputFault)
        S.hotkey := true
        S.enabled := true
        S.faulted := false
        S.armed := true
        SetTimer(RearmVolume, 100)
        S.savedHid := S.devices[S.selected].hid
        S.resume := true
        IniWrite(S.savedHid, ConfigPath, "Mapping", "HardwareId")
        IniWrite(1, ConfigPath, "Mapping", "EnableOnLaunch")
        S.notice := N("按 Mic Air 启动豆包语音。`n音量＋已接管，调音量请用系统滑块。", "Press Mic Air to start Doubao voice input.`nVolume Up is remapped; use the system volume slider.")
        Log("mapping_enabled mode=" S.profile.source " keyboard=" S.devices[S.selected].id)
    } catch as err {
        StopMapping(true)
        S.notice := N("暂时无法启用：{1}", "Could not enable: {1}", ErrorText(err))
    }
    UpdateUI()
}

StopMapping(save := true) {
    global S, ConfigPath
    Critical("On")
    inputStopped := true
    S.enabled := false
    try {
        if MicSetupActive() {
            S.setup.priorEnabled := false
            if !FinishMicSetup()
                inputStopped := false
        }
        if S.hotkey || (S.HasOwnProp("button") && IsObject(S.button)) {
            try {
                if S.HasOwnProp("button") && IsObject(S.button)
                    S.button.Stop()
                else
                    Hotkey("Volume_Up", "Off")
                S.hotkey := false
            } catch {
                inputStopped := false
                Log("button_stop_failed")
            }
        }
        SetTimer(RearmVolume, 0)
        if save {
            S.resume := false
            if S.editing
                S.editorResume := false
            IniWrite(0, ConfigPath, "Mapping", "EnableOnLaunch")
        }
        S.notice := inputStopped ? N("已停止，音量＋恢复原来的功能。", "Paused. Volume Up works normally again.") :
            N("已暂停，但按钮监听未完全停止。请退出程序后重新打开。", "Paused, but the button listener could not fully stop. Exit and reopen AirKey.")
        Log("mapping_stopped")
    } catch as err {
        S.notice := N("已停止，但设置未能保存：{1}", "Stopped, but the setting could not be saved: {1}", ErrorText(err))
    } finally {
        ReleaseHeldKeys()
        Critical("Off")
        UpdateUI()
    }
}

VolumeTrigger(*) {
    global S
    S.lastVolume := A_TickCount
    Log("button_received")
    if !S.enabled || !S.armed || S.busy
        return
    S.armed := false
    SendShortcut("volume_up")
}

RearmVolume() {
    global S
    if S.enabled && !S.armed && !S.busy && A_TickCount - S.lastVolume >= 1500
        && !GetKeyState("Volume_Up", "P")
        S.armed := true
}

SendShortcut(source) {
    global S, ConfigPath
    if !S.enabled || S.busy || !S.selected || S.maintenance || S.editing
        return
    Critical("On")
    S.busy := true
    try {
        for key in ["LAlt", "RAlt", "LCtrl", "RCtrl", "LShift", "RShift", "LWin", "RWin", S.binding.keys[S.binding.keys.Length].ahkName] {
            if GetKeyState(key, "P") {
                S.notice := N("请先松开键盘上的快捷键，再按 Mic Air 按钮。", "Release the shortcut keys before pressing the Mic Air button.")
                Log("send_skipped held_key")
                return
            }
        }
        device := S.devices[S.selected].id
        SendConfiguredShortcut(S.native, device, S.binding, S.held)
        S.notice := N("按 Mic Air 启动豆包语音。`n音量＋已接管，调音量请用系统滑块。", "Press Mic Air to start Doubao voice input.`nVolume Up is remapped; use the system volume slider.")
        Log("sequence_delivered source=" source " keyboard=" device " shortcut=" S.binding.canonical)
    } catch as err {
        S.faulted := true
        S.notice := N("已停止：{1}", "Stopped: {1}", ErrorText(err))
        Log("send_error " err.Message)
    } finally {
        ReleaseHeldKeys()
        S.busy := false
        if S.faulted {
            S.enabled := false
            S.resume := false
            if S.hotkey {
                try {
                    if S.HasOwnProp("button") && IsObject(S.button)
                        S.button.Stop()
                    else
                        Hotkey("Volume_Up", "Off")
                    S.hotkey := false
                } catch {
                    Log("button_stop_failed")
                }
            }
            try IniWrite(0, ConfigPath, "Mapping", "EnableOnLaunch")
            SetTimer(RearmVolume, 0)
        }
        Critical("Off")
        UpdateUI()
    }
}

ReleaseHeldKeys() {
    global S
    if !IsObject(S.native)
        return
    if !ReleaseConfiguredKeys(S.native, S.held) {
        S.faulted := true
        S.notice := N("部分按键未能释放，请手动按下并松开设置中的快捷键，再退出程序。", "Some keys could not be released. Press and release your configured shortcut manually before exiting.")
    }
}

DriverOperation(action) {
    global S, Driver, DataDir, ConfigPath
    if S.maintenance || S.busy || S.pendingReboot || S.editing || S.held.keys.Length || !Driver.known || MicSetupActive()
        return
    if WinExist("Mic Air → 豆包：驱动发送测试 ahk_class AutoHotkeyGUI") {
        S.notice := N("请先关闭旧版测试窗口，再进行驱动操作。", "Close the older test window before changing the driver.")
        UpdateUI()
        return
    }
    StopMapping(true)
    CloseNative()
    S.maintenance := true
    S.notice := N("请在 Windows 管理员确认窗口中允许本次操作。完成后需要手动重启。", "Allow this change in the Windows administrator prompt. Restart Windows when it finishes.")
    UpdateUI()
    bootBefore := Driver.bootId
    try {
        result := RunDriverOperation(action, DataDir "\components\install-interception.exe")
        Log("driver_operation " action " ok=" result.ok " cancelled=" result.cancelled " exit=" result.exitCode)
        if result.needsReboot {
            IniWrite(action, ConfigPath, "Driver", "PendingAction")
            IniWrite(bootBefore, ConfigPath, "Driver", "BootId")
            S.resume := result.ok && action = "install"
            IniWrite(S.resume ? 1 : 0, ConfigPath, "Mapping", "EnableOnLaunch")
            if result.ok && action = "uninstall" {
                S.savedHid := ""
                IniDelete(ConfigPath, "Mapping", "HardwareId")
                S.profile := 0
                InvalidateMicProfile(ConfigPath)
            }
        }
        S.maintenance := false
        RefreshDriver()
        S.notice := result.ok ? (action = "install" ? N("安装已完成。请重启 Windows，再打开本 EXE 启用。", "Installation complete. Restart Windows, then reopen AirKey to enable it.") :
            N("卸载已完成。请重启 Windows；之后可直接删除本 EXE。", "Uninstalled. Restart Windows, then you can delete this app.")) :
            N("{1}{2}", "{1}{2}", result.message, result.needsReboot ? N(" 请先重启 Windows，再检查状态。", " Restart Windows before checking the status again.") : "")
    } catch as err {
        S.maintenance := false
        RefreshDriver()
        S.notice := N("操作未完成：{1}", "The operation did not finish: {1}", ErrorText(err))
        Log("driver_operation_error " err.Message)
    } finally {
        S.maintenance := false
        UpdateUI()
    }
}

UpdateUI() {
    global UI, S, Driver
    if !UI.Has("window") || !IsObject(Driver)
        return
    needsSetup := !IsObject(S.profile) || !S.selected
    UI["mapping"].Text := S.enabled ? L("● 已开启", "● On") : S.pendingReboot ? L("● 等待重启", "● Restart needed") : DriverReady() && needsSetup ? L("● 待设置", "● Set up required") : L("● 已关闭", "● Off")
    UI["mapping"].SetFont(S.enabled ? "c16816A" : "c63718A")
    UI["enable"].Text := S.enabled ? L("暂停语音按钮", "Pause Voice Button") : DriverReady() ? (needsSetup ? L("设置语音按钮", "Set Up Voice Button") : L("启用语音按钮", "Enable Voice Button")) : L("安装并启用", "Install && Enable")
    UI["enable"].Enabled := !S.maintenance && !S.editing && (S.enabled || (Driver.known && !Driver.serviceConflict && !S.pendingReboot && !S.held.keys.Length))
    UI["refresh"].Enabled := !S.maintenance && !S.busy && !S.pendingReboot && !S.held.keys.Length && !S.editing
    UI["editShortcut"].Enabled := !S.maintenance && !S.busy && !S.held.keys.Length && !S.editing
    UI["shortcutSummary"].Text := ShortcutDisplayLabel(S.binding)
    UI["shortcutSetting"].Text := ShortcutDisplayLabel(S.binding)
    UI["uninstall"].Enabled := Driver.known && !Driver.serviceConflict && !S.maintenance && !S.busy && !S.held.keys.Length && !S.pendingReboot && (Driver.installed || Driver.running || Driver.partial)
    UI["notice"].Text := Text(S.notice)
    UI["language"].Enabled := !S.maintenance && !S.busy && !S.editing && !S.held.keys.Length
    if MicSetupActive()
        for name in ["enable", "refresh", "editShortcut", "uninstall", "language"]
            UI[name].Enabled := false
    A_IconTip := L("AirKey · 语音键", "AirKey") " · " (S.enabled ? L("已启用", "On") : L("已停止", "Off"))
    for name in ["enable", "advanced", "help", "uninstall", "refresh", "editShortcut", "language"]
        ModernRedraw(UI[name])
}

RequestExit(*) {
    global S
    if S.maintenance {
        S.notice := N("驱动操作进行中，请等待完成后再退出。", "A driver operation is in progress. Wait for it to finish before exiting.")
        UpdateUI()
        return true
    }
    ExitApp()
}

DriverReady() {
    global Driver
    return IsObject(Driver) && Driver.known && Driver.installed && Driver.running && !Driver.partial && !Driver.serviceConflict
}

CloseNative() {
    global S
    ReleaseHeldKeys()
    if S.held.keys.Length
        return false
    if IsObject(S.native) {
        S.native.Close()
        S.native := 0
    }
    return true
}

Cleanup(*) {
    global S
    try CloseShortcutRecorderForExit()
    if MicSetupActive()
        try FinishMicSetup()
    if IsObject(S.button)
        try S.button.Close()
    SetTimer(RearmVolume, 0)
    ReleaseHeldKeys()
    CloseNative()
    if S.mutex {
        DllCall("Kernel32\CloseHandle", "Ptr", S.mutex)
        S.mutex := 0
    }
    Log("exit")
}

Log(message) {
    global LogPath
    if LogPath {
        try {
            if FileExist(LogPath) && FileGetSize(LogPath) > 1048576
                FileMove(LogPath, LogPath ".previous", 1)
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", LogPath, "UTF-8")
        }
    }
}

RunSelfTest() {
    global DataDir
    status := GetDriverStatus()
    report := "AirKey 1.3.0 self-check`r`nNo hotkeys registered; no keyboard events sent; no driver changes.`r`n"
    report .= "Assets SHA256 verified.`r`nDriver installed=" status.installed " running=" status.running " pending=" status.pending "`r`n"
    if status.running && !status.pending {
        native := NativeOutput(DataDir "\components\interception.dll")
        try {
            devices := native.Enumerate()
            report .= "Enumerated keyboards=" devices.Length "`r`n"
        } finally
            native.Close()
    }
    FileOpen(DataDir "\self-test.txt", "w", "UTF-8").Write(report)
}
