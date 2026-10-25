; x64 WH_SHELL volume-command guard. Construction does not install a hook.
; Start/Stop/Close return true, or throw a localized error. A failed Stop keeps
; the native handle/bridge available for another Stop. Notifications only count.
; Modules are cached until process exit: Unhook can leave callbacks in flight.
#Include Localization.ahk

class NativeVolumeGuard {
    static Active := 0
    static Modules := Map()
    static Message := 0x8048
    static BridgeTitle := "AirKey.VolumeGuard.v1"
    static OwnerProperty := "AirKey.VolumeGuard.OwnerPID"
    static DeadlineProperty := "AirKey.VolumeGuard.Deadline"

    __New(dllPath) {
        this.closed := false
        this.running := false
        this.nativeStarted := false
        this.everStarted := false
        this.receivedCount := 0
        this.onFault := 0
        this.lastFault := ""
        this.bridge := 0
        this.monitored := false
        this.tickCallback := ObjBindMethod(this, "Tick")
        this.messageCallback := ObjBindMethod(this, "Blocked")
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if IsObject(NativeVolumeGuard.Active)
                throw LocalError("另一个音量保护仍在运行，请先停止它。", "Another volume guard is still open. Stop it first.")
            NativeVolumeGuard.Active := this
            this.module := this._AcquireModule(dllPath)
            this.bridge := this._CreateBridge()
            this._SetProperty(NativeVolumeGuard.OwnerProperty, this._ProcessId())
            this._Disarm()
            this._Monitor(true)
            this.monitored := true
        } catch {
            if IsObject(this.bridge) {
                try this._RemoveProperty(NativeVolumeGuard.DeadlineProperty)
                try this._RemoveProperty(NativeVolumeGuard.OwnerProperty)
                try this._Monitor(false)
                try this._DestroyBridge()
            }
            if NativeVolumeGuard.Active = this
                NativeVolumeGuard.Active := 0
            this.closed := true
            throw LocalError("无法准备音量保护，请关闭程序后重试。", "Could not prepare volume protection. Close AirKey and try again.")
        } finally Critical(previousCritical ? previousCritical : "Off")
    }

    Start(onFault := 0) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if this.closed || NativeVolumeGuard.Active != this
                throw LocalError("音量保护已关闭，请重新打开程序。", "Volume protection is closed. Reopen AirKey.")
            if onFault != 0 && !HasMethod(onFault, "Call")
                throw LocalError("音量保护回调无效。", "The volume protection callback is invalid.")
            if this.running {
                this.onFault := onFault
                return true
            }
            ; Never rearm a hook whose previous cleanup has not succeeded.
            if this.nativeStarted
                this.Stop()
            this.onFault := onFault
            this.lastFault := ""
            try {
                if !this._NativeStart()
                    throw Error("Guard start failed")
                this.nativeStarted := true
                this.everStarted := true
                this._RefreshDeadline()
                this.running := true
                this._Schedule(250)
            } catch {
                try this.Stop()
                throw LocalError("无法启用音量保护，语音按钮未启用。请退出程序后重试。",
                    "Could not enable volume protection. The voice button remains off. Exit AirKey and try again.")
            }
            return true
        } finally Critical(previousCritical ? previousCritical : "Off")
    }

    Stop() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if this.closed
                return true
            this.running := false
            this.onFault := 0
            failed := false
            try this._Schedule(0)
            catch
                failed := true
            try this._Disarm()
            catch
                failed := true
            ; Attempt every cleanup step even when an earlier one failed.
            if this.nativeStarted {
                try {
                    if !this._NativeStop()
                        throw Error("Guard stop failed")
                    this.nativeStarted := false
                } catch
                    failed := true
            }
            if failed
                throw LocalError("音量保护未完全停止，请退出程序后重试。", "Volume protection could not fully stop. Exit AirKey and try again.")
            return true
        } finally Critical(previousCritical ? previousCritical : "Off")
    }

    Close() {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if this.closed
                return true
            this.Stop() ; Keep the bridge and ownership if unhook needs a retry.
            try {
                this._RemoveProperty(NativeVolumeGuard.OwnerProperty)
                if this._GetProperty(NativeVolumeGuard.OwnerProperty)
                    throw Error("Owner property remains")
                if this.monitored {
                    this._Monitor(false)
                    this.monitored := false
                }
                this._DestroyBridge()
            } catch {
                throw LocalError("无法完成音量保护清理，请退出程序后重试。", "Could not finish volume protection cleanup. Exit AirKey and try again.")
            }
            this.bridge := 0
            this.closed := true
            if NativeVolumeGuard.Active = this
                NativeVolumeGuard.Active := 0
            return true
        } finally Critical(previousCritical ? previousCritical : "Off")
    }

    Tick(*) {
        previousCritical := A_IsCritical
        Critical("On")
        try {
            if this.closed || !this.running
                return
            try this._RefreshDeadline()
            catch {
                callback := this.onFault
                message := N("音量保护已停止，请重新启用语音按钮。", "Volume protection stopped. Enable the voice button again.")
                try this.Stop()
                catch
                    message := N("音量保护未完全停止，请退出程序后重试。", "Volume protection could not fully stop. Exit AirKey and try again.")
                this.lastFault := message
                ; Invoke once while serialized with Stop; the callback may stop
                ; or close this guard again. No keyboard event is generated here.
                if IsObject(callback)
                    try callback.Call(message)
            }
        } finally Critical(previousCritical ? previousCritical : "Off")
    }

    Blocked(wParam, lParam, message, hwnd) {
        if !this.closed && this.running && this.nativeStarted && IsObject(this.bridge)
            && hwnd = this.bridge.Hwnd && message = NativeVolumeGuard.Message && wParam = 10 && lParam = 0
            this.receivedCount += 1
        return 0
    }

    _RefreshDeadline() {
        deadline := (this._Now() + 1500) & 0xFFFFFFFF
        this._SetProperty(NativeVolumeGuard.DeadlineProperty, deadline ? deadline : 1)
    }

    _Disarm() {
        this._RemoveProperty(NativeVolumeGuard.DeadlineProperty)
        if this._GetProperty(NativeVolumeGuard.DeadlineProperty)
            throw Error("Deadline removal failed")
    }

    ; OS seams are replaced by the isolated test subclass.
    _Schedule(delay) => SetTimer(this.tickCallback, delay)
    _Now() => DllCall("Kernel32\GetTickCount", "UInt")
    _ProcessId() => DllCall("Kernel32\GetCurrentProcessId", "UInt")
    _CreateBridge() => Gui("+ToolWindow", NativeVolumeGuard.BridgeTitle)
    _DestroyBridge() => this.bridge.Destroy()
    _Monitor(enabled) => OnMessage(NativeVolumeGuard.Message, this.messageCallback, enabled ? 1 : 0)
    _NativeStart() => DllCall(this.module.start, "Ptr", this.bridge.Hwnd, "Int")
    _NativeStop() => DllCall(this.module.stop, "Int")
    _GetProperty(name) => DllCall("User32\GetPropW", "Ptr", this.bridge.Hwnd, "Str", name, "Ptr")
    _RemoveProperty(name) => DllCall("User32\RemovePropW", "Ptr", this.bridge.Hwnd, "Str", name, "Ptr")

    _SetProperty(name, value) {
        if !DllCall("User32\SetPropW", "Ptr", this.bridge.Hwnd, "Str", name, "Ptr", value, "Int")
            throw Error("Bridge property update failed")
    }

    _AcquireModule(dllPath) {
        if A_PtrSize != 8 || Type(dllPath) != "String" || dllPath = ""
            throw Error("Invalid volume guard component")
        length := DllCall("Kernel32\GetFullPathNameW", "Str", dllPath, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
        if !length || length > 32768
            throw Error("Invalid volume guard component")
        fullPath := Buffer(length * 2, 0)
        written := DllCall("Kernel32\GetFullPathNameW", "Str", dllPath, "UInt", length, "Ptr", fullPath, "Ptr", 0, "UInt")
        if !written || written >= length
            throw Error("Invalid volume guard component")
        canonical := StrGet(fullPath, "UTF-16")
        key := StrLower(canonical)
        if NativeVolumeGuard.Modules.Has(key)
            return NativeVolumeGuard.Modules[key]
        module := DllCall("Kernel32\LoadLibraryExW", "Str", canonical, "Ptr", 0, "UInt", 0x1100, "Ptr")
        if !module
            throw Error("Volume guard component unavailable")
        start := DllCall("Kernel32\GetProcAddress", "Ptr", module, "AStr", "AirKeyGuardStart", "Ptr")
        stop := DllCall("Kernel32\GetProcAddress", "Ptr", module, "AStr", "AirKeyGuardStop", "Ptr")
        if !start || !stop {
            ; No export has been called, so this invalid DLL cannot have a
            ; callback in flight. Successfully loaded modules remain cached.
            DllCall("Kernel32\FreeLibrary", "Ptr", module)
            throw Error("Volume guard component incomplete")
        }
        record := {handle: module, start: start, stop: stop}
        NativeVolumeGuard.Modules[key] := record
        return record
    }
}
