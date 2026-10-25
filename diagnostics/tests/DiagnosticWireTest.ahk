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
    sample.events := [{source: "raw-hid", down: true, ms: 100, flags: 0},
        {source: "wm-hotkey", down: true, ms: 101, flags: 0}]
    sample.devices := [{id: "PRIVATE_SERIAL", path: "C:\Users\SECRET\hid", vid: "1234"}]
    sample.message := "PRIVATE_TEXT"
    path := directory "\snapshot.txt"
    DiagWriteSnapshot(path, sample, "confirmed", true)
    restored := DiagReadSnapshot(path, "legacy")
    Check(IsObject(restored) && restored.counts.legacyHotkey = 2 && restored.counts.rearmed = 1, "Counts roundtrip")
    Check(restored.events[1].source = "raw-hid" && restored.events[2].source = "wm-hotkey", "Event source survives")
    Check(restored.legacyRegisteredType = "reg-observed" && restored.eventDrops = 7, "Reg metadata survives")
    Check(!InStr(FileRead(path), "SECRET") && !InStr(FileRead(path), "PRIVATE"), "Identity and text discarded")
    Check(!DiagReadSnapshot(path, "hook"), "Wrong phase rejected")
    FileOpen(path, "w").Write("format=1`nphase=legacy`n")
    Check(!DiagReadSnapshot(path, "legacy"), "Partial snapshot rejected")
    report .= "PASS fixed IPC roundtrip, source names, identity stripping, wrong phase, truncation`r`n"
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
