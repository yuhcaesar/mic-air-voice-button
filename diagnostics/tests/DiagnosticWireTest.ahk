#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include ..\DiagnosticWire.ahk
#Include ..\DiagnosticInput.ahk
directory := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\wire"
DirCreate(directory)
report := "Wire and lease checks (no input registration or key sends).`r`n"
try {
    input := DiagnosticInput()
    sample := input.Snapshot()
    sample.phaseId := "legacy", sample.started := true, sample.completed := true
    sample.legacyRegisteredType := "reg-observed", sample.eventDrops := 7
    sample.counts.legacyHotkey := 2, sample.counts.rearmed := 1
    ; Four records exceed the three inner numeric fields. Distinct timestamps,
    ; flags and alternating edges catch accidental reuse of the inner A_Index.
    sample.events := [{source: "raw-hid", down: true, ms: 100, flags: 0},
        {source: "wm-hotkey", down: false, ms: 231, flags: 16},
        {source: "hook", down: true, ms: 478, flags: 32},
        {source: "raw-keyboard", down: false, ms: 811, flags: 128}]
    for event in sample.events {
        event.device := "PRIVATE_DEVICE_PATH"
        event.text := "PRIVATE_EVENT_TEXT"
    }
    sample.errors := [{stage: "start", code: "REGISTER_FAILED", win32: 1409, message: "PRIVATE_ERROR_TEXT"},
        {stage: "cleanup", code: "UNREGISTER_FAILED", win32: 5, path: "C:\Users\SECRET\error"}]
    sample.devices := [{id: "PRIVATE_SERIAL", path: "C:\Users\SECRET\hid", vid: "1234"}]
    sample.message := "PRIVATE_TEXT"
    path := directory "\snapshot.txt"
    DiagWriteSnapshot(path, sample, "confirmed", true)
    restored := DiagReadSnapshot(path, "legacy")
    Check(IsObject(restored) && restored.counts.legacyHotkey = 2 && restored.counts.rearmed = 1, "Counts roundtrip")
    Check(restored.events.Length = sample.events.Length, "Event count survives")
    for index, expected in sample.events {
        for field in ["source", "down", "ms", "flags"]
            Check(restored.events[index].%field% = expected.%field%, "Event " index " field " field " roundtrip")
        Check(!restored.events[index].HasOwnProp("device") && !restored.events[index].HasOwnProp("text"),
            "Event private fields are not restored")
    }
    Check(restored.errors.Length = sample.errors.Length, "Error count survives")
    for index, expected in sample.errors {
        for field in ["stage", "code", "win32"]
            Check(restored.errors[index].%field% = expected.%field%, "Error " index " field " field " roundtrip")
        Check(!restored.errors[index].HasOwnProp("message") && !restored.errors[index].HasOwnProp("path"),
            "Error private fields are not restored")
    }
    Check(restored.legacyRegisteredType = "reg-observed" && restored.eventDrops = 7, "Reg metadata survives")
    Check(!InStr(FileRead(path), "SECRET") && !InStr(FileRead(path), "PRIVATE"), "Identity and text discarded")
    Check(!DiagReadSnapshot(path, "hook"), "Wrong phase rejected")
    FileOpen(path, "w").Write("format=1`nphase=legacy`n")
    Check(!DiagReadSnapshot(path, "legacy"), "Partial snapshot rejected")
    report .= "PASS complete four-event and error roundtrip, identity stripping, wrong phase, truncation`r`n"

    ; Exercise every retained index and the existing privacy/size boundary.
    sample.events := []
    loop 65
        sample.events.Push({source: Mod(A_Index, 2) ? "raw-hid" : "hook", down: Mod(A_Index, 2),
            ms: A_Index * 29, flags: Mod(A_Index * 3, 256), device: "PRIVATE_DEVICE_PATH"})
    DiagWriteSnapshot(path, sample)
    restored := DiagReadSnapshot(path, "legacy")
    Check(restored.events.Length = 64, "Event limit stays at 64")
    for index, event in restored.events {
        for field in ["source", "down", "ms", "flags"]
            Check(event.%field% = sample.events[index].%field%, "Bounded event " index " field " field " roundtrip")
    }
    encoded := FileRead(path)
    Check(!InStr(encoded, "event65_") && !InStr(encoded, "PRIVATE") && !InStr(encoded, "SECRET"),
        "Over-limit event and private fields excluded")
    report .= "PASS all 64 retained event indices and event limit preserve allowed fields only`r`n"
    Check(DiagDeadlineFresh(1100, 1000), "Live lease")
    Check(!DiagDeadlineFresh(0, 1000) && !DiagDeadlineFresh(1000, 1000) && !DiagDeadlineFresh(900, 1000), "Missing and expired lease")
    Check(DiagDeadlineFresh(500, 0xFFFFFF00) && !DiagDeadlineFresh(0xFFFFFF00, 500), "Wrap-safe lease")
    Check(!DiagDeadlineFresh(10000, 1000), "Implausible lease rejected")
    report .= "PASS heartbeat expiry, missing lease, DWORD wrap and future bound`r`n"
    mock := WireOutput()
    wrapper := DiagnosticGuardedOutput(mock, (*) => false)
    failed := false
    try wrapper.Send(1, 0x38, 2)
    catch
        failed := true
    wrapper.Send(1, 0x38, 3)
    Check(failed && mock.calls.Length = 1 && mock.calls[1] = 3, "Focus loss blocks down but permits release")
    report .= "PASS focus protection always allows key-up cleanup`r`n"
    FileOpen(directory "\report.txt", "w", "UTF-8").Write(report)
    ExitApp(0)
} catch as err {
    FileOpen(directory "\report.txt", "w", "UTF-8").Write(report "FAIL " err.Message "`r`n" err.Stack)
    ExitApp(1)
}
Check(condition, message) {
    if !condition
        throw Error(message)
}
class WireOutput {
    __New() => this.calls := []
    Send(device, code, state) => this.calls.Push(state)
}
