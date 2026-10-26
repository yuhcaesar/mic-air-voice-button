; AHK v2 x64. No input registration, device enumeration or I/O on include/new.
; Learn(onDetected, preference:="standard"): observe a press for at least 1000 ms,
; then Stop before onDetected(profile). Standard learns registered hotkey > hook;
; compatibility learns consumer HID only. Neither mode falls back to the other.
; A raw keyboard event alone does not prove that the suppressing hook works.
; __New(guardPath:=""): no I/O; the HID guard is constructed lazily on Start.
; Start(profile,onPress,onFault:=0): registered uses Win32 RegisterHotKey,
; key uses *$Volume_Up, and hid requires NativeVolumeGuard before Raw Input.
; Stop()/Close(): disarm guard, cancel timers and remove all owned registrations.
; RegistrationError retains the last Win32 registration failure (0 on success).
; Profile: {source:"registered"|"key"|"hid",device:"",usagePage:12,usage:1}. HID device paths
; are local matching data: never log or include them in user-visible errors.
;
; Raw structures and HID parser contracts:
; https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-rawinput
; https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-rawhid
; https://learn.microsoft.com/windows-hardware/drivers/ddi/hidpi/nf-hidpi-hidp_getusages
; Blank WM_INPUT returns let AHK's default window procedure perform cleanup.
#Include Localization.ahk
#Include MachineProfile.ahk
#Include NativeVolumeGuard.ahk

class MicButtonInput {
    static Active := 0
    static HotkeyId := 0xA17E ; Outside AHK hotkey IDs; inside Win32's application range.
    static LearnMilliseconds := 1000

    __New(guardPath := "") {
        if A_PtrSize != 8
            throw LocalError("按钮监听需要 64 位程序。", "Button input requires the 64-bit app.")
        this.mode := ""
        this.preference := "standard"
        this.profile := 0
        this.onDetected := 0
        this.onPress := 0
        this.onFault := 0
        this.LastError := ""
        this.generation := 0
        this.hookHeld := false
        this.rawKeyHeld := false
        this.learnPending := false
        this.learnStarted := 0
        this.sawHook := false
        this.sawRegistered := false
        this.RegistrationError := 0
        this.hotkeyRegistered := false
        this.registeredMonitored := false
        this.guardPath := guardPath
        this.guard := 0
        this.learnDevices := Map()
        this.hidStates := Map()
        this.devices := Map()
        this.pressPending := false
        this.faultPending := false
        this.faultMessage := ""
        this.hookDownName := ""
        this.hookUpName := ""
        this.rawRegistered := false
        this.rawKeyboard := false
        this.inputMonitored := false
        this.deviceMonitored := false
        this.hookDown := ObjBindMethod(this, "_HookDown")
        this.hookUp := ObjBindMethod(this, "_HookUp")
        this.rawCallback := ObjBindMethod(this, "_RawInput")
        this.deviceCallback := ObjBindMethod(this, "_DeviceChange")
        this.registeredCallback := ObjBindMethod(this, "_RegisteredInput")
        this.guardFault := ObjBindMethod(this, "_QueueFault")
        this.learnTimer := ObjBindMethod(this, "_FinishLearn")
        this.pressTimer := ObjBindMethod(this, "_DeliverPress")
        this.faultTimer := ObjBindMethod(this, "_DeliverFault")
    }

    Learn(onDetected, preference := "standard") {
        if !ValidMicMode(preference)
            throw LocalError("按钮模式无效，请重新选择。", "Invalid button mode. Choose a mode again.")
        this.Stop()
        this._Claim()
        this.mode := "learn"
        this.preference := preference
        this.onDetected := onDetected
        this.LastError := ""
        this.RegistrationError := 0
        try {
            if preference = "compatibility"
                this._SetRaw(true, false)
            else {
                this._SetRegistered(true, false)
                this._SetRaw(true, true)
                this._SetHooks(true, true)
            }
        } catch as err {
            try this.Stop()
            throw err
        }
    }

    Start(profile, onPress, onFault := 0) {
        profile := MicButtonInput.NormalizeProfile(profile)
        this.Stop()
        this._Claim()
        this.mode := profile.source
        this.profile := profile
        this.onPress := onPress
        this.onFault := onFault
        this.LastError := ""
        try {
            if this.mode = "registered"
                this._SetRegistered(true, true)
            else if this.mode = "key"
                this._SetHooks(true, false)
            else {
                this._PrepareHidDevice(profile.device)
                this._SetGuard(true)
                this._SetRaw(true, false)
            }
        } catch as err {
            try this.Stop()
            throw err
        }
    }

    Stop() {
        this.mode := ""
        this.generation += 1
        this.learnPending := false
        this.pressPending := false
        this.faultPending := false
        for timer in [this.learnTimer, this.pressTimer, this.faultTimer]
            this._Schedule(timer, 0)
        failure := 0
        try this._SetGuard(false)
        catch as err
            failure := err
        try this._SetHooks(false)
        catch as err
            failure := err
        try this._SetRegistered(false)
        catch as err
            failure := err
        try this._SetRaw(false)
        catch as err
            failure := err
        this.onDetected := 0
        this.onPress := 0
        this.onFault := 0
        this.profile := 0
        this.hookHeld := false
        this.rawKeyHeld := false
        this.sawHook := false
        this.sawRegistered := false
        this.learnStarted := 0
        this.preference := "standard"
        this.learnDevices.Clear()
        this.hidStates.Clear()
        this.devices.Clear()
        if !IsObject(failure) && MicButtonInput.Active = this
            MicButtonInput.Active := 0
        if IsObject(failure)
            throw failure
        return true
    }

    Close() => this.Stop()

    _Claim() {
        if IsObject(MicButtonInput.Active) && MicButtonInput.Active != this
            throw LocalError("已有另一个按钮监听正在运行。", "Another button listener is already running.")
        MicButtonInput.Active := this
    }

    static NormalizeProfile(profile) {
        if !IsObject(profile) || !profile.HasOwnProp("source")
            || !(profile.source == "registered" || profile.source == "key" || profile.source == "hid")
            || !profile.HasOwnProp("usagePage") || profile.usagePage != 12
            || !profile.HasOwnProp("usage") || profile.usage != 1
            throw LocalError("按钮配置无效，请重新校准。", "Invalid button profile. Calibrate the button again.")
        device := profile.HasOwnProp("device") ? profile.device : ""
        if profile.source = "hid" && (Type(device) != "String" || device = ""
            || StrLen(device) > 32767 || RegExMatch(device, "[\x00\r\n]"))
            throw LocalError("按钮设备配置无效，请重新校准。", "Invalid button device profile. Calibrate the button again.")
        return {source: profile.source, device: profile.source = "hid" ? device : "", usagePage: 12, usage: 1}
    }

    static ChooseLearnProfile(sawHook, hidDevice, sawRegistered := false, preference := "standard") {
        if !ValidMicMode(preference)
            throw LocalError("按钮模式无效，请重新选择。", "Invalid button mode. Choose a mode again.")
        if preference = "compatibility"
            return hidDevice != "" ? {source: "hid", device: hidDevice, usagePage: 12, usage: 1} : 0
        if sawRegistered
            return {source: "registered", device: "", usagePage: 12, usage: 1}
        if sawHook
            return {source: "key", device: "", usagePage: 12, usage: 1}
        return 0
    }

    _HookDown(*) => this.FeedHook(true)
    _HookUp(*) => this.FeedHook(false)

    _RegisteredInput(wParam, lParam, message, hwnd) {
        if hwnd != A_ScriptHwnd || message != 0x312 || wParam != MicButtonInput.HotkeyId
            return
        if (lParam >> 16 & 0xFFFF) = 0xAF && !(lParam & 0xF)
            this.FeedRegistered()
        return 0 ; Only consume our own WM_HOTKEY, including stale queued messages.
    }

    FeedRegistered() {
        if !this.hotkeyRegistered || !(this.mode = "learn" || this.mode = "registered") || this.faultPending
            return
        if this.mode = "learn" && this.preference != "standard"
            return
        if this.mode = "learn" {
            this.sawRegistered := true
            this._BeginCorrelation()
        } else
            this._QueuePress() ; MOD_NOREPEAT provides native held-key deduplication.
    }

    FeedHook(isDown) {
        if !(this.mode = "learn" || this.mode = "key") || this.faultPending
            return
        if this.mode = "learn" && this.preference != "standard"
            return
        wasDown := this.hookHeld
        this.hookHeld := !!isDown
        if !isDown || wasDown
            return
        if this.mode = "learn" {
            this.sawHook := true
            this._BeginCorrelation()
        } else
            this._QueuePress()
    }

    FeedKeyboard(vkey, isDown) {
        ; Do not retain or act on any other keyboard key.
        if this.mode != "learn" || this.preference != "standard" || vkey != 0xAF
            return
        wasDown := this.rawKeyHeld
        this.rawKeyHeld := !!isDown
        if isDown && !wasDown
            this._BeginCorrelation()
    }

    FeedHid(device, reportId, isDown) {
        if !(this.mode = "learn" || this.mode = "hid") || this.faultPending || device = ""
            return
        if this.mode = "learn" && this.preference != "compatibility"
            return
        if this.mode = "hid" && StrLower(device) != StrLower(this.profile.device)
            return
        key := StrLower(device)
        if !this.hidStates.Has(key)
            this.hidStates[key] := Map()
        reports := this.hidStates[key]
        wasDown := false
        for id, down in reports
            wasDown := wasDown || down
        reports[reportId] := !!isDown
        nowDown := false
        for id, down in reports
            nowDown := nowDown || down
        if !nowDown || wasDown
            return
        if this.mode = "learn" {
            this.learnDevices[key] := device
            this._BeginCorrelation()
        } else
            this._QueuePress()
    }

    _BeginCorrelation() {
        if this.learnPending
            return
        this.learnPending := true
        this.learnStarted := this._Now()
        this._Schedule(this.learnTimer, -MicButtonInput.LearnMilliseconds)
    }

    _FinishLearn() {
        if this.mode != "learn" || !this.learnPending
            return
        remaining := MicButtonInput.LearnMilliseconds - (this._Now() - this.learnStarted)
        if remaining > 0 {
            this._Schedule(this.learnTimer, -remaining)
            return
        }
        this._Schedule(this.learnTimer, 0)
        this.learnPending := false
        device := ""
        if this.learnDevices.Count = 1
            for name, original in this.learnDevices
                device := original
        profile := MicButtonInput.ChooseLearnProfile(this.sawHook, device, this.sawRegistered, this.preference)
        this.sawHook := false
        this.sawRegistered := false
        this.learnDevices.Clear()
        if !IsObject(profile)
            return ; No proven source, or simultaneous ambiguous HID devices.
        callback := this.onDetected
        this.Stop()
        try callback.Call(profile)
        catch
            this.LastError := L("无法完成按钮校准，请重试。", "Could not finish button calibration. Please try again.")
    }

    _QueuePress() {
        if this.pressPending
            return
        this.pressPending := true
        this._Schedule(this.pressTimer, -1)
    }

    _DeliverPress() {
        if !this.pressPending || !(this.mode = "registered" || this.mode = "key" || this.mode = "hid") || this.faultPending
            return
        this.pressPending := false
        generation := this.generation
        try this.onPress.Call()
        catch {
            if this.generation = generation
                this._QueueFault(N("按钮响应失败，请重新启用。", "The button callback failed. Enable the button again."))
        }
    }

    _QueueFault(message) {
        if this.mode = "" || this.faultPending
            return
        this.faultPending := true
        this.faultMessage := message
        this._Schedule(this.faultTimer, -1)
    }

    _DeliverFault() {
        if !this.faultPending || this.mode = ""
            return
        callback := this.onFault
        message := this.faultMessage
        try this.Stop()
        catch
            message := N("无法完全停止按钮监听，请退出程序后重试。", "The button listener could not fully stop. Exit the app and try again.")
        this.LastError := Text(message)
        if IsObject(callback)
            try callback.Call(message)
    }

    ; OS/clock seams are overridden by the isolated test subclass.
    _Schedule(callback, delay) => SetTimer(callback, delay)
    _Now() => DllCall("Kernel32\GetTickCount64", "UInt64")

    _SetGuard(enabled) {
        if !enabled {
            if IsObject(this.guard) {
                if !this.guard.Stop() || !this.guard.Close()
                    throw LocalError("无法完全停止音量保护，请退出程序后重试。", "Volume protection could not fully stop. Exit the app and retry.")
                this.guard := 0
            }
            return
        }
        if !IsObject(this.guard) {
            if this.guardPath = ""
                throw LocalError("音量保护组件不可用，请重新打开程序。", "Volume protection is unavailable. Reopen the app.")
            this.guard := NativeVolumeGuard(this.guardPath)
        }
        if !this.guard.Start(this.guardFault)
            throw LocalError("无法启动音量保护，请重新启用。", "Could not start volume protection. Enable the button again.")
    }

    _SetRegistered(enabled, required := false) {
        if !enabled {
            if this.hotkeyRegistered {
                result := this._NativeRegistered(false)
                if !result.ok
                    throw LocalError("无法停止注册音量键（错误 {1}）。", "Could not unregister Volume Up (error {1}).", result.code)
                this.hotkeyRegistered := false
            }
            if this.registeredMonitored {
                this._MonitorRegistered(false)
                this.registeredMonitored := false
            }
            return true
        }
        if this.hotkeyRegistered
            return true
        this._MonitorRegistered(true)
        this.registeredMonitored := true
        result := this._NativeRegistered(true)
        this.RegistrationError := result.ok ? 0 : result.code
        if result.ok {
            this.hotkeyRegistered := true
            return true
        }
        this._MonitorRegistered(false)
        this.registeredMonitored := false
        if required
            throw LocalError("音量键暂时无法注册（错误 {1}），请关闭其他按键映射工具后重试。",
                "Volume Up could not be registered (error {1}). Close other key-mapping tools and retry.", result.code)
        return false ; Standard learning may still prove the hook source.
    }

    _NativeRegistered(enabled) {
        if enabled
            ok := DllCall("User32\RegisterHotKey", "Ptr", A_ScriptHwnd, "Int", MicButtonInput.HotkeyId,
                "UInt", 0x4000, "UInt", 0xAF, "Int") ; MOD_NOREPEAT
        else
            ok := DllCall("User32\UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", MicButtonInput.HotkeyId, "Int")
        code := A_LastError
        return {ok: !!ok, code: ok ? 0 : code}
    }

    _MonitorRegistered(enabled) => OnMessage(0x312, this.registeredCallback, enabled ? 1 : 0)

    _SetHooks(enabled, passThrough := false) {
        if !enabled {
            failed := false
            for property in ["hookDownName", "hookUpName"] {
                if this.%property% != "" {
                    try {
                        Hotkey(this.%property%, "Off")
                        this.%property% := ""
                    } catch
                        failed := true
                }
            }
            if failed
                throw LocalError("无法停止音量键监听。", "Could not stop the Volume Up hook.")
            return
        }
        prefix := passThrough ? "~*$" : "*$"
        Hotkey(prefix "Volume_Up", this.hookDown, "On B0 T1")
        this.hookDownName := prefix "Volume_Up"
        Hotkey(prefix "Volume_Up Up", this.hookUp, "On B0 T1")
        this.hookUpName := prefix "Volume_Up Up"
    }

    _SetRaw(enabled, keyboard := false) {
        if !enabled {
            failure := false
            if this.rawRegistered {
                devices := this._RegistrationBuffer(1, 0, this.rawKeyboard)
                if DllCall("User32\RegisterRawInputDevices", "Ptr", devices, "UInt", this.rawKeyboard ? 2 : 1, "UInt", 16, "Int")
                    this.rawRegistered := false
                else
                    failure := true
            }
            if this.inputMonitored {
                OnMessage(0xFF, this.rawCallback, 0)
                this.inputMonitored := false
            }
            if this.deviceMonitored {
                OnMessage(0xFE, this.deviceCallback, 0)
                this.deviceMonitored := false
            }
            if failure
                throw LocalError("无法注销按钮设备监听。", "Could not unregister button device input.")
            return
        }
        this.rawKeyboard := keyboard
        OnMessage(0xFF, this.rawCallback)
        this.inputMonitored := true
        OnMessage(0xFE, this.deviceCallback)
        this.deviceMonitored := true
        ; INPUTSINK | DEVNOTIFY only. Never NOLEGACY, capture or exclusion flags.
        devices := this._RegistrationBuffer(0x2100, A_ScriptHwnd, keyboard)
        if !DllCall("User32\RegisterRawInputDevices", "Ptr", devices, "UInt", keyboard ? 2 : 1, "UInt", 16, "Int")
            throw LocalError("无法开始按钮设备监听。", "Could not start button device input.")
        this.rawRegistered := true
    }

    _RegistrationBuffer(flags, hwnd, keyboard) {
        devices := Buffer(keyboard ? 32 : 16, 0)
        NumPut("UShort", 12, "UShort", 1, "UInt", flags, "Ptr", hwnd, devices, 0)
        if keyboard
            NumPut("UShort", 1, "UShort", 6, "UInt", flags, "Ptr", hwnd, devices, 16)
        return devices
    }

    _PrepareHidDevice(expectedName) {
        matched := 0
        for handle in this._HidHandles() {
            try name := this._DeviceName(handle)
            catch
                continue ; A device can disappear during enumeration.
            if StrLower(name) != StrLower(expectedName) {
                this.devices.Delete(handle)
                continue
            }
            if matched
                throw LocalError("按钮设备匹配不唯一，请重新校准。", "The button device match is ambiguous. Calibrate again.")
            try metadata := this._HidMetadata(handle, name)
            catch
                throw LocalError("无法读取已校准的按钮，请重新连接或重新校准。",
                    "Could not read the calibrated button. Reconnect it or calibrate again.")
            if !IsObject(metadata)
                throw LocalError("已校准的设备不再提供音量＋按钮，请重新校准。",
                    "The calibrated device no longer exposes a Volume Up button. Calibrate again.")
            matched := handle
        }
        if !matched
            throw LocalError("未找到已校准的按钮设备，请连接接收器或重新校准。",
                "The calibrated button device was not found. Connect the receiver or calibrate again.")
        ; The selected name/preparsed data are now cached, so removal is detected
        ; even if the device is unplugged before sending its first input report.
        return matched
    }

    _HidHandles() {
        ; Read-only enumeration. RAWINPUTDEVICELIST is 16 bytes on x64, with
        ; hDevice at 0 and dwType at 8. Retry a bounded number of hot-plug races.
        loop 3 {
            count := 0
            if DllCall("User32\GetRawInputDeviceList", "Ptr", 0, "UInt*", &count, "UInt", 16, "UInt") = 0xFFFFFFFF
                throw LocalError("无法检查按钮设备。", "Could not check connected button devices.")
            if count = 0
                return []
            if count > 16384
                throw LocalError("按钮设备列表无效。", "The button device list is invalid.")
            capacity := count
            devices := Buffer(capacity * 16, 0)
            copied := DllCall("User32\GetRawInputDeviceList", "Ptr", devices, "UInt*", &count, "UInt", 16, "UInt")
            if copied = 0xFFFFFFFF {
                if A_LastError = 122
                    continue ; ERROR_INSUFFICIENT_BUFFER after an arrival.
                throw LocalError("无法检查按钮设备。", "Could not check connected button devices.")
            }
            if copied > capacity
                throw LocalError("按钮设备列表无效。", "The button device list is invalid.")
            handles := []
            loop copied {
                offset := (A_Index - 1) * 16
                if NumGet(devices, offset + 8, "UInt") = 2
                    handles.Push(NumGet(devices, offset, "Ptr"))
            }
            return handles
        }
        throw LocalError("按钮设备正在变化，请稍后重试。", "Connected button devices changed. Please try again.")
    }

    _RawInput(wParam, lParam, message, hwnd) {
        if hwnd != A_ScriptHwnd || !(this.mode = "learn" || this.mode = "hid") || this.faultPending
            return
        selected := false
        try {
            size := 0
            if DllCall("User32\GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
                "Ptr", 0, "UInt*", &size, "UInt", 24, "UInt") = 0xFFFFFFFF || size < 24 || size > 1048576
                return
            raw := Buffer(size, 0)
            copied := DllCall("User32\GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
                "Ptr", raw, "UInt*", &size, "UInt", 24, "UInt")
            if copied = 0xFFFFFFFF || copied < 24 || copied > raw.Size || NumGet(raw, 4, "UInt") != copied
                return
            kind := NumGet(raw, 0, "UInt")
            if kind = 1 {
                if this.mode = "learn" && this.preference = "standard" && copied >= 40 {
                    vkey := NumGet(raw, 30, "UShort")
                    if vkey = 0xAF
                        this.FeedKeyboard(vkey, !(NumGet(raw, 26, "UShort") & 1))
                }
                return
            }
            if kind != 2 || copied < 33
                return
            if this.mode = "learn" && this.preference != "compatibility"
                return ; Standard learning does not retain HID identities or state.
            handle := NumGet(raw, 8, "Ptr")
            if !handle
                return
            name := this._DeviceName(handle)
            if this.mode = "hid" && StrLower(name) != StrLower(this.profile.device)
                return
            selected := this.mode = "hid"
            metadata := this._HidMetadata(handle, name)
            if !IsObject(metadata) {
                if selected
                    throw Error("Calibrated HID no longer exposes Volume Up")
                return
            }
            reportSize := NumGet(raw, 24, "UInt")
            count := NumGet(raw, 28, "UInt")
            if reportSize < 1 || count < 1 || count > Floor((copied - 32) / reportSize)
                throw Error("Invalid HID report bounds")
            if reportSize != metadata.reportLength
                throw Error("Invalid HID report length")
            loop count {
                pointer := raw.Ptr + 32 + (A_Index - 1) * reportSize
                reportId := NumGet(pointer, 0, "UChar")
                if !metadata.reportIds.Has(reportId)
                    continue ; Another report ID must not release Volume Up.
                usages := Buffer(metadata.maxUsages * 2, 0)
                usageCount := metadata.maxUsages
                status := DllCall(A_WinDir "\System32\hid.dll\HidP_GetUsages", "Int", 0, "UShort", 12,
                    "UShort", 0, "Ptr", usages, "UInt*", &usageCount, "Ptr", metadata.preparsed,
                    "Ptr", pointer, "UInt", reportSize, "UInt")
                if status != 0x110000
                    throw Error("HID usage parsing failed")
                this.FeedHid(name, reportId, MicButtonInput.HasVolumeUsage(usages, usageCount))
            }
        } catch {
            if selected
                this._QueueFault(N("无法读取已校准的按钮，请重新连接或重新校准。",
                    "Could not read the calibrated button. Reconnect it or calibrate again."))
        }
        ; Return no integer: preserve DefWindowProc cleanup for foreground WM_INPUT.
    }

    _DeviceName(handle) {
        if this.devices.Has(handle)
            return this.devices[handle].name
        chars := 0
        if DllCall("User32\GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", 0, "UInt*", &chars, "UInt") = 0xFFFFFFFF || chars < 1 || chars > 32767
            throw Error("Device name is unavailable")
        nameBuffer := Buffer((chars + 1) * 2, 0)
        capacity := chars + 1
        if DllCall("User32\GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000007,
            "Ptr", nameBuffer, "UInt*", &capacity, "UInt") = 0xFFFFFFFF || capacity > chars + 1
            throw Error("Device name is unavailable")
        name := StrGet(nameBuffer, "UTF-16")
        this.devices[handle] := {name: name, metadata: 0, checked: false}
        return name
    }

    _HidMetadata(handle, name) {
        device := this.devices[handle]
        if device.checked
            return device.metadata
        size := 0
        if DllCall("User32\GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000005,
            "Ptr", 0, "UInt*", &size, "UInt") = 0xFFFFFFFF || size < 1 || size > 1048576
            throw Error("HID descriptor is unavailable")
        preparsed := Buffer(size, 0)
        copied := DllCall("User32\GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000005,
            "Ptr", preparsed, "UInt*", &size, "UInt")
        if copied = 0xFFFFFFFF || copied < 1 || copied > preparsed.Size
            throw Error("HID descriptor is unavailable")
        caps := Buffer(64, 0)
        if DllCall(A_WinDir "\System32\hid.dll\HidP_GetCaps", "Ptr", preparsed, "Ptr", caps, "UInt") != 0x110000
            throw Error("HID capabilities are unavailable")
        buttonCount := NumGet(caps, 46, "UShort")
        reportLength := NumGet(caps, 4, "UShort")
        if !buttonCount || !reportLength {
            device.checked := true
            return 0
        }
        buttons := Buffer(buttonCount * 72, 0)
        if DllCall(A_WinDir "\System32\hid.dll\HidP_GetButtonCaps", "Int", 0, "Ptr", buttons,
            "UShort*", &buttonCount, "Ptr", preparsed, "UInt") != 0x110000
            throw Error("HID button capabilities are unavailable")
        reportIds := MicButtonInput.ReportIds(buttons, buttonCount)
        maxUsages := DllCall(A_WinDir "\System32\hid.dll\HidP_MaxUsageListLength", "Int", 0, "UShort", 12, "Ptr", preparsed, "UInt")
        if reportIds.Count && maxUsages > 0 && maxUsages <= 65535
            device.metadata := {preparsed: preparsed, reportIds: reportIds,
                reportLength: reportLength, maxUsages: maxUsages}
        device.checked := true
        return device.metadata
    }

    static ReportIds(buttons, count) {
        if count < 0 || count > Floor(buttons.Size / 72)
            throw Error("Invalid HID capability count")
        ids := Map()
        loop count {
            offset := (A_Index - 1) * 72
            if NumGet(buttons, offset, "UShort") != 12
                continue
            minimum := NumGet(buttons, offset + 56, "UShort")
            maximum := NumGet(buttons, offset + 12, "UChar") ? NumGet(buttons, offset + 58, "UShort") : minimum
            if minimum <= 0xE9 && maximum >= 0xE9
                ids[NumGet(buttons, offset + 2, "UChar")] := true
        }
        return ids
    }

    static HasVolumeUsage(usages, count) {
        if count < 0 || count > Floor(usages.Size / 2)
            throw Error("Invalid HID usage count")
        loop count
            if NumGet(usages, (A_Index - 1) * 2, "UShort") = 0xE9
                return true
        return false
    }

    _DeviceChange(wParam, lParam, message, hwnd) {
        if hwnd != A_ScriptHwnd || this.mode = "" || !this.devices.Has(lParam)
            return
        device := this.devices[lParam]
        this.devices.Delete(lParam)
        key := StrLower(device.name)
        if this.hidStates.Has(key)
            this.hidStates.Delete(key)
        if this.learnDevices.Has(key)
            this.learnDevices.Delete(key)
        if wParam = 2 && this.mode = "hid" && StrLower(this.profile.device) = key
            this._QueueFault(N("已校准的按钮设备已断开，请重新连接。", "The calibrated button was disconnected. Reconnect it."))
    }
}
