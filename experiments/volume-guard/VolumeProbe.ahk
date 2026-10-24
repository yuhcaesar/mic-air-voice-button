#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Include ModernControls.ahk
;@Ahk2Exe-SetName AirKey Volume Check
;@Ahk2Exe-SetDescription Temporary volume-command suppression check for AirKey
;@Ahk2Exe-SetVersion 0.1.0.0
; This independent probe never sends keys, writes audio levels or edits AirKey settings.
global Probe := 0
try {
    Probe := VolumeProbe()
    OnExit((*) => Probe.Cleanup())
    if A_Args.Length && A_Args[1] = "--self-test" {
        Probe.SelfTest()
        ExitApp(0)
    }
    Probe.window.Show("w580 h530")
} catch as err {
    if A_Args.Length && A_Args[1] = "--self-test" {
        FileAppend("FAIL: " err.Message "`n" err.Stack, "*", "UTF-8")
        ExitApp(1)
    }
    MsgBox("无法打开音量验证：" err.Message, "AirKey 音量验证", "Icon!")
    ExitApp(1)
}

class VolumeProbe {
    __New() {
        this.module := 0, this.active := false, this.count := 0
        this.nativeStarted := false, this.everStarted := false, this.cleaned := false, this.initialVolume := ""
        this.mutex := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 0,
            "Str", "Local\AirKey.VolumeGuard.Probe.v1", "Ptr")
        if !this.mutex || A_LastError = 183
            throw Error("已有一个音量验证程序，请先关闭它。")
        this.tickCallback := ObjBindMethod(this, "Tick")
        this.commandCallback := ObjBindMethod(this, "Blocked")
        this.directory := A_Temp "\AirKeyVolumeProbe-" DllCall("GetCurrentProcessId", "UInt")
        if DirExist(this.directory)
            throw Error("临时目录已存在，请重新打开。")
        DirCreate(this.directory)
        this.dllPath := this.directory "\volume-guard.dll"
        try {
            FileInstall("native\volume-guard.dll", this.dllPath)
            this.module := DllCall("Kernel32\LoadLibraryExW", "Str", this.dllPath, "Ptr", 0, "UInt", 0x1100, "Ptr")
            if !this.module
                throw OSError()
            this.startAddress := DllCall("GetProcAddress", "Ptr", this.module, "AStr", "AirKeyGuardStart", "Ptr")
            this.stopAddress := DllCall("GetProcAddress", "Ptr", this.module, "AStr", "AirKeyGuardStop", "Ptr")
            if !this.startAddress || !this.stopAddress
                throw Error("验证组件不完整。")
            this.bridge := Gui("+ToolWindow", "AirKey.VolumeGuard.Probe.v1")
            this.SetProperty("AirKey.VolumeGuard.OwnerPID", DllCall("GetCurrentProcessId", "UInt"))
            this.SetProperty("AirKey.VolumeGuard.Deadline", 0)
            OnMessage(0x8047, this.commandCallback)
            this.Build()
        } catch as err {
            this.Cleanup()
            throw err
        }
    }

    Build() {
        g := Gui("-MaximizeBox", "AirKey · 音量拦截验证")
        this.window := g
        g.BackColor := "F8FAF9"
        g.SetFont("s10 c71827B", "Microsoft YaHei UI")
        g.AddText("x32 y24 w516 h24", "独立验证 · 不修改现有设置")
        g.SetFont("s21 bold c172E2A")
        g.AddText("x30 y62 w520 h42", "测试能否保持音量不变")
        g.SetFont("s10 norm c566D63")
        g.AddText("x32 y118 w516 h68", "保持 AirKey 已开启。点击下方“开始验证”，再点击输入框、按 Mic Air 按钮。`n也可切换到平常使用的软件里试一次。")
        g.SetFont("s11 c16816A")
        this.status := g.AddText("x32 y198 w516 h28", "尚未开始")
        g.SetFont("s10 c566D63")
        this.volume := g.AddText("x32 y234 w516 h28", "请同时留意系统音量是否变化。")
        this.input := g.AddEdit("x32 y276 w516 h70 +Multi +WantReturn -VScroll")
        g.SetFont("s9 c71827B")
        g.AddText("x32 y360 w516 h58", "验证期间临时拦截所有来源的音量＋媒体命令，音量滑块仍可用。`n60 秒后自动停止；关闭程序也会恢复。输入框内容不会保存。")
        g.SetFont("s11 bold")
        this.action := ModernButton(g, "x32 y434 w516 h46", "开始验证 · 60 秒", "primary")
        this.action.OnEvent("Click", ObjBindMethod(this, "Toggle"))
        g.SetFont("s9 norm c71827B")
        g.AddText("x32 y494 w516 h22", "验证目标：豆包能启动，音量不变，音量条不弹出。")
        g.OnEvent("Close", (*) => ExitApp())
        g.OnEvent("Escape", (*) => ExitApp())
    }

    SetProperty(name, value) {
        if !DllCall("User32\SetPropW", "Ptr", this.bridge.Hwnd, "Str", name, "Ptr", value, "Int")
            throw OSError()
    }

    Toggle(*) {
        if this.active || this.nativeStarted {
            this.Stop("已停止，音量按键恢复正常。")
            return
        }
        try {
            this.count := 0
            this.initialVolume := this.ReadVolume()
            this.endsAt := A_TickCount + 60000
            this.SetProperty("AirKey.VolumeGuard.Deadline", (DllCall("GetTickCount", "UInt") + 1500) & 0xFFFFFFFF)
            if !DllCall(this.startAddress, "Ptr", this.bridge.Hwnd, "CDecl Int")
                throw OSError()
            this.nativeStarted := true
            this.everStarted := true
            this.active := true
            this.action.Text := "停止验证"
            ModernRedraw(this.action)
            SetTimer(this.tickCallback, 250)
            this.Tick()
            this.input.Focus()
        } catch as err {
            this.Stop("无法开始验证：" err.Message)
        }
    }

    ReadVolume() {
        try return Round(SoundGetVolume(), 1)
        return "无法读取"
    }

    Tick(*) {
        if !this.active
            return
        try {
            remaining := Ceil((this.endsAt - A_TickCount) / 1000)
            if remaining <= 0 {
                this.Stop("验证已结束。音量按键恢复正常。")
                return
            }
            this.SetProperty("AirKey.VolumeGuard.Deadline", (DllCall("GetTickCount", "UInt") + 1500) & 0xFFFFFFFF)
            this.status.Text := "正在验证 · 剩余 " remaining " 秒 · 已拦截 " this.count " 次"
            this.volume.Text := "系统音量：开始 " this.initialVolume "%　现在 " this.ReadVolume() "%"
        } catch as err {
            this.Stop("验证已停止：" err.Message)
        }
    }

    Blocked(wParam, lParam, message, hwnd) {
        if this.active && hwnd = this.bridge.Hwnd && wParam = 10
            this.count += 1
        return 0
    }

    Stop(message := "") {
        this.active := false
        SetTimer(this.tickCallback, 0)
        ; Disarm before unhooking. A stalled/crashed host also expires in 1.5 s.
        if this.HasOwnProp("bridge")
            DllCall("User32\RemovePropW", "Ptr", this.bridge.Hwnd, "Str", "AirKey.VolumeGuard.Deadline", "Ptr")
        if this.nativeStarted {
            if DllCall(this.stopAddress, "CDecl Int")
                this.nativeStarted := false
            else
                message := "拦截已停用。请关闭此验证程序，完成清理。"
        }
        if this.HasOwnProp("status") {
            this.status.Text := message
            this.volume.Text := "已拦截 " this.count " 次。请确认豆包和音量的实际表现。"
            this.action.Text := "重新验证 · 60 秒"
            ModernRedraw(this.action)
        }
    }

    SelfTest() {
        if this.active || this.nativeStarted
            throw Error("Self-test must not activate a hook")
        if !DllCall(this.stopAddress, "CDecl Int") || !DllCall(this.stopAddress, "CDecl Int")
            throw Error("Idempotent stop failed")
        this.Stop()
        if DllCall("User32\GetPropW", "Ptr", this.bridge.Hwnd, "Str", "AirKey.VolumeGuard.Deadline", "Ptr")
            throw Error("Deadline was not cleared")
        FileAppend("PASS: DLL loaded, exports available, repeat Stop and deadline cleanup. No hook installed, keys sent or volume written.`n", "*", "UTF-8")
    }

    Cleanup() {
        if this.cleaned
            return
        this.cleaned := true
        try this.Stop()
        try OnMessage(0x8047, this.commandCallback, 0)
        if this.HasOwnProp("bridge") {
            DllCall("User32\RemovePropW", "Ptr", this.bridge.Hwnd, "Str", "AirKey.VolumeGuard.OwnerPID", "Ptr")
            try this.bridge.Destroy()
        }
        ; Unhook success does not mean every in-flight callback has returned.
        ; Once started, keep the module until Windows tears down this process.
        if this.module && !this.everStarted {
            DllCall("FreeLibrary", "Ptr", this.module)
            this.module := 0
        }
        if !this.module {
            try FileDelete(this.dllPath)
            try DirDelete(this.directory) ; Non-recursive: only the probe's own empty directory.
        }
        if this.mutex {
            DllCall("Kernel32\CloseHandle", "Ptr", this.mutex)
            this.mutex := 0
        }
    }
}
