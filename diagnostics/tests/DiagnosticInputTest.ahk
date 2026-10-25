#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include ..\DiagnosticInput.ahk

; Every OS registration, hook, clock and key-state seam is mocked.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results"
DirCreate(testDir)
report := "DiagnosticInput mocks: no input registration, key sends, audio or driver changes.`r`n"
try {
    for test in [
        ["Construction and isolated mode resources", TestModes],
        ["Legacy WM_HOTKEY passes through and gate order", TestLegacy],
        ["Legacy 1500 ms rearm and held-key exclusion", TestRearm],
        ["Registered route and registration failure", TestRegistered],
        ["Hook-only low-level callback always forwards", TestHook],
        ["Raw edges, anonymous model bounds and snapshot copies", TestRaw],
        ["Retryable cleanup preserves resources and callback", TestCleanup],
        ["HID capability filtering and error projection", TestCaps]
    ] {
        test[2].Call()
        report .= "PASS " test[1] ".`r`n"
    }
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report)
    ExitApp(0)
} catch as err {
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report "FAIL " err.Message "`r`n" err.Stack)
    ExitApp(1)
}

Check(value, message) {
    if !value
        throw Error(message)
}

TestModes() {
    for mode in ["baseline", "legacy", "registered", "hook"] {
        input := FakeDiagnosticInput()
        Check(input.calls.Length = 0 && !input.Snapshot().started, "Constructor must not touch OS seams")
        input.Start(mode)
        Check(input.rawRegistered, "Each mode observes Raw Input")
        Check(input.legacyHookInstalled = (mode = "legacy"), "Only legacy explicitly installs AHK's tracking hook")
        Check(input.keyRegistered = (mode = "registered"), "Only registered calls explicit RegisterHotKey")
        Check(!!input.llHandle = (mode = "hook"), "Only hook adds an independent native LL observer")
        Check(input.hotkeyNames.Length = (mode = "legacy" ? 1 : mode = "hook" ? 2 : 0), "No competing hotkeys in baseline/registered")
        if mode = "legacy"
            Check(input.onNames[1] = "Volume_Up|On", "Legacy exactly matches old plain hotkey and options")
        if mode = "hook"
            Check(input.onNames[1] = "~*$Volume_Up|On B0 T1" && input.onNames[2] = "~*$Volume_Up Up|On B0 T1",
                "Hook stage passes both edges through and accepts modifiers")
        input.Stop()
        Check(input.Clean() && input.Snapshot().completed, "Stop clears all phase registrations")
        failed := false
        try input.Start(mode = "baseline" ? "registered" : "baseline")
        catch
            failed := true
        Check(failed, "A different mode requires a fresh worker process")
        input.Close()
    }
}

TestLegacy() {
    input := FakeDiagnosticInput()
    input.Start("legacy")
    reply := input._HotkeyMessage(3, 0xAF << 16, 0x312, A_ScriptHwnd)
    Check(reply = "", "Legacy observer must not consume WM_HOTKEY")
    Check(input.Snapshot().counts.wmHotkey = 1 && input.Snapshot().legacyRegisteredType = "reg-observed",
        "Actual native message proves the observed legacy registration path")
    input._LegacyPress()
    Check(input.counts.legacyHotkey = 1 && input.counts.sendAttempt = 1 && input.counts.eligible = 1,
        "Legacy callback reaches simulated send gates without sending")
    input._LegacyPress()
    Check(input.gates.unarmed = 1 && input.counts.sendAttempt = 1, "Unarmed repeat cannot reach send gates")
    input.SetGateState({armed: true, enabled: false})
    input._LegacyPress()
    Check(input.gates.disabled = 1 && input.gateState.armed, "Disabled gate leaves arming state unchanged")
    input.SetGateState({enabled: true, busy: true})
    input._LegacyPress()
    Check(input.gates.busy = 1 && input.gateState.armed, "Busy gate precedes disarming")
    input.SetGateState({busy: false, selected: 0})
    input._LegacyPress()
    Check(input.gates.noOutput = 1 && !input.gateState.armed, "SendShortcut no-output gate occurs after disarming")
    input.SetGateState({armed: true, selected: 1, maintenance: true})
    input._LegacyPress()
    input.SetGateState({armed: true, maintenance: false, editing: true})
    input._LegacyPress()
    Check(input.gates.maintenance = 1 && input.gates.editing = 1, "Other old SendShortcut gates are counted")
    input.SetGateState({armed: true, editing: false})
    input.keys["RAlt"] := true
    input._LegacyPress()
    Check(input.gates.heldShortcut = 1 && input.modifierMask = 2, "Only the event samples a modifier mask")
    input.keys.Clear()
    input.SetGateState({armed: true})
    input.keys["Space"] := true
    input._LegacyPress()
    Check(input.gates.heldShortcut = 2 && input.counts.eligible = 1, "Configured main key is a pre-send gate")
    input.Close()
}

TestRearm() {
    input := FakeDiagnosticInput()
    input.Start("legacy")
    input._LegacyPress()
    input.now += 1499
    input._Rearm()
    Check(!input.gateState.armed, "Rearm cannot occur before 1500 ms")
    input.now++
    input.keys["Volume_Up"] := true
    input._Rearm()
    Check(!input.gateState.armed, "Held Volume Up blocks rearm")
    input.keys.Clear()
    input._Rearm()
    Check(input.gateState.armed && input.counts.rearmed = 1, "Released key rearms at the old deadline")
    input.now += 1500
    input._LegacyPress()
    Check(input.counts.eligible = 2, "Two presses three seconds apart can pass the old gate")
    input.now += 1000
    input._LegacyPress()
    input.now += 600
    input._Rearm()
    Check(!input.gateState.armed, "Even a blocked repeat restarts the old 1500 ms wait")
    input.now += 900
    input._Rearm()
    Check(input.counts.rearmed = 2, "Rearm is measured from the most recent callback")
    input.Close()
}

TestRegistered() {
    input := FakeDiagnosticInput()
    input.Start("registered")
    input._HotkeyMessage(DiagnosticInput.HotkeyId + 1, 0xAF << 16, 0x312, A_ScriptHwnd)
    input._HotkeyMessage(DiagnosticInput.HotkeyId, 0xAE << 16, 0x312, A_ScriptHwnd)
    Check(!input.counts.registeredHotkey, "Wrong ID and ordinary keys are ignored")
    reply := input._HotkeyMessage(DiagnosticInput.HotkeyId, 0xAF << 16, 0x312, A_ScriptHwnd)
    Check(reply = 0 && input.counts.registeredHotkey = 1, "Only explicit registration is consumed by this stage")
    input.Stop()
    input._HotkeyMessage(DiagnosticInput.HotkeyId, 0xAF << 16, 0x312, A_ScriptHwnd)
    Check(input.counts.registeredHotkey = 1, "Stopped registration ignores queued input")
    input.Close()

    input := FakeDiagnosticInput()
    input.failRegister := true
    failed := false
    try input.Start("registered")
    catch
        failed := true
    snap := input.Snapshot()
    Check(failed && snap.registration.attempted && !snap.registration.ok && snap.registration.errorCode = 1409,
        "Registration conflict is visible without claiming input failure")
    Check(input.Clean() && !snap.started && !snap.completed, "Start failure cleans resources and is not a completed phase")
    input.Close()
}

TestHook() {
    input := FakeDiagnosticInput()
    input.Start("hook")
    packet := Buffer(24, 0)
    NumPut("UInt", 0x41, "UInt", 30, "UInt", 0x12, packet)
    Check(input._LowLevelInput(0, 0x100, packet.Ptr) = 77, "Unrelated key always passes to next hook")
    Check(!input.counts.llDown && input.events.Length = 0, "Ordinary input is neither counted nor retained")
    NumPut("UInt", 0xAF, packet)
    Check(input._LowLevelInput(0, 0x100, packet.Ptr) = 77, "Volume Up still passes to next hook")
    input._LowLevelInput(0, 0x101, packet.Ptr)
    input._LowLevelInput(-1, 0x100, 0)
    input._HookPress(true)
    input._HookPress(false)
    Check(input.counts.llDown = 1 && input.counts.llUp = 1 && input.forwarded = 4,
        "LL only records AF while always forwarding negative codes and other keys")
    Check(input.counts.hookDown = 1 && input.counts.hookUp = 1 && input.events[1].flags = 0x12,
        "Native LL flags and AHK callbacks are recorded separately")
    input.Close()
    Check(input.freed = 1 && input.llDepth = 0, "Native callback is released after unhook and successful Stop")
}

TestRaw() {
    input := FakeDiagnosticInput()
    input.Start("baseline")
    input.FeedKeyboard(0x41, true, 99)
    Check(input.keyStates.Count = 0 && input.events.Length = 0, "Ordinary raw keys have no retained state")
    input.FeedKeyboard(0xAF, true, 99)
    input.FeedKeyboard(0xAF, true, 99)
    input.FeedKeyboard(0xAF, false, 99)
    Check(input.counts.rawKeyboardDown = 1 && input.counts.rawKeyboardUp = 1, "Raw keyboard reports are edge deduplicated")
    input.FeedHid(12345, 1, true)
    input.FeedHid(12345, 2, true)
    input.FeedHid(12345, 1, false)
    input.FeedHid(12345, 2, false)
    Check(input.counts.hidDown = 1 && input.counts.hidUp = 1, "HID report IDs share one aggregate press state")
    snap := input.Snapshot()
    Check(snap.devices[1].id = "hid1" && snap.devices[1].vid = "1234" && snap.devices[1].pid = "ABCD",
        "HID output contains only a session alias and public model fields")
    for key, value in snap.devices[1].OwnProps()
        Check(key = "id" || key = "vid" || key = "pid" || key = "usagePage" || key = "usage" || key = "down" || key = "up",
            "No handle, path, serial or raw report can enter the device projection")
    snap.counts.hidDown := 999
    snap.devices[1].id := "changed"
    snap.events[1].source := "changed"
    Check(input.counts.hidDown = 1 && input.devices[1].id = "hid1" && input.events[1].source != "changed",
        "Snapshot is detached from live state")
    loop 12
        input.FeedHid(20000 + A_Index, 1, true)
    loop 70 {
        input.FeedKeyboard(0xAF, true, 99)
        input.FeedKeyboard(0xAF, false, 99)
    }
    Check(input.devices.Length = 8 && input.events.Length = 64 && input.eventDrops > 0,
        "Device/event projections are bounded without stopping counters")
    input.Close()
}

TestCleanup() {
    input := FakeDiagnosticInput()
    input.Start("registered")
    input.failUnregister := true
    failed := false
    try input.Stop()
    catch
        failed := true
    Check(failed && input.keyRegistered && input.wmMonitored && !input.rawRegistered && !input.active,
        "Unregister failure retains retry state while other input is stopped")
    input.failUnregister := false
    input.Close()
    Check(input.Clean(), "Native unregister can be retried")

    input := FakeDiagnosticInput()
    input.Start("hook")
    input.failUnhook := true
    failed := false
    try input.Close()
    catch
        failed := true
    Check(failed && input.llHandle && input.llAddress && !input.freed && !input.active,
        "Failed unhook must not free an active callback")
    Check(!input.hotkeyNames.Length && !input.rawRegistered, "LL failure does not skip AHK or raw cleanup")
    input.failUnhook := false
    input.Close()
    Check(input.Clean() && input.freed = 1, "Retry stops LL and frees its callback once")
}

TestCaps() {
    caps := Buffer(72 * 3, 0)
    NumPut("UShort", 12, caps, 0)
    NumPut("UChar", 7, caps, 2)
    NumPut("UShort", 0xE9, caps, 56)
    NumPut("UShort", 1, caps, 72)
    NumPut("UChar", 8, caps, 74)
    NumPut("UShort", 0xE9, caps, 128)
    NumPut("UShort", 12, caps, 144)
    NumPut("UChar", 9, caps, 146)
    NumPut("UChar", 1, caps, 156)
    NumPut("UShort", 0xE8, caps, 200)
    NumPut("UShort", 0xEA, caps, 202)
    ids := DiagnosticInput.ReportIds(caps, 3)
    Check(ids.Count = 2 && ids.Has(7) && ids.Has(9), "Only consumer E9 button capabilities are selected")
    input := FakeDiagnosticInput()
    input._AddError("raw", "HID_PARSE_FAILED")
    input._AddError("raw", "HID_PARSE_FAILED")
    Check(input.Snapshot().errors.Length = 1, "Repeated fixed-code errors are deduplicated")
    input.Close()
}

class FakeDiagnosticInput extends DiagnosticInput {
    __New() {
        this.now := 1000
        this.keys := Map()
        this.calls := [], this.onNames := []
        this.failRegister := false, this.failUnregister := false, this.failUnhook := false
        this.forwarded := 0, this.freed := 0
        super.__New()
    }
    _Now() => this.now
    _KeyDown(key) => this.keys.Has(key) && this.keys[key]
    _Monitor(message, callback, enabled) => this.calls.Push("monitor")
    _Timer(enabled) => this.calls.Push("timer")
    _InstallLegacyHook(enabled) => this.calls.Push("legacy-hook")
    _HotkeyOn(name, callback, options) {
        this.calls.Push("hotkey-on")
        this.onNames.Push(name "|" options)
    }
    _HotkeyOff(name) => this.calls.Push("hotkey-off")
    _CreateCallback() => 4321
    _FreeCallback(address) => this.freed++
    _InstallLowLevel(address) => 9876
    _UnhookLowLevel(handle) => !this.failUnhook
    _CallNext(code, wParam, lParam) {
        this.forwarded++
        return 77
    }
    _Registration(enabled) {
        this.calls.Push("registered")
        if enabled && this.failRegister
            return {ok: false, code: 1409}
        if !enabled && this.failUnregister
            return {ok: false, code: 5}
        return {ok: true, code: 0}
    }
    _RawRegistration(enabled) {
        this.calls.Push("raw")
        return {ok: true, code: 0}
    }
    _DeviceModel(handle) => {vid: "1234", pid: "ABCD", usagePage: 12, usage: 1}
    Clean() {
        return !this.rawRegistered && !this.rawMonitored && !this.changeMonitored && !this.wmMonitored
            && !this.keyRegistered && !this.legacyHookInstalled && !this.hotkeyNames.Length
            && !this.timerActive && !this.llHandle
    }
}
