#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include %A_ScriptDir%\..\NativeVolumeGuard.ahk

; All DLL, window, message, property and timer operations are mocked.
; This test never installs a hook or sends input or reads/writes audio levels.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\native-volume-guard"
DirCreate(testDir)
report := "NativeVolumeGuard lifecycle tests — mocked OS operations only.`r`n"
guard := 0
try {
    guard := MockVolumeGuard()
    Check(!guard.running && !guard.nativeStarted && guard.starts = 0 && guard.timer = 0, "Construction is unarmed")
    Check(guard._GetProperty(NativeVolumeGuard.OwnerProperty) = 123 && !guard.Deadline(), "Only owner identity is present")
    blockedSecond := false
    try second := MockVolumeGuard()
    catch
        blockedSecond := true
    Check(blockedSecond && NativeVolumeGuard.Active = guard, "A second bridge cannot replace the first")
    Check(guard.Start() && guard.running && guard.nativeStarted && guard.everStarted, "Start enables the native hook")
    Check(guard.starts = 1 && guard.timer = 250 && guard.Deadline() = 11500, "Initial deadline and heartbeat interval")
    Check(guard.Start() && guard.starts = 1, "Repeated start is idempotent")
    guard.now := 11000
    guard.Tick()
    Check(guard.Deadline() = 12500, "Tick renews the 1500 ms lease")
    guard.now := 0xFFFFFF00
    guard.Tick()
    Check(guard.Deadline() = 1244, "Heartbeat wraps as a DWORD")
    guard.now := 0x100000000 - 1500
    guard.Tick()
    Check(guard.Deadline() = 1, "Wrap does not create the disabled zero sentinel")
    guard.Blocked(10, 0, 0x8048, 100)
    guard.Blocked(10, 0, 0x8047, 100)
    guard.Blocked(10, 0, 0x8048, 101)
    guard.Blocked(9, 0, 0x8048, 100)
    guard.Blocked(10, 1, 0x8048, 100)
    Check(guard.receivedCount = 1 && guard.starts = 1, "Only the exact counter message is counted, without native actions")
    guard.events := []
    Check(guard.Stop(), "Stop succeeds")
    Check(EventText(guard.events) = "timer:0|remove:AirKey.VolumeGuard.Deadline|native-stop", "Stop disables timer and deadline before unhook")
    Check(!guard.running && !guard.nativeStarted && !guard.Deadline() && guard.onFault = 0, "Stop clears enabled state and callback")
    countAfterStop := guard.events.Length
    guard.Tick()
    guard.Blocked(10, 0, 0x8048, 100)
    Check(guard.events.Length = countAfterStop && guard.receivedCount = 1, "Late ticks and notices are harmless")
    Check(guard.Stop() && guard.Close() && guard.Close(), "Stop and Close are idempotent")
    Check(guard.destroyed = 1 && guard.closed && NativeVolumeGuard.Active = 0, "Close destroys one bridge and releases ownership")
    report .= "PASS unarmed construction, singleton bridge, heartbeat/tick wrap, fixed notifications and ordered/idempotent cleanup.`r`n"

    guard := MockVolumeGuard()
    guard.Start((*) => 0)
    guard.fail["unhook"] := true
    failed := false
    try guard.Stop()
    catch
        failed := true
    Check(failed && !guard.running && guard.nativeStarted && !guard.Deadline() && guard.timer = 0 && guard.onFault = 0,
        "Failed unhook retains its handle but remains disarmed")
    failedClose := false
    try guard.Close()
    catch
        failedClose := true
    Check(failedClose && !guard.closed && guard.destroyed = 0 && NativeVolumeGuard.Active = guard, "Failed Close keeps bridge and ownership for retry")
    startsBefore := guard.starts
    try guard.Start()
    catch {
    }
    Check(guard.starts = startsBefore && !guard.running && !guard.Deadline(), "Failed cleanup cannot be rearmed")
    guard.fail["unhook"] := false
    Check(guard.Stop() && guard.Close(), "Retained native handle can be stopped and closed later")
    report .= "PASS failed unhook/Close remain disarmed, retain ownership and support retry without rearming.`r`n"

    for failure in ["start", "arm", "timer-start"] {
        guard := MockVolumeGuard()
        guard.fail[failure] := true
        rejected := false
        try guard.Start((*) => 0)
        catch as err {
            rejected := true
            Check(err is Error && IsObject(ErrorText(err)), "Start failure is localized")
        }
        Check(rejected && !guard.running && !guard.nativeStarted && !guard.Deadline() && guard.timer = 0 && guard.onFault = 0,
            "Start failure rolls back: " failure)
        guard.fail[failure] := false
        Check(guard.Start() && guard.Close(), "Start can be retried after rollback: " failure)
    }
    report .= "PASS hook, deadline and timer-start failures roll back and permit a later retry.`r`n"

    guard := MockVolumeGuard()
    fault := {count: 0, message: "", critical: 0}
    guard.Start((message) => (fault.count++, fault.message := message, fault.critical := A_IsCritical))
    guard.fail["arm"] := true
    guard.Tick()
    Check(!guard.running && !guard.nativeStarted && !guard.Deadline() && guard.timer = 0, "Heartbeat failure stops before notification")
    Check(fault.count = 1 && fault.message is AppLocalizedMessage && fault.critical, "Fault callback gets a bilingual object while serialized")
    AppLanguage.Current := "zh"
    chinese := Text(fault.message)
    AppLanguage.Current := "en"
    Check(Text(fault.message) != chinese, "Fault notification remains dynamically translatable")
    guard.Tick()
    Check(fault.count = 1, "Heartbeat failure notifies only once")
    guard.Close()

    guard := MockVolumeGuard()
    guard.Start((message) => guard.Close())
    guard.fail["arm"] := true
    guard.Tick()
    Check(guard.closed && NativeVolumeGuard.Active = 0, "Fault callback may synchronously close the guard")
    report .= "PASS heartbeat failure stops before one localized callback, including reentrant Close.`r`n"

    guard := MockVolumeGuard()
    guard.Start()
    guard.fail["timer-stop"] := true
    failed := false
    try guard.Stop()
    catch
        failed := true
    Check(failed && !guard.running && !guard.Deadline() && !guard.nativeStarted && guard.stops = 1,
        "Timer failure still disarms and unhooks")
    guard.fail["timer-stop"] := false
    guard.fail["remove-owner"] := true
    failed := false
    try guard.Close()
    catch
        failed := true
    Check(failed && !guard.closed && guard.destroyed = 0 && NativeVolumeGuard.Active = guard, "Owner cleanup failure retains the bridge")
    guard.fail["remove-owner"] := false
    guard.Close()
    report .= "PASS cleanup continues after timer errors; failed bridge cleanup retains retryable state.`r`n"

    guard := MockVolumeGuard()
    Critical(23)
    try {
        guard.Start()
        Check(A_IsCritical = 23, "Start preserves caller critical setting")
        guard.Stop()
        Check(A_IsCritical = 23, "Stop preserves caller critical setting")
        guard.Close()
        Check(A_IsCritical = 23, "Close preserves caller critical setting")
    } finally Critical("Off")
    rejected := false
    try guard := MockVolumeGuard(Map("load", true))
    catch as err {
        rejected := true
        Check(IsObject(ErrorText(err)) && !InStr(err.Message, "PRIVATE_FIXTURE"), "Constructor errors contain no component path")
    }
    Check(rejected && NativeVolumeGuard.Active = 0, "Constructor failure releases its singleton claim")
    report .= "PASS caller critical state is preserved and constructor failures are localized without paths.`r`n"
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report)
    ExitApp(0)
} catch as err {
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report "FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
} finally {
    if IsObject(guard) {
        guard.fail.Clear()
        try guard.Close()
    }
}

Check(condition, message) {
    if !condition
        throw Error(message)
}

EventText(events) {
    result := ""
    for item in events
        result .= (result = "" ? "" : "|") item
    return result
}

class MockVolumeGuard extends NativeVolumeGuard {
    __New(failures := 0) {
        this.events := []
        this.properties := Map()
        this.fail := IsObject(failures) ? failures : Map()
        this.now := 10000
        this.timer := 0
        this.starts := 0
        this.stops := 0
        this.destroyed := 0
        super.__New("PRIVATE_FIXTURE")
    }
    Fails(name) => this.fail.Has(name) && this.fail[name]
    Deadline() => this._GetProperty(NativeVolumeGuard.DeadlineProperty)
    _AcquireModule(path) {
        if this.Fails("load")
            throw Error("PRIVATE_FIXTURE load failed")
        return {handle: 1, start: 2, stop: 3}
    }
    _CreateBridge() => {Hwnd: 100}
    _DestroyBridge() => this.destroyed++
    _Monitor(enabled) => this.events.Push("monitor:" enabled)
    _ProcessId() => 123
    _Now() => this.now
    _GetProperty(name) => this.properties.Has(name) ? this.properties[name] : 0
    _SetProperty(name, value) {
        if name = NativeVolumeGuard.DeadlineProperty && this.Fails("arm")
            throw Error("Mock property failure")
        this.events.Push("set:" name)
        this.properties[name] := value
    }
    _RemoveProperty(name) {
        this.events.Push("remove:" name)
        if name = NativeVolumeGuard.OwnerProperty && this.Fails("remove-owner")
            return
        if this.properties.Has(name)
            this.properties.Delete(name)
    }
    _Schedule(delay) {
        this.events.Push("timer:" delay)
        if this.Fails(delay ? "timer-start" : "timer-stop")
            throw Error("Mock timer failure")
        this.timer := delay
    }
    _NativeStart() {
        this.events.Push("native-start")
        this.starts++
        return !this.Fails("start")
    }
    _NativeStop() {
        this.events.Push("native-stop")
        this.stops++
        Check(!this.Deadline(), "Native unhook begins only after disarming")
        return !this.Fails("unhook")
    }
}
