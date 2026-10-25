; Standalone AHK v2 x64 input-only diagnostic. Include/new perform no OS I/O.
; Start(mode): baseline | legacy | registered | hook. Use a fresh PROCESS for
; each different mode; this class rejects switching modes in the same instance.
; Snapshot(): detached counts/errors/events (max 64), anonymous HID models (max 8).
; Stop(): remove every owned registration, true or fixed-code Error; retryable.
; Dispose(): Stop, then release the native callback only when none is executing.
; SetGateState(object): optional legacy gate simulation; selected defaults to 1.
; "eligible" means the old pre-send gates passed. This module NEVER sends keys,
; writes volume, uses Interception, reads text, or queries/saves device paths.
; Raw HID parsing is adapted from the project's ButtonInput.ahk (MIT).

class DiagnosticInput {
    static Owner := 0
    static HotkeyId := 0xA17D
    static Modifiers := ["LAlt", "RAlt", "LCtrl", "RCtrl", "LShift", "RShift", "LWin", "RWin"]

    __New(mainKey := "Space") {
        if A_PtrSize != 8 || Type(mainKey) != "String" || mainKey = "" || StrLen(mainKey) > 32
            throw Error("INVALID_CONFIGURATION")
        this.mainKey := mainKey
        this.phaseId := ""
        this.active := false
        this.started := false
        this.completed := false
        this.disposed := false
        this.rawRegistered := false
        this.rawMonitored := false
        this.changeMonitored := false
        this.wmMonitored := false
        this.keyRegistered := false
        this.legacyHookInstalled := false
        this.hotkeyNames := []
        this.timerActive := false
        this.llHandle := 0
        this.llAddress := 0
        this.llDepth := 0
        this.rawCallback := ObjBindMethod(this, "_RawInput")
        this.changeCallback := ObjBindMethod(this, "_DeviceChange")
        this.wmCallback := ObjBindMethod(this, "_HotkeyMessage")
        this.legacyCallback := ObjBindMethod(this, "_LegacyPress")
        this.hookDownCallback := ObjBindMethod(this, "_HookPress", true)
        this.hookUpCallback := ObjBindMethod(this, "_HookPress", false)
        this.llCallback := ObjBindMethod(this, "_LowLevelInput")
        this.rearmCallback := ObjBindMethod(this, "_Rearm")
        this._Reset()
    }

    _Reset() {
        this.counts := {legacyHotkey: 0, wmHotkey: 0, registeredHotkey: 0, hookDown: 0, hookUp: 0,
            llDown: 0, llUp: 0, rawKeyboardDown: 0, rawKeyboardUp: 0, hidDown: 0, hidUp: 0,
            eligible: 0, sendAttempt: 0, rearmed: 0}
        this.gates := {disabled: 0, unarmed: 0, busy: 0, noOutput: 0, maintenance: 0, editing: 0, heldShortcut: 0}
        this.gateState := {enabled: true, armed: true, busy: false, selected: 1, maintenance: false, editing: false}
        this.registration := {attempted: false, ok: false, errorCode: 0}
        this.events := [], this.errors := [], this.devices := []
        this.eventDrops := 0
        this.modifierMask := 0
        this.legacyRegisteredType := "unknown"
        this.rawCache := Map(), this.hidStates := Map(), this.keyStates := Map(), this.aliases := Map()
        this.startTick := 0, this.endTick := 0, this.lastVolume := 0
    }

    Start(mode) {
        if !(mode == "baseline" || mode == "legacy" || mode == "registered" || mode == "hook")
            throw Error("INVALID_MODE")
        if this.disposed || this.active || (IsObject(DiagnosticInput.Owner) && DiagnosticInput.Owner != this)
            throw Error("INPUT_UNAVAILABLE")
        if this.phaseId != "" && this.phaseId != mode
            throw Error("FRESH_PROCESS_REQUIRED")
        this.Stop()
        this._Reset()
        this.phaseId := mode
        this.started := false, this.completed := false
        this.startTick := this._Now()
        DiagnosticInput.Owner := this
        this.active := true
        try {
            this._SetRaw(true)
            if mode == "legacy" || mode == "registered"
                this._SetHotkeyMonitor(true)
            if mode == "registered"
                this._SetRegistered(true)
            else if mode == "legacy" || mode == "hook"
                this._SetKeyboardHooks(true)
            if mode == "hook"
                this._SetLowLevel(true)
            if mode == "legacy" {
                this._Timer(true)
                this.timerActive := true
            }
            this.started := true
            return true
        } catch {
            this._AddError("start", "START_FAILED")
            try this.Stop()
            throw Error("INPUT_START_FAILED")
        }
    }

    SetGateState(state) {
        for name, value in state.OwnProps() {
            if !this.gateState.HasOwnProp(name) || !(Type(value) = "Integer")
                throw Error("INVALID_GATE_STATE")
            this.gateState.%name% := name = "selected" ? (value > 0 ? 1 : 0) : !!value
        }
    }

    Snapshot() {
        events := [], errors := [], devices := []
        for item in this.events
            events.Push(item.Clone())
        for item in this.errors
            errors.Push(item.Clone())
        for item in this.devices
            devices.Push(item.Clone())
        duration := this.startTick ? Max(0, (this.active ? this._Now() : this.endTick) - this.startTick) : 0
        return {phaseId: this.phaseId, started: this.started, active: this.active, completed: this.completed,
            durationMs: duration, registration: this.registration.Clone(), counts: this.counts.Clone(),
            gates: this.gates.Clone(), devices: devices, errors: errors, events: events,
            modifierMask: this.modifierMask, legacyRegisteredType: this.legacyRegisteredType, eventDrops: this.eventDrops}
    }

    Stop() {
        if this.active
            this.endTick := this._Now()
        this.active := false
        failed := false
        if this.timerActive {
            try {
                this._Timer(false)
                this.timerActive := false
            } catch
                failed := true
        }
        for method in ["_SetKeyboardHooks", "_SetRegistered", "_SetLowLevel", "_SetRaw", "_SetHotkeyMonitor"] {
            try this.%method%(false)
            catch
                failed := true
        }
        this.rawCache.Clear(), this.hidStates.Clear(), this.keyStates.Clear(), this.aliases.Clear()
        if failed {
            this._AddError("cleanup", "CLEANUP_FAILED")
            throw Error("INPUT_CLEANUP_FAILED")
        }
        this.completed := this.started
        if DiagnosticInput.Owner = this
            DiagnosticInput.Owner := 0
        return true
    }

    Dispose() {
        this.Stop()
        if this.llDepth
            throw Error("CALLBACK_STILL_RUNNING")
        if this.llAddress {
            this._FreeCallback(this.llAddress)
            this.llAddress := 0
        }
        this.disposed := true
        return true
    }

    Close() => this.Dispose()

    _AddError(stage, code, win32 := 0) {
        for errorRecord in this.errors
            if errorRecord.stage = stage && errorRecord.code = code && errorRecord.win32 = win32
                return
        if this.errors.Length < 16
            this.errors.Push({stage: stage, code: code, win32: win32})
    }

    _Record(source, down, device := "", flags := 0, sampleModifiers := true) {
        if !this.active
            return
        if sampleModifiers {
            mask := 0
            for index, key in DiagnosticInput.Modifiers
                if this._KeyDown(key)
                    mask |= 1 << (index - 1)
            this.modifierMask := mask
        }
        if this.events.Length < 64
            this.events.Push({source: source, down: !!down, ms: Max(0, this._Now() - this.startTick),
                device: device, flags: flags & 0xFF})
        else
            this.eventDrops++
    }

    _LegacyPress(*) {
        if !this.active || this.phaseId != "legacy"
            return
        this.counts.legacyHotkey++
        this.lastVolume := this._Now() ; Exact old behavior: even blocked repeats reset rearm time.
        this._Record("legacy", true)
        s := this.gateState
        if !s.enabled {
            this.gates.disabled++
            return
        }
        if !s.armed {
            this.gates.unarmed++
            return
        }
        if s.busy {
            this.gates.busy++
            return
        }
        s.armed := false
        this.counts.sendAttempt++
        if !s.selected {
            this.gates.noOutput++
            return
        }
        if s.maintenance {
            this.gates.maintenance++
            return
        }
        if s.editing {
            this.gates.editing++
            return
        }
        if this.modifierMask || this._KeyDown(this.mainKey) {
            this.gates.heldShortcut++
            return
        }
        this.counts.eligible++ ; Deliberately no SendConfiguredShortcut or output call.
        this._Record("eligible", true, "", 0, false)
    }

    _Rearm(*) {
        s := this.gateState
        if this.active && this.phaseId = "legacy" && s.enabled && !s.armed && !s.busy
            && this._Now() - this.lastVolume >= 1500 && !this._KeyDown("Volume_Up") {
            s.armed := true
            this.counts.rearmed++
            this._Record("rearm", true, "", 0, false)
        }
    }

    _HookPress(down, *) {
        if !this.active || this.phaseId != "hook"
            return
        if down
            this.counts.hookDown++
        else
            this.counts.hookUp++
        this._Record("hook", down)
    }

    _HotkeyMessage(wParam, lParam, message, hwnd) {
        if hwnd != A_ScriptHwnd || message != 0x312 || (lParam >> 16 & 0xFFFF) != 0xAF
            return
        if this.active && this.phaseId = "legacy" {
            this.counts.wmHotkey++
            this.legacyRegisteredType := "reg-observed"
            this._Record("wm-hotkey", true)
            return ; MUST pass through to AHK's own legacy hotkey dispatcher.
        }
        if this.phaseId = "registered" && wParam = DiagnosticInput.HotkeyId {
            if this.active && this.keyRegistered {
                this.counts.wmHotkey++
                this.counts.registeredHotkey++
                this._Record("registered", true)
            }
            return 0 ; Only consume the diagnostic's explicit Win32 registration.
        }
    }

    _LowLevelInput(code, wParam, lParam) {
        this.llDepth++
        try {
            try {
                code := code << 32 >> 32
                if code = 0 && this.active && this.phaseId = "hook" && NumGet(lParam, 0, "UInt") = 0xAF {
                    down := wParam = 0x100 || wParam = 0x104
                    if down || wParam = 0x101 || wParam = 0x105 {
                        if down
                            this.counts.llDown++
                        else
                            this.counts.llUp++
                        this._Record("ll", down, "", NumGet(lParam, 8, "UInt"))
                    }
                }
            } catch
                this._AddError("hook", "LL_CALLBACK_FAILED")
            try return this._CallNext(code, wParam, lParam)
            catch
                return 0 ; Fail open even if an unexpected DllCall error occurs.
        } finally this.llDepth--
    }

    FeedKeyboard(vkey, down, handle := 0) {
        if !this.active || vkey != 0xAF
            return
        previous := this.keyStates.Has(handle) ? this.keyStates[handle] : false
        this.keyStates[handle] := !!down
        if previous = !!down
            return
        if down
            this.counts.rawKeyboardDown++
        else
            this.counts.rawKeyboardUp++
        this._Record("raw-keyboard", down)
    }

    FeedHid(handle, reportId, down) {
        if !this.active
            return
        if !this.hidStates.Has(handle)
            this.hidStates[handle] := Map()
        reports := this.hidStates[handle]
        previous := false
        for id, held in reports
            previous := previous || held
        reports[reportId] := !!down
        current := false
        for id, held in reports
            current := current || held
        if current = previous
            return
        item := this._AnonymousDevice(handle)
        if current {
            this.counts.hidDown++
            if IsObject(item)
                item.down++
        } else {
            this.counts.hidUp++
            if IsObject(item)
                item.up++
        }
        this._Record("raw-hid", current, IsObject(item) ? item.id : "")
    }

    _AnonymousDevice(handle) {
        if this.aliases.Has(handle)
            return this.aliases[handle]
        if this.devices.Length >= 8
            return 0
        try model := this._DeviceModel(handle)
        catch {
            this._AddError("raw", "DEVICE_INFO_FAILED")
            model := {vid: "----", pid: "----", usagePage: 12, usage: 1}
        }
        item := {id: "hid" (this.devices.Length + 1), vid: model.vid, pid: model.pid,
            usagePage: model.usagePage, usage: model.usage, down: 0, up: 0}
        this.devices.Push(item)
        this.aliases[handle] := item
        return item
    }

    _SetHotkeyMonitor(enabled) {
        if enabled = this.wmMonitored
            return
        ; If native unregister failed, keep consuming our own stale ID until retry.
        if !enabled && this.keyRegistered
            return
        this._Monitor(0x312, this.wmCallback, enabled)
        this.wmMonitored := enabled
    }

    _SetRegistered(enabled) {
        if enabled = this.keyRegistered
            return
        result := this._Registration(enabled)
        if enabled
            this.registration := {attempted: true, ok: result.ok, errorCode: result.code}
        if !result.ok {
            this._AddError("register", enabled ? "REGISTER_FAILED" : "UNREGISTER_FAILED", result.code)
            throw Error("HOTKEY_REGISTRATION_FAILED")
        }
        this.keyRegistered := enabled
    }

    _SetKeyboardHooks(enabled) {
        if !enabled {
            failed := false
            index := this.hotkeyNames.Length
            while index >= 1 {
                try {
                    this._HotkeyOff(this.hotkeyNames[index])
                    this.hotkeyNames.RemoveAt(index)
                } catch
                    failed := true
                index--
            }
            if this.legacyHookInstalled {
                try {
                    this._InstallLegacyHook(false)
                    this.legacyHookInstalled := false
                } catch
                    failed := true
            }
            if failed {
                this._AddError("hook", "HOOK_STOP_FAILED")
                throw Error("HOOK_STOP_FAILED")
            }
            return
        }
        try {
            if this.phaseId = "legacy" {
                this._InstallLegacyHook(true)
                this.legacyHookInstalled := true
                this._HotkeyOn("Volume_Up", this.legacyCallback, "On")
                this.hotkeyNames.Push("Volume_Up")
            } else {
                this._HotkeyOn("~*$Volume_Up", this.hookDownCallback, "On B0 T1")
                this.hotkeyNames.Push("~*$Volume_Up")
                this._HotkeyOn("~*$Volume_Up Up", this.hookUpCallback, "On B0 T1")
                this.hotkeyNames.Push("~*$Volume_Up Up")
            }
        } catch {
            this._AddError("hook", "HOOK_SETUP_FAILED")
            throw Error("HOOK_SETUP_FAILED")
        }
    }

    _SetLowLevel(enabled) {
        if enabled {
            if !this.llAddress
                this.llAddress := this._CreateCallback()
            this.llHandle := this._InstallLowLevel(this.llAddress)
            if !this.llHandle {
                this._AddError("hook", "LL_INSTALL_FAILED", A_LastError)
                throw Error("LL_INSTALL_FAILED")
            }
        } else if this.llHandle {
            if !this._UnhookLowLevel(this.llHandle) {
                this._AddError("hook", "LL_UNHOOK_FAILED", A_LastError)
                throw Error("LL_UNHOOK_FAILED")
            }
            this.llHandle := 0
        }
    }

    _SetRaw(enabled) {
        if enabled {
            this._Monitor(0xFF, this.rawCallback, true)
            this.rawMonitored := true
            this._Monitor(0xFE, this.changeCallback, true)
            this.changeMonitored := true
            result := this._RawRegistration(true)
            if !result.ok {
                this._AddError("raw", "RAW_REGISTER_FAILED", result.code)
                throw Error("RAW_REGISTER_FAILED")
            }
            this.rawRegistered := true
            return
        }
        failed := false
        if this.rawRegistered {
            result := this._RawRegistration(false)
            if result.ok
                this.rawRegistered := false
            else {
                failed := true
                this._AddError("raw", "RAW_UNREGISTER_FAILED", result.code)
            }
        }
        for pair in [["rawMonitored", 0xFF, this.rawCallback], ["changeMonitored", 0xFE, this.changeCallback]] {
            if this.%pair[1]% {
                try {
                    this._Monitor(pair[2], pair[3], false)
                    this.%pair[1]% := false
                } catch
                    failed := true
            }
        }
        if failed
            throw Error("RAW_CLEANUP_FAILED")
    }

    _RawInput(wParam, lParam, message, hwnd) {
        if !this.active || hwnd != A_ScriptHwnd
            return
        try {
            size := 0
            if DllCall("User32\GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
                "Ptr", 0, "UInt*", &size, "UInt", 24, "UInt") = 0xFFFFFFFF || size < 24 || size > 1048576
                throw Error("RAW_READ_FAILED")
            raw := Buffer(size, 0)
            copied := DllCall("User32\GetRawInputData", "Ptr", lParam, "UInt", 0x10000003,
                "Ptr", raw, "UInt*", &size, "UInt", 24, "UInt")
            if copied = 0xFFFFFFFF || copied < 24 || copied > raw.Size || NumGet(raw, 4, "UInt") != copied
                throw Error("RAW_READ_FAILED")
            kind := NumGet(raw, 0, "UInt")
            handle := NumGet(raw, 8, "Ptr")
            if kind = 1 {
                if copied >= 40 && NumGet(raw, 30, "UShort") = 0xAF
                    this.FeedKeyboard(0xAF, !(NumGet(raw, 26, "UShort") & 1), handle)
                return
            }
            if kind != 2 || copied < 33 || !handle
                return
            metadata := this._HidMetadata(handle)
            if !IsObject(metadata)
                return
            reportSize := NumGet(raw, 24, "UInt"), count := NumGet(raw, 28, "UInt")
            if reportSize < 1 || count < 1 || count > Floor((copied - 32) / reportSize)
                || reportSize != metadata.reportLength
                throw Error("HID_PARSE_FAILED")
            loop count {
                pointer := raw.Ptr + 32 + (A_Index - 1) * reportSize
                reportId := NumGet(pointer, 0, "UChar")
                if !metadata.reportIds.Has(reportId)
                    continue
                usages := Buffer(metadata.maxUsages * 2, 0), usageCount := metadata.maxUsages
                status := DllCall(A_WinDir "\System32\hid.dll\HidP_GetUsages", "Int", 0, "UShort", 12,
                    "UShort", 0, "Ptr", usages, "UInt*", &usageCount, "Ptr", metadata.preparsed,
                    "Ptr", pointer, "UInt", reportSize, "UInt")
                if status != 0x110000 || usageCount > metadata.maxUsages
                    throw Error("HID_PARSE_FAILED")
                down := false
                loop usageCount
                    if NumGet(usages, (A_Index - 1) * 2, "UShort") = 0xE9
                        down := true
                this.FeedHid(handle, reportId, down)
            }
        } catch as err
            this._AddError("raw", err.Message = "RAW_READ_FAILED" ? "RAW_READ_FAILED" : "HID_PARSE_FAILED")
        ; Blank return preserves normal foreground WM_INPUT cleanup.
    }

    _HidMetadata(handle) {
        if this.rawCache.Has(handle)
            return this.rawCache[handle]
        size := 0
        if DllCall("User32\GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000005,
            "Ptr", 0, "UInt*", &size, "UInt") = 0xFFFFFFFF || size < 1 || size > 1048576
            throw Error("HID_PARSE_FAILED")
        preparsed := Buffer(size, 0)
        copied := DllCall("User32\GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000005,
            "Ptr", preparsed, "UInt*", &size, "UInt")
        if copied = 0xFFFFFFFF || copied < 1 || copied > preparsed.Size
            throw Error("HID_PARSE_FAILED")
        caps := Buffer(64, 0)
        if DllCall(A_WinDir "\System32\hid.dll\HidP_GetCaps", "Ptr", preparsed, "Ptr", caps, "UInt") != 0x110000
            throw Error("HID_PARSE_FAILED")
        buttonCount := NumGet(caps, 46, "UShort"), reportLength := NumGet(caps, 4, "UShort")
        metadata := 0
        if buttonCount && reportLength {
            buttons := Buffer(buttonCount * 72, 0)
            if DllCall(A_WinDir "\System32\hid.dll\HidP_GetButtonCaps", "Int", 0, "Ptr", buttons,
                "UShort*", &buttonCount, "Ptr", preparsed, "UInt") != 0x110000
                throw Error("HID_PARSE_FAILED")
            ids := DiagnosticInput.ReportIds(buttons, buttonCount)
            maxUsages := DllCall(A_WinDir "\System32\hid.dll\HidP_MaxUsageListLength", "Int", 0,
                "UShort", 12, "Ptr", preparsed, "UInt")
            if ids.Count && maxUsages > 0 && maxUsages <= 65535
                metadata := {preparsed: preparsed, reportIds: ids, reportLength: reportLength, maxUsages: maxUsages}
        }
        this.rawCache[handle] := metadata
        return metadata
    }

    static ReportIds(buttons, count) {
        if count < 0 || count > Floor(buttons.Size / 72)
            throw Error("HID_PARSE_FAILED")
        ids := Map()
        loop count {
            offset := (A_Index - 1) * 72
            if NumGet(buttons, offset, "UShort") != 12
                continue
            first := NumGet(buttons, offset + 56, "UShort")
            last := NumGet(buttons, offset + 12, "UChar") ? NumGet(buttons, offset + 58, "UShort") : first
            if first <= 0xE9 && last >= 0xE9
                ids[NumGet(buttons, offset + 2, "UChar")] := true
        }
        return ids
    }

    _DeviceChange(wParam, lParam, message, hwnd) {
        if hwnd != A_ScriptHwnd || wParam != 2
            return
        for items in [this.rawCache, this.hidStates, this.keyStates, this.aliases]
            if items.Has(lParam)
                items.Delete(lParam)
    }

    _DeviceModel(handle) {
        info := Buffer(32, 0), size := 32
        NumPut("UInt", 32, info)
        if DllCall("User32\GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x2000000B,
            "Ptr", info, "UInt*", &size, "UInt") = 0xFFFFFFFF || NumGet(info, 4, "UInt") != 2
            throw Error("DEVICE_INFO_FAILED")
        return {vid: Format("{:04X}", NumGet(info, 8, "UInt") & 0xFFFF),
            pid: Format("{:04X}", NumGet(info, 12, "UInt") & 0xFFFF),
            usagePage: NumGet(info, 20, "UShort"), usage: NumGet(info, 22, "UShort")}
    }

    ; OS seams below are replaced by mocks. No ordinary key values are retained.
    _Now() => DllCall("Kernel32\GetTickCount64", "UInt64")
    _KeyDown(key) => GetKeyState(key, "P")
    _Monitor(message, callback, enabled) => OnMessage(message, callback, enabled ? 1 : 0)
    _Timer(enabled) => SetTimer(this.rearmCallback, enabled ? 100 : 0)
    _HotkeyOn(name, callback, options) => Hotkey(name, callback, options)
    _HotkeyOff(name) => Hotkey(name, "Off")
    _InstallLegacyHook(enabled) => InstallKeybdHook(enabled)
    _CreateCallback() => CallbackCreate(this.llCallback, , 3)
    _FreeCallback(address) => CallbackFree(address)
    _InstallLowLevel(address) => DllCall("User32\SetWindowsHookExW", "Int", 13, "Ptr", address,
        "Ptr", DllCall("Kernel32\GetModuleHandleW", "Ptr", 0, "Ptr"), "UInt", 0, "Ptr")
    _UnhookLowLevel(handle) => DllCall("User32\UnhookWindowsHookEx", "Ptr", handle, "Int")
    _CallNext(code, wParam, lParam) => DllCall("User32\CallNextHookEx", "Ptr", 0,
        "Int", code, "UPtr", wParam, "Ptr", lParam, "Ptr")

    _Registration(enabled) {
        if enabled
            ok := DllCall("User32\RegisterHotKey", "Ptr", A_ScriptHwnd, "Int", DiagnosticInput.HotkeyId,
                "UInt", 0, "UInt", 0xAF, "Int") ; Match v1.1.0, including repeats.
        else
            ok := DllCall("User32\UnregisterHotKey", "Ptr", A_ScriptHwnd, "Int", DiagnosticInput.HotkeyId, "Int")
        code := A_LastError
        return {ok: !!ok, code: ok ? 0 : code}
    }

    _RawRegistration(enabled) {
        devices := Buffer(32, 0)
        flags := enabled ? 0x2100 : 1, target := enabled ? A_ScriptHwnd : 0
        NumPut("UShort", 12, "UShort", 1, "UInt", flags, "Ptr", target, devices, 0)
        NumPut("UShort", 1, "UShort", 6, "UInt", flags, "Ptr", target, devices, 16)
        ok := DllCall("User32\RegisterRawInputDevices", "Ptr", devices, "UInt", 2, "UInt", 16, "Int")
        code := A_LastError
        return {ok: !!ok, code: ok ? 0 : code}
    }
}
