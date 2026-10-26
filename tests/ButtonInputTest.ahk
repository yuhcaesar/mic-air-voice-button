#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include %A_ScriptDir%\..\ButtonInput.ahk

; All registration, hook and timer seams are replaced below. No real input is used.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\button-input"
DirCreate(testDir)
report := "ButtonInput synthetic tests - no hooks, device registration or drivers.`r`n"
try {
    for test in [
        ["Profile selection and validation", TestProfiles],
        ["Capability and usage buffers", TestBuffers],
        ["Raw registration structure and removal flags", TestRegistrationBuffers],
        ["Learning modes and keyboard-only rejection", TestLearning],
        ["Explicit mode isolation and cancellation", TestModeIsolation],
        ["Registered learning priority and observation window", TestRegisteredLearning],
        ["Registered runtime and retryable cleanup", TestRegisteredRuntime],
        ["Keyboard press edges and suppression", TestKeyboardRuntime],
        ["HID device filtering and report aggregation", TestHidRuntime],
        ["HID guard is required and stops before input", TestGuardLifecycle],
        ["HID preflight and removal before first report", TestHidPreflight],
        ["Stop cancels queued work", TestStop],
        ["Callback failure stops before fault notification", TestCallbackFailure]
    ] {
        test[2].Call()
        report .= "PASS " test[1] ".`r`n"
    }
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report)
    ExitApp(0)
} catch as err {
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report "FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
}

Check(condition, message) {
    if !condition
        throw Error(message)
}

KeyProfile(device := "") {
    return {source: "key", device: device, usagePage: 12, usage: 1}
}

RegisteredProfile(device := "") {
    return {source: "registered", device: device, usagePage: 12, usage: 1}
}

HidProfile(device := "test-hid-a") {
    return {source: "hid", device: device, usagePage: 12, usage: 1}
}

TestProfiles() {
    profile := MicButtonInput.ChooseLearnProfile(true, "test-hid-a", true)
    Check(profile.source = "registered" && profile.device = "", "Standard mode prioritizes registered input")
    profile := MicButtonInput.ChooseLearnProfile(true, "test-hid-a")
    Check(profile.source = "key" && profile.device = "", "Standard mode permits a proven hook")
    Check(profile.usagePage = 12 && profile.usage = 1, "Learned key profile uses expected usage")
    Check(!MicButtonInput.ChooseLearnProfile(false, "test-hid-a"), "Standard mode never falls back to HID")
    profile := MicButtonInput.ChooseLearnProfile(true, "test-hid-a", true, "compatibility")
    Check(profile.source = "hid" && profile.device = "test-hid-a", "Compatibility mode only accepts HID, even with keyboard evidence")
    Check(!MicButtonInput.ChooseLearnProfile(true, "", true, "compatibility"),
        "Compatibility mode cannot fall back to registered or hook input")
    Check(!MicButtonInput.ChooseLearnProfile(false, ""), "No observation is not a learned profile")
    profile := MicButtonInput.NormalizeProfile(KeyProfile("unused-device"))
    Check(profile.source = "key" && profile.device = "", "Normalize clears key device")
    profile := MicButtonInput.NormalizeProfile(RegisteredProfile("unused-device"))
    Check(profile.source = "registered" && profile.device = "", "Normalize clears registered device")
    profile := MicButtonInput.NormalizeProfile(HidProfile())
    Check(profile.source = "hid" && profile.device = "test-hid-a", "Normalize preserves valid HID device")
    for invalid in [
        {source: "mouse", device: "test", usagePage: 12, usage: 1},
        HidProfile(""), HidProfile("device`nother"), HidProfile("device`rother"),
        {source: "hid", device: "test", usagePage: 1, usage: 1},
        {source: "hid", device: "test", usagePage: 12, usage: 2},
        {source: "key", device: "", usagePage: 1, usage: 6}
    ] {
        rejected := false
        try rejected := !MicButtonInput.NormalizeProfile(invalid)
        catch
            rejected := true
        Check(rejected, "Invalid source, device or usage must be rejected")
    }
}

TestBuffers() {
    caps := Buffer(72 * 5, 0)
    SetCap(caps, 0, 12, 1, false, 0xE9)
    SetCap(caps, 1, 12, 4, true, 0xE8, 0xEA)
    SetCap(caps, 2, 1, 7, false, 0xE9)
    SetCap(caps, 3, 12, 9, true, 0xEA, 0xEF)
    SetCap(caps, 4, 12, 1, false, 0xE9)
    ids := MicButtonInput.ReportIds(caps, 5)
    Check(ids.Count = 2 && ids.Has(1) && ids.Has(4), "Select exact/ranged consumer E9 and deduplicate IDs")
    ids := MicButtonInput.ReportIds(caps, 1)
    Check(ids.Count = 1 && ids.Has(1), "Respect returned capability count")
    Check(MicButtonInput.ReportIds(caps, 0).Count = 0, "Zero capability count")
    usages := Buffer(6, 0)
    NumPut("UShort", 0xEA, usages, 0)
    NumPut("UShort", 0xE9, usages, 2)
    NumPut("UShort", 0xE2, usages, 4)
    Check(!MicButtonInput.HasVolumeUsage(usages, 0), "Zero returned usages")
    Check(!MicButtonInput.HasVolumeUsage(usages, 1), "Ignore E9 beyond returned usage count")
    Check(MicButtonInput.HasVolumeUsage(usages, 2), "Read E9 as a USHORT usage")
    absent := Buffer(2, 0)
    NumPut("UShort", 0xEA, absent)
    rejected := false
    try rejected := !MicButtonInput.HasVolumeUsage(absent, 2)
    catch
        rejected := true
    Check(rejected, "Oversized returned usage count cannot read a phantom E9")
}

SetCap(buffer, index, page, reportId, isRange, firstUsage, lastUsage := 0) {
    offset := index * 72
    NumPut("UShort", page, buffer, offset)
    NumPut("UChar", reportId, buffer, offset + 2)
    NumPut("UChar", isRange, buffer, offset + 12)
    NumPut("UShort", firstUsage, buffer, offset + 56)
    NumPut("UShort", lastUsage, buffer, offset + 58)
}

TestRegistrationBuffers() {
    input := FakeButtonInput()
    registration := input._RegistrationBuffer(0x2100, 123456, true)
    Check(registration.Size = 32 && NumGet(registration, 0, "UShort") = 12
        && NumGet(registration, 2, "UShort") = 1, "x64 consumer registration layout")
    Check(NumGet(registration, 16, "UShort") = 1 && NumGet(registration, 18, "UShort") = 6,
        "Learning keyboard top-level collection")
    Check(NumGet(registration, 4, "UInt") = 0x2100 && NumGet(registration, 8, "Ptr") = 123456
        && NumGet(registration, 24, "Ptr") = 123456, "INPUTSINK and DEVNOTIFY target the expected window")
    removal := input._RegistrationBuffer(1, 0, true)
    Check(NumGet(removal, 4, "UInt") = 1 && NumGet(removal, 20, "UInt") = 1
        && NumGet(removal, 8, "Ptr") = 0 && NumGet(removal, 24, "Ptr") = 0,
        "Unregister each collection with REMOVE and NULL target")
    input.Close()
}

TestLearning() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Learn(ObjBindMethod(sink, "Detected"))
    Check(input.testHooks && input.testPassThrough, "Learning hooks pass through Volume Up")
    Check(input.testRaw && input.testKeyboard, "Learning includes raw keyboard observation")
    Check(input.testRegistered && input.registeredMonitored, "Learning also registers the native hotkey")
    Check(!input.testGuard && !input.testGuardOwned, "Learning never enables the shell guard")
    input.FeedKeyboard(0xAE, true)
    Check(!input.learnPending && !input.rawKeyHeld, "Other raw keys do not alter learning state")
    input.FeedKeyboard(0xAF, true)
    input.FeedKeyboard(0xAF, false)
    input.FinishLearning()
    Check(sink.profiles.Length = 0, "Raw keyboard alone cannot report learning success")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Learn(ObjBindMethod(sink, "Detected"), "compatibility")
    input.FeedHid("test-hid-a", 1, true)
    input.FeedHid("test-hid-a", 1, false)
    input.FinishLearning()
    Check(sink.profiles.Length = 1 && sink.profiles[1].source = "hid"
        && sink.profiles[1].device = "test-hid-a", "Compatibility learns a HID-only Volume Up source")
    Check(sink.detectedStopped, "Stop registrations before reporting learned profile")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Learn(ObjBindMethod(sink, "Detected"))
    input.FeedHid("test-hid-a", 1, true)
    input.FeedHook(true)
    input.FeedHook(false)
    input.FinishLearning()
    Check(sink.profiles.Length = 1 && sink.profiles[1].source = "key", "Standard learns the hook and ignores HID")
    Check(sink.detectedStopped, "Hook learning stops before callback")
    input.Close()
}

TestModeIsolation() {
    global testDir
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Learn(ObjBindMethod(sink, "Detected"), "compatibility")
    Check(input.testRaw && !input.testKeyboard && !input.testHooks && !input.testRegistered
        && !input.registeredMonitored && !input.testGuard && !input.testGuardOwned,
        "Compatibility learning enables consumer Raw Input only, without keyboard interception or guard")
    Check(!InStr(input.OrderText(), "hook:on") && !InStr(input.OrderText(), "register:on"),
        "Compatibility never attempts keyboard hook or hotkey registration")
    input.FeedHook(true)
    input.FeedRegistered()
    input.FeedKeyboard(0xAF, true)
    Check(!input.sawHook && !input.sawRegistered && !input.hookHeld && !input.rawKeyHeld && !input.learnPending,
        "Stale keyboard callbacks cannot influence compatibility learning")
    input.FeedHid("test-hid-a", 1, true)
    input.FeedHid("test-hid-b", 1, true)
    input.FinishLearning()
    Check(sink.profiles.Length = 0, "Ambiguous compatibility devices are not silently selected")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Learn(ObjBindMethod(sink, "Detected"), "standard")
    input.FeedHid("test-hid-a", 1, true)
    input.FinishLearning()
    Check(!input.learnPending && input.learnDevices.Count = 0 && input.hidStates.Count = 0
        && sink.profiles.Length = 0, "Standard does not retain or learn HID input")
    input.Close()

    for invalid in ["", "automatic", "STANDARD", 0, {}] {
        input := FakeButtonInput()
        rejected := false
        try input.Learn((*) => 0, invalid)
        catch
            rejected := true
        Check(rejected && input.testOrder.Length = 0 && input.Stopped(),
            "Invalid mode is rejected before touching input resources")
        rejected := false
        try MicButtonInput.ChooseLearnProfile(true, "test-hid-a", true, invalid)
        catch
            rejected := true
        Check(rejected, "Invalid pure selection mode cannot choose a fallback")
        input.Close()
    }

    ; A save callback must not run after cancellation, even if its old timer fires.
    path := testDir "\cancel-mode.ini"
    IniWrite("original", path, "Button", "Source")
    before := FileRead(path)
    for preference in ["standard", "compatibility"] {
        input := FakeButtonInput()
        input.Learn((profile) => IniWrite(profile.source, path, "Button", "Source"), preference)
        if preference = "compatibility"
            input.FeedHid("test-hid-a", 1, true)
        else
            input.FeedHook(true)
        queued := input.PendingCallbacks()
        Check(queued.Length = 1, "Learning has a completion queued before cancellation")
        input.Stop()
        for callback in queued
            callback.Call()
        input.FinishLearning()
        Check(input.Stopped() && FileRead(path) = before, "Cancelling either mode preserves existing saved bytes")
        input.Close()
    }
}

TestRegisteredLearning() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Learn(ObjBindMethod(sink, "Detected"))
    Check(!input.learnPending && !input.sawRegistered, "Successful registration alone does not learn a key")
    input.FeedHook(true)
    input.testNow += 200
    input._FinishLearn()
    Check(sink.profiles.Length = 0 && input.mode = "learn", "Standard cannot finish at the former 200 ms deadline")
    Check(input.testTimers[input.learnTimer] = -800, "Early completion waits for the remaining observation interval")
    input.FeedHook(true)
    input._RegisteredInput(MicButtonInput.HotkeyId + 1, 0xAF << 16, 0x312, A_ScriptHwnd)
    input._RegisteredInput(MicButtonInput.HotkeyId, 0xAE << 16, 0x312, A_ScriptHwnd)
    input._RegisteredInput(MicButtonInput.HotkeyId, 0xAF << 16, 0x312, 0)
    Check(!input.sawRegistered, "Unrelated native messages do not count as registered evidence")
    input.testNow += 500
    input._RegisteredInput(MicButtonInput.HotkeyId, 0xAF << 16, 0x312, A_ScriptHwnd)
    Check(input.sawRegistered && sink.profiles.Length = 0, "Actual WM_HOTKEY is recorded without calling the client")
    input.testNow += 299
    input._FinishLearn()
    Check(sink.profiles.Length = 0, "Full 1000 ms must elapse from the first valid down")
    input.testNow++
    input._FinishLearn()
    Check(sink.profiles.Length = 1 && sink.profiles[1].source = "registered", "A later registered signal wins the same observation")
    Check(sink.detectedStopped, "Native hotkey is unregistered before delivering learned profile")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testRegisterAvailable := false
    input.Learn(ObjBindMethod(sink, "Detected"))
    Check(input.RegistrationError = 1409 && !input.hotkeyRegistered && !input.registeredMonitored,
        "Registration conflict is recorded without a leftover message monitor")
    input.FeedRegistered()
    Check(!input.sawRegistered && !input.learnPending, "A failed registration cannot fabricate a registered source")
    input.FeedHook(true)
    input.FinishLearning()
    Check(sink.profiles.Length = 1 && sink.profiles[1].source = "key", "A registration conflict still permits a proven hook")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testRegisterAvailable := false
    input.Learn(ObjBindMethod(sink, "Detected"))
    input.FeedHid("test-hid-a", 1, true)
    input.FinishLearning()
    Check(sink.profiles.Length = 0 && input.mode = "learn", "Registration failure cannot switch standard mode to HID")
    input.Close()
}

TestRegisteredRuntime() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(RegisteredProfile(), ObjBindMethod(sink, "Pressed"))
    Check(input.testRegistered && !input.testHooks && !input.testRaw && !input.testGuard,
        "Registered runtime uses native registration only, independent of sticky AHK hook flags")
    input._RegisteredInput(MicButtonInput.HotkeyId, 0xAF << 16, 0x312, A_ScriptHwnd)
    input._RegisteredInput(MicButtonInput.HotkeyId, 0xAF << 16, 0x312, A_ScriptHwnd)
    Check(sink.presses = 0 && input.pressPending, "Registered callbacks queue work rather than invoking client input")
    input._DeliverPress()
    Check(sink.presses = 1, "Queued notifications coalesce until delivery")
    input.FeedHook(true)
    input.FeedHid("test-hid-a", 1, true)
    input._DeliverPress()
    Check(sink.presses = 1, "Other routes cannot deliver registered runtime presses")
    input.FeedRegistered()
    queued := input.PendingCallbacks()
    input.testUnregisterFailure := true
    failed := false
    try input.Stop()
    catch
        failed := true
    Check(failed && input.hotkeyRegistered && input.registeredMonitored && MicButtonInput.Active = input,
        "Unregister failure preserves ownership and monitor for a cleanup retry")
    for callback in queued
        callback.Call()
    input._RegisteredInput(MicButtonInput.HotkeyId, 0xAF << 16, 0x312, A_ScriptHwnd)
    Check(sink.presses = 1 && !input.pressPending, "Stopped or stale WM_HOTKEY cannot send after failed cleanup")
    input.testUnregisterFailure := false
    input.Stop()
    Check(input.Stopped() && !IsObject(MicButtonInput.Active), "Retry releases native registration and ownership")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testRegisterAvailable := false
    failed := false
    try input.Start(RegisteredProfile(), ObjBindMethod(sink, "Pressed"))
    catch
        failed := true
    Check(failed && input.RegistrationError = 1409 && input.Stopped(), "Runtime registration failure throws and cleans up")
    input.Close()
}

TestKeyboardRuntime() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(KeyProfile(), ObjBindMethod(sink, "Pressed"))
    Check(input.testHooks && !input.testPassThrough, "Runtime key hook suppresses original Volume Up")
    input.FeedHook(true)
    input._DeliverPress()
    input.FeedHook(true)
    input._DeliverPress()
    Check(sink.presses = 1, "Held keyboard repeat produces one press")
    input.FeedHook(false)
    input.FeedHook(true)
    input._DeliverPress()
    Check(sink.presses = 2, "Keyboard release rearms the next press")
    input.FeedKeyboard(0xAF, true)
    input.FeedHid("test-hid-a", 1, true)
    input._DeliverPress()
    Check(sink.presses = 2, "Other input paths do not activate key runtime")
    input.Close()
}

TestHidRuntime() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    Check(input.testRaw && !input.testKeyboard, "HID runtime registers only consumer raw input")
    Check(input.testGuard && input.testGuardOwned, "HID runtime requires active volume protection")
    input.FeedHid("test-hid-b", 1, true)
    input._DeliverPress()
    Check(sink.presses = 0, "Unrelated HID device is ignored")
    input.FeedHid("test-hid-a", 1, true)
    input._DeliverPress()
    input.FeedHid("test-hid-a", 1, true)
    input._DeliverPress()
    Check(sink.presses = 1, "Duplicate HID down is ignored")
    input.FeedHid("test-hid-a", 2, true)
    input.FeedHid("test-hid-a", 1, false)
    input.FeedHid("test-hid-a", 1, true)
    input._DeliverPress()
    Check(sink.presses = 1, "Another report ID keeps the aggregate button held")
    input.FeedHid("test-hid-a", 1, false)
    input.FeedHid("test-hid-a", 2, false)
    input.FeedHid("test-hid-b", 1, false)
    input.FeedHid("test-hid-a", 2, true)
    input._DeliverPress()
    Check(sink.presses = 2, "All report IDs released before a new HID press")
    input.Close()
}

TestGuardLifecycle() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    Check(InStr(input.OrderText(), "preflight,guard:on,raw:on"), "HID preflight precedes guard start and Raw Input")
    input.testOrder := []
    input.Stop()
    Check(input.testOrder[1] = "guard:off" && input.Stopped(), "Guard disarms before any input cleanup")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testFailGuardStart := true
    failed := false
    try input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    catch
        failed := true
    Check(failed && !InStr(input.OrderText(), "raw:on") && input.Stopped(),
        "Guard startup failure prevents Raw Input and rolls back a partial guard")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testFailRawStart := true
    failed := false
    try input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    catch
        failed := true
    Check(failed && input.Stopped(), "Raw Input startup failure also rolls back the active guard")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    input.testFailGuardStop := true
    input.testOrder := []
    failed := false
    try input.Stop()
    catch
        failed := true
    Check(failed && !input.testGuard && input.testGuardOwned && !input.testRaw && !input.testHooks,
        "Guard cleanup failure is disarmed, retains retry ownership, and does not skip other cleanup")
    Check(MicButtonInput.Active = input, "Failed guard cleanup cannot be replaced by a second listener")
    input.testFailGuardStop := false
    input.Stop()
    Check(input.Stopped() && !IsObject(MicButtonInput.Active), "Guard cleanup can be retried")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"), ObjBindMethod(sink, "Faulted"))
    input.guardFault.Call(N("模拟心跳故障。", "Simulated heartbeat fault."))
    input.FeedHid("test-hid-a", 1, true)
    input._DeliverPress()
    input._DeliverFault()
    Check(sink.presses = 0 && sink.faults = 1 && sink.faultStopped,
        "Guard faults stop input before notifying the client")
    input.Close()
}

TestStop() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Learn(ObjBindMethod(sink, "Detected"))
    input.FeedHook(true)
    queued := input.PendingCallbacks()
    Check(queued.Length > 0, "Learning schedules completion")
    input.Stop()
    Check(input.Stopped() && input.testTimers.Count = 0, "Stop unregisters input and cancels learning timers")
    for callback in queued
        callback.Call()
    input._FinishLearn()
    Check(sink.detectedCalls = 0, "Stale learning completion cannot call the user")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(KeyProfile(), ObjBindMethod(sink, "Pressed"))
    input.FeedHook(true)
    queued := input.PendingCallbacks()
    Check(queued.Length > 0, "Press delivery is queued")
    input.Stop()
    Check(input.Stopped() && input.testTimers.Count = 0, "Stop cancels queued press delivery")
    for callback in queued
        callback.Call()
    input._DeliverPress()
    input.FeedHook(false)
    input.FeedHook(true)
    input._DeliverPress()
    Check(sink.presses = 0, "Stopped or stale input cannot deliver a press")
    input.Close()
    input.Close()
    Check(input.Stopped() && input.testTimers.Count = 0, "Close is safe to repeat")
}

TestHidPreflight() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testDevices.Clear()
    rejected := false
    try input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    catch
        rejected := true
    Check(rejected && input.Stopped(), "Disconnected saved HID cannot enable input")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testDevices[1].supportsVolume := false
    rejected := false
    try input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    catch
        rejected := true
    Check(rejected && input.Stopped(), "Saved HID without E9 capabilities cannot enable input")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.testDevices[2] := {name: "TEST-HID-A", supportsVolume: true}
    rejected := false
    try input.Start(HidProfile(), ObjBindMethod(sink, "Pressed"))
    catch
        rejected := true
    Check(rejected && input.Stopped(), "Ambiguous exact HID matches cannot enable input")
    input.Close()

    input := FakeButtonInput(), sink := InputRecorder(input)
    input.Start(HidProfile("TEST-HID-A"), ObjBindMethod(sink, "Pressed"), ObjBindMethod(sink, "Faulted"))
    Check(input.devices.Has(1), "Selected HID is cached before any report")
    input._DeviceChange(2, 1, 0xFE, A_ScriptHwnd)
    input._DeliverFault()
    Check(sink.presses = 0 && sink.faults = 1 && sink.faultStopped,
        "Removal before first report stops input and notifies once")
    input.Close()
}

TestCallbackFailure() {
    input := FakeButtonInput(), sink := InputRecorder(input)
    sink.failPress := true
    input.Start(KeyProfile(), ObjBindMethod(sink, "Pressed"), ObjBindMethod(sink, "Faulted"))
    input.FeedHook(true)
    input._DeliverPress()
    Check(sink.presses = 1 && sink.faults = 0, "Fault callback is deferred out of input delivery")
    input._DeliverFault()
    Check(sink.presses = 1 && sink.faults = 1, "Press exception produces one fault callback")
    Check(sink.faultStopped && input.testTimers.Count = 0, "Stop input and timers before fault callback")
    previousLanguage := AppLanguage.Current
    try {
        AppLanguage.Current := "zh"
        Check(Text(sink.lastFault) = "按钮响应失败，请重新启用。", "Stored fault renders in Chinese")
        AppLanguage.Current := "en"
        Check(Text(sink.lastFault) = "The button callback failed. Enable the button again.",
            "Stored fault renders in English after language switch")
        Check(Type(input.LastError) = "String", "Diagnostic LastError remains plain text")
    } finally {
        AppLanguage.Current := previousLanguage
    }
    input.FeedHook(false)
    input.FeedHook(true)
    input._DeliverPress()
    Check(sink.presses = 1 && sink.faults = 1, "Failed runtime remains stopped")
    input.Close()
}

class FakeButtonInput extends MicButtonInput {
    __New() {
        this.testHooks := false
        this.testPassThrough := false
        this.testRaw := false
        this.testKeyboard := false
        this.testTimers := Map()
        this.testDevices := Map(1, {name: "test-hid-a", supportsVolume: true})
        this.testNow := 1000
        this.testRegistered := false
        this.testRegisteredMonitor := false
        this.testRegisterAvailable := true
        this.testUnregisterFailure := false
        this.testGuard := false
        this.testGuardOwned := false
        this.testFailGuardStart := false
        this.testFailGuardStop := false
        this.testFailRawStart := false
        this.testOrder := []
        super.__New()
    }
    _SetHooks(enabled, passThrough := false) {
        this.testOrder.Push(enabled ? "hook:on" : "hook:off")
        this.testHooks := enabled
        this.testPassThrough := passThrough
    }
    _SetRaw(enabled, keyboard := false) {
        this.testOrder.Push(enabled ? "raw:on" : "raw:off")
        this.testRaw := enabled
        this.testKeyboard := enabled && keyboard
        if enabled && this.testFailRawStart
            throw Error("Synthetic Raw Input start failure")
    }
    _NativeRegistered(enabled) {
        this.testOrder.Push(enabled ? "register:on" : "register:off")
        if enabled && !this.testRegisterAvailable
            return {ok: false, code: 1409}
        if !enabled && this.testUnregisterFailure
            return {ok: false, code: 5}
        this.testRegistered := enabled
        return {ok: true, code: 0}
    }
    _MonitorRegistered(enabled) {
        this.testRegisteredMonitor := enabled
    }
    _SetGuard(enabled) {
        this.testOrder.Push(enabled ? "guard:on" : "guard:off")
        this.testGuard := enabled
        if enabled {
            this.testGuardOwned := true
            if this.testFailGuardStart
                throw Error("Synthetic guard start failure")
        } else {
            if this.testGuardOwned && this.testFailGuardStop
                throw Error("Synthetic guard stop failure")
            this.testGuardOwned := false
        }
    }
    _HidHandles() {
        this.testOrder.Push("preflight")
        handles := []
        for handle in this.testDevices
            handles.Push(handle)
        return handles
    }
    _DeviceName(handle) {
        name := this.testDevices[handle].name
        this.devices[handle] := {name: name, metadata: 0, checked: false}
        return name
    }
    _HidMetadata(handle, name) {
        return this.testDevices[handle].supportsVolume ? {reportLength: 2, maxUsages: 1} : 0
    }
    _Schedule(callback, delay) {
        if delay = 0 {
            if this.testTimers.Has(callback)
                this.testTimers.Delete(callback)
        } else
            this.testTimers[callback] := delay
    }
    _Now() => this.testNow
    FinishLearning() {
        this.testNow += MicButtonInput.LearnMilliseconds
        this._FinishLearn()
    }
    OrderText() {
        result := ""
        for item in this.testOrder
            result .= (result = "" ? "" : ",") item
        return result
    }
    PendingCallbacks() {
        callbacks := []
        for callback in this.testTimers
            callbacks.Push(callback)
        return callbacks
    }
    Stopped() {
        return !this.testHooks && !this.testRaw && !this.testRegistered && !this.testRegisteredMonitor
            && !this.testGuard && !this.testGuardOwned
    }
}

class InputRecorder {
    __New(input) {
        this.input := input
        this.profiles := []
        this.detectedCalls := 0
        this.detectedStopped := false
        this.presses := 0
        this.faults := 0
        this.faultStopped := false
        this.lastFault := 0
        this.failPress := false
    }
    Detected(profile := 0, *) {
        this.detectedCalls += 1
        this.detectedStopped := this.input.Stopped()
        if profile
            this.profiles.Push(profile)
    }
    Pressed(*) {
        this.presses += 1
        if this.failPress
            throw Error("Synthetic press callback failure")
    }
    Faulted(message, *) {
        this.faults += 1
        this.faultStopped := this.input.Stopped()
        this.lastFault := message
    }
}
