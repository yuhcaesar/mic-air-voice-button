#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#MaxThreadsPerHotkey 1
#Include DriverManager.ahk
#Include NativeOutput.ahk
#Include ModernControls.ahk
#Include ShortcutConfig.ahk
#Include ShortcutRecorder.ahk
#Include AppArtwork.ahk
;@Ahk2Exe-SetName Mic Air Voice Button
;@Ahk2Exe-SetDescription Mic Air to Doubao voice input
;@Ahk2Exe-SetVersion 1.0.7.0
;@Ahk2Exe-SetOrigFilename MicAirDoubao.exe

global AppTitle := "Mic Air 语音按钮"
global DataDir := EnvGet("LOCALAPPDATA") "\MicAirDoubao"
global SelfTest := false, TestUI := false
global S := {enabled: false, busy: false, maintenance: false, advancedOpen: false,
    faulted: false, hotkey: false, armed: true, lastVolume: 0,
    held: {keys: []}, binding: 0, editing: false, editorResume: false,
    native: 0, devices: [], selected: 0, mutex: 0,
    notice: "启用后，按 Mic Air 按钮即可启动豆包语音。",
    pendingReboot: false, savedHid: "", resume: false}
global UI := Map(), ConfigPath := "", LogPath := "", Driver := 0

try {
    ParseArguments()
    nativeMachine := 0, processMachine := 0
    try {
        if DllCall("Kernel32\IsWow64Process2", "Ptr", -1, "UShort*", &processMachine, "UShort*", &nativeMachine)
            && nativeMachine != 0x8664
            throw Error("本程序需要 Intel／AMD 的 64 位 Windows，当前系统架构不适用。")
    } catch as archError {
        if nativeMachine && nativeMachine != 0x8664
            throw archError
    }
    ConfigPath := DataDir "\settings.ini"
    LogPath := DataDir "\activity.log"
    if !SelfTest
        ClaimInstance()
    OnExit(Cleanup)
    ExtractAssets()
    if SelfTest {
        RunSelfTest()
        ExitApp(0)
    }
    S.savedHid := IniRead(ConfigPath, "Mapping", "HardwareId", "")
    S.resume := IniRead(ConfigPath, "Mapping", "EnableOnLaunch", "0") = "1"
    try S.binding := ParseShortcut(IniRead(ConfigPath, "Mapping", "Shortcut", "RAlt+Space"))
    catch {
        S.binding := ParseShortcut("RAlt+Space")
        S.resume := false
        Log("Invalid saved shortcut; default restored with mapping paused.")
    }
    BuildGui()
    RefreshDriver()
    if S.resume && !TestUI && !S.pendingReboot && DriverReady()
        EnableMapping()
} catch as err {
    if SelfTest {
        try FileAppend("FAIL: " err.Message "`n", DataDir "\self-test.txt", "UTF-8")
    } else
        MsgBox("程序无法启动：" err.Message, AppTitle, "Icon!")
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
                throw Error("数据目录必须是本机绝对路径。")
        } else
            throw Error("不支持的启动参数。")
        i++
    }
}

ClaimInstance() {
    global S, AppTitle
    S.mutex := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 0,
        "Str", "Local\MicAirDoubao.ControlPanel.v1", "Ptr")
    if !S.mutex
        throw Error("无法建立单实例保护。")
    if A_LastError = 183 {
        DllCall("Kernel32\CloseHandle", "Ptr", S.mutex)
        S.mutex := 0
        if WinExist(AppTitle " ahk_class AutoHotkeyGUI") {
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
    FileInstall "assets\interception.dll", DataDir "\components\interception.dll", 1
    FileInstall "assets\install-interception.exe", DataDir "\components\install-interception.exe", 1
    FileInstall "assets\AutoHotkey-license.txt", DataDir "\licenses\AutoHotkey-license.txt", 1
    FileInstall "assets\LGPL-3.0.txt", DataDir "\licenses\LGPL-3.0.txt", 1
    FileInstall "assets\GPL-3.0.txt", DataDir "\licenses\GPL-3.0.txt", 1
    FileInstall "assets\Interception-API.pdf", DataDir "\licenses\Interception-API.pdf", 1
    FileInstall "assets\Interception.pdf", DataDir "\licenses\Interception.pdf", 1
    FileInstall "assets\README.txt", DataDir "\README.txt", 1
    FileInstall "assets\mic-air-original.png", DataDir "\components\mic-air-original.png", 1
    FileInstall "assets\voice-illustration.png", DataDir "\components\voice-illustration.png", 1
    if SHA256File(DataDir "\components\interception.dll") != "AB88164C11B1B48488772D4C3BFAA4509D5B0AE9DBC5A691DC4F96F0260443C8"
        throw Error("按键发送组件校验失败。")
    if SHA256File(DataDir "\components\install-interception.exe") != "E137863A79DA797F08E7A137280FF2A123809044A888FD75CE9C973198915ABE"
        throw Error("驱动安装组件校验失败。")
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
    g.AddText("x28 y22 w270 h24", "Insta360 Mic Air")
    g.SetFont("s10 norm c71827B", "Microsoft YaHei UI")
    UI["mapping"] := g.AddText("x350 y24 w142 h24 Right", "● 已关闭")

    g.SetFont("s23 bold c172E2A")
    g.AddText("x28 y54 w464 h42", "一键开启豆包语音")

    g.AddPicture("x70 y116 w128 h128", DataDir "\components\mic-air-original.png")
    doubaoIcon := FindDoubaoIcon()
    fallbackVoiceArt := DataDir "\components\voice-illustration.png"
    try g.AddPicture("x330 y124 w112 h112", doubaoIcon != "" ? doubaoIcon : fallbackVoiceArt)
    catch
        g.AddPicture("x330 y124 w112 h112", fallbackVoiceArt)
    g.SetFont("s23 norm cA8B9B0")
    g.AddText("x242 y161 w36 h42 Center", "→")
    g.SetFont("s11 bold c29433C")
    g.AddText("x28 y249 w212 h28 Center", "按下侧边按钮")
    g.AddText("x280 y249 w212 h28 Center", "豆包输入法")
    g.SetFont("s9 norm c71827B")
    g.AddText("x28 y281 w212 h23 Center", "Mic Air")
    UI["shortcutSummary"] := g.AddText("x260 y281 w250 h23 Center", S.binding.label)

    g.SetFont("s11 bold cFFFFFF")
    UI["enable"] := ModernButton(g, "x28 y328 w464 h50", "启用语音按钮")
    UI["enable"].OnEvent("Click", TogglePower)
    g.SetFont("s10 norm c71827B")
    UI["notice"] := g.AddText("x30 y396 w462 h48", "")

    g.SetFont("s9 norm c71827B")
    UI["advanced"] := ModernButton(g, "x22 y458 w142 h32", "设置", "ghost")
    UI["advanced"].OnEvent("Click", (*) => ToggleAdvanced())
    UI["help"] := ModernButton(g, "x190 y458 w142 h32", "使用说明", "ghost")
    UI["help"].OnEvent("Click", (*) => Run('"' DataDir '\README.txt"'))
    UI["uninstall"] := ModernButton(g, "x358 y458 w142 h32", "卸载并恢复", "ghost")
    UI["uninstall"].OnEvent("Click", (*) => DriverOperation("uninstall"))
    g.SetFont("s8 c8C9993")
    g.AddText("x30 y504 w462 h22 Center", "最小化继续运行 · 关闭窗口即停止")

    g.SetFont("s11 bold c29433C")
    UI["advancedControls"].Push(g.AddText("x30 y557 w320 h28 Hidden", "启动豆包的快捷键"))
    g.SetFont("s10 norm c29433C")
    UI["shortcutSetting"] := g.AddText("x30 y595 w340 h28 Hidden", S.binding.label)
    UI["editShortcut"] := ModernButton(g, "x396 y587 w96 h38 Hidden", "修改", "secondary")
    UI["editShortcut"].OnEvent("Click", EditShortcut)
    UI["advancedControls"].Push(UI["shortcutSetting"], UI["editShortcut"])
    g.SetFont("s9 c71827B")
    UI["advancedControls"].Push(g.AddText("x30 y632 w462 h23 Hidden", "请与豆包里的快捷键保持一致。"))
    g.SetFont("s9 c29433C")
    UI["refresh"] := ModernButton(g, "x22 y672 w170 h34 Hidden", "修复按钮响应", "ghost")
    UI["refresh"].OnEvent("Click", Reconfigure)
    UI["advancedControls"].Push(UI["refresh"])

    g.OnEvent("Close", RequestExit)
    g.OnEvent("Escape", RequestExit)
    A_TrayMenu.Delete()
    A_TrayMenu.Add("打开控制面板", (*) => g.Show())
    A_TrayMenu.Add("停止并恢复音量键", (*) => StopMapping(true))
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出程序", RequestExit)
    A_TrayMenu.Default := "打开控制面板"
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

ToggleAdvanced(forceOpen := false) {
    global UI, S
    S.advancedOpen := forceOpen || !S.advancedOpen
    for control in UI["advancedControls"]
        control.Visible := S.advancedOpen
    UI["advanced"].Text := S.advancedOpen ? "收起设置" : "设置"
    ModernRedraw(UI["advanced"])
    UI["window"].Show(S.advancedOpen ? "w520 h728" : "w520 h548")
}

EditShortcut(*) {
    global S, UI
    if S.editing || S.busy || S.maintenance || S.held.keys.Length
        return
    S.editorResume := S.enabled
    StopMapping(false)
    S.editing := true
    try ShowShortcutRecorder(UI["window"], S.binding, SaveShortcut, FinishShortcutEdit)
    catch as err {
        FinishShortcutEdit()
        S.notice := "无法打开快捷键设置：" err.Message
        UpdateUI()
    }
}

SaveShortcut(binding) {
    global S, ConfigPath
    validated := ParseShortcut(binding.canonical)
    IniWrite(validated.canonical, ConfigPath, "Mapping", "Shortcut")
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
        S.notice := "快捷键：" S.binding.label "。请与豆包里的设置保持一致。"
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
    CloseNative()
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
    S.notice := S.pendingReboot ? "驱动操作尚需重启。请保存工作，手动重启 Windows 后再打开本程序。" :
        DriverReady() ? "已准备就绪。点击“启用语音按钮”即可使用。" : Driver.description
    if DriverReady() && !S.pendingReboot {
        try {
            S.native := NativeOutput(DataDir "\components\interception.dll")
            S.devices := S.native.Enumerate()
            index := FindDeviceSelection(S.devices, S.savedHid)
            if index {
                S.selected := index
            } else if S.savedHid
                S.notice := "电脑连接发生变化。点击“修复按钮响应”即可重新准备。"
            else if S.devices.Length
                S.notice := "暂时无法完成配置。请重新连接接收器，再点“修复按钮响应”。"
            else
                S.notice := "暂时无法完成配置。请重新连接接收器，再点“修复按钮响应”。"
        } catch as err {
            S.notice := err.Message
            CloseNative()
        }
    }
    UpdateUI()
    Log("refresh installed=" Driver.installed " running=" Driver.running " pending=" S.pendingReboot " keyboards=" S.devices.Length)
}

Reconfigure(*) {
    global S, ConfigPath
    if S.busy || S.maintenance || S.pendingReboot || S.held.keys.Length || S.editing
        return
    wasEnabled := S.enabled
    previousHid := S.savedHid
    S.savedHid := ""
    RefreshDriver()
    if DriverReady() && S.selected {
        S.savedHid := S.devices[S.selected].hid
        IniWrite(S.savedHid, ConfigPath, "Mapping", "HardwareId")
        S.notice := "已重新检测，可以继续使用。"
        if wasEnabled
            EnableMapping()
    } else {
        S.savedHid := previousHid
        S.notice := S.pendingReboot ? "请先重启电脑，再打开本程序。" :
            !Driver.known ? "暂时无法确认系统状态，请重新打开程序。" :
            !Driver.installed ? "请先点击“安装并启用”，完成后重启电脑。" :
            "暂时无法完成配置。请重新连接接收器，或重启电脑后再试。"
    }
    UpdateUI()
}

InstallOrEnable(*) {
    global Driver, S
    if S.maintenance || S.pendingReboot
        return
    if DriverReady() {
        if !S.selected
            Reconfigure()
        if S.selected
            EnableMapping()
        else
            ToggleAdvanced(true)
    }
    else
        DriverOperation("install")
}

EnableMapping(*) {
    global S, Driver, ConfigPath
    if S.enabled || S.maintenance || S.pendingReboot || S.editing || S.held.keys.Length || !DriverReady()
        return
    if S.selected < 1 || !IsObject(S.native) {
        S.notice := "暂时无法启动。请点击“修复按钮响应”后再试。"
        UpdateUI()
        ToggleAdvanced(true)
        return
    }
    if WinExist("Mic Air → 豆包：驱动发送测试 ahk_class AutoHotkeyGUI") {
        S.notice := "旧版测试窗口仍在运行。请先关闭旧版窗口，再点击启用。"
        UpdateUI()
        return
    }
    try {
        InstallKeybdHook()
        Hotkey("Volume_Up", VolumeTrigger, "On")
        S.hotkey := true
        S.enabled := true
        S.faulted := false
        S.armed := true
        SetTimer(RearmVolume, 100)
        S.savedHid := S.devices[S.selected].hid
        S.resume := true
        IniWrite(S.savedHid, ConfigPath, "Mapping", "HardwareId")
        IniWrite(1, ConfigPath, "Mapping", "EnableOnLaunch")
        S.notice := "先点击输入框，再按 Mic Air 按钮。`n启用时，键盘上的音量＋也会启动豆包。"
        Log("mapping_enabled keyboard=" S.devices[S.selected].id)
    } catch as err {
        StopMapping(true)
        S.notice := "暂时无法启用：" err.Message
    }
    UpdateUI()
}

StopMapping(save := true) {
    global S, ConfigPath
    Critical("On")
    try {
        if S.hotkey {
            Hotkey("Volume_Up", "Off")
            S.hotkey := false
        }
        S.enabled := false
        SetTimer(RearmVolume, 0)
        ReleaseHeldKeys()
        if save {
            S.resume := false
            if S.editing
                S.editorResume := false
            IniWrite(0, ConfigPath, "Mapping", "EnableOnLaunch")
        }
        S.notice := S.held.keys.Length ? "释放按键失败，请手动按下并松开设置中的快捷键，再退出程序。" :
            "已停止，音量＋恢复原来的功能。"
        Log("mapping_stopped")
    } finally {
        Critical("Off")
    }
    UpdateUI()
}

VolumeTrigger(*) {
    global S
    S.lastVolume := A_TickCount
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
                S.notice := "请先松开键盘上的快捷键，再按 Mic Air 按钮。"
                return
            }
        }
        device := S.devices[S.selected].id
        SendConfiguredShortcut(S.native, device, S.binding, S.held)
        S.notice := "先点击输入框，再按 Mic Air 按钮。`n启用时，键盘上的音量＋也会启动豆包。"
        Log("sequence_delivered source=" source " keyboard=" device " shortcut=" S.binding.canonical)
    } catch as err {
        S.faulted := true
        S.notice := "已停止：" err.Message
        Log("send_error " err.Message)
    } finally {
        ReleaseHeldKeys()
        S.busy := false
        if S.faulted {
            if S.hotkey {
                Hotkey("Volume_Up", "Off")
                S.hotkey := false
            }
            S.enabled := false
            S.resume := false
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
        S.notice := "部分按键未能释放，请手动按下并松开设置中的快捷键，再退出程序。"
    }
}

DriverOperation(action) {
    global S, Driver, DataDir, ConfigPath
    if S.maintenance || S.busy || S.pendingReboot || S.editing || !Driver.known
        return
    if WinExist("Mic Air → 豆包：驱动发送测试 ahk_class AutoHotkeyGUI") {
        S.notice := "请先关闭旧版测试窗口，再进行驱动操作。"
        UpdateUI()
        return
    }
    StopMapping(true)
    CloseNative()
    S.maintenance := true
    S.notice := "请在 Windows 管理员确认窗口中允许本次操作。完成后需要手动重启。"
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
            }
        }
        S.maintenance := false
        RefreshDriver()
        S.notice := result.ok ? (action = "install" ? "安装已完成。请重启 Windows，再打开本 EXE 启用。" :
            "卸载已完成。请重启 Windows；之后可直接删除本 EXE。") : result.message
                . (result.needsReboot ? " 请先重启 Windows，再检查状态。" : "")
    } catch as err {
        S.maintenance := false
        RefreshDriver()
        S.notice := "操作未完成：" err.Message
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
    UI["mapping"].Text := S.enabled ? "● 已开启" : S.pendingReboot ? "● 等待重启" : "● 已关闭"
    UI["mapping"].SetFont(S.enabled ? "c16816A" : "c63718A")
    UI["enable"].Text := S.enabled ? "暂停语音按钮" : DriverReady() ? (S.selected ? "启用语音按钮" : "修复按钮响应") : "安装并启用"
    UI["enable"].Enabled := !S.maintenance && !S.editing && (S.enabled || (Driver.known && !Driver.serviceConflict && !S.pendingReboot && !S.held.keys.Length))
    UI["refresh"].Enabled := !S.maintenance && !S.busy && !S.pendingReboot && !S.held.keys.Length && !S.editing
    UI["editShortcut"].Enabled := !S.maintenance && !S.busy && !S.held.keys.Length && !S.editing
    UI["shortcutSummary"].Text := S.binding.label
    UI["shortcutSetting"].Text := S.binding.label
    UI["uninstall"].Enabled := Driver.known && !Driver.serviceConflict && !S.maintenance && !S.pendingReboot && (Driver.installed || Driver.running || Driver.partial)
    UI["notice"].Text := S.notice
    A_IconTip := "Mic Air 语音按钮 · " (S.enabled ? "已启用" : "已停止")
    for name in ["enable", "advanced", "help", "uninstall", "refresh", "editShortcut"]
        ModernRedraw(UI[name])
}

RequestExit(*) {
    global S
    if S.maintenance {
        S.notice := "驱动操作进行中，请等待完成后再退出。"
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
    if IsObject(S.native) {
        S.native.Close()
        S.native := 0
    }
}

Cleanup(*) {
    global S
    try CloseShortcutRecorderForExit()
    if S.hotkey
        try Hotkey("Volume_Up", "Off")
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
    report := "Mic Air 1.0.7 self-check`r`nNo hotkeys registered; no keyboard events sent; no driver changes.`r`n"
    report .= "Assets SHA256 verified.`r`nDriver installed=" status.installed " running=" status.running " pending=" status.pending "`r`n"
    if status.running && !status.pending {
        native := NativeOutput(DataDir "\components\interception.dll")
        try {
            devices := native.Enumerate()
            report .= "Enumerated keyboards=" devices.Length "`r`n"
            for device in devices
                report .= device.id ": " device.hid "`r`n"
        } finally
            native.Close()
    }
    sample := [{id: 1, hid: "ACPI\TEST"}, {id: 2, hid: "USB\TEST"}]
    if FindDeviceSelection(sample, "USB\TEST") != 2 || FindDeviceSelection(sample, "missing") != 0
        throw Error("Device matching self-check failed.")
    sample.Push({id: 3, hid: "USB\TEST"})
    if FindDeviceSelection(sample, "USB\TEST") != 0
        throw Error("Ambiguous device matching self-check failed.")
    report .= "Device matching (exact, missing, duplicate): PASS.`r`n"
    automaticSample := [{id: 1, hid: "LdVKeyboard"}, {id: 4, hid: "HID\VID_1234&PID_5678"}]
    if FindDeviceSelection(automaticSample, "") != 2
        throw Error("Automatic physical device matching self-check failed.")
    report .= "Automatic physical device selection: PASS.`r`n"
    FileOpen(DataDir "\self-test.txt", "w", "UTF-8").Write(report)
}
