#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include ..\DiagnosticInput.ahk

; MANUAL live API smoke: registers only baseline Raw Input for about 250 ms.
; Both message callbacks are no-ops: no input data, key state, device metadata,
; identifiers or text are read. No Hotkey/RegisterHotKey, native LL/shell hook,
; output component, audio write, driver operation or daily settings are used.
; Run deliberately; /Validate only checks syntax without starting registration.

resultDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\live-registration"
DirCreate(resultDir)
liveInput := RegistrationOnlyInput()
OnExit(LiveRegistrationCleanup)
registered := false
unregistered := false
isolated := false
passed := false
try {
    liveInput.Start("baseline")
    registered := liveInput.rawRegistered && liveInput.rawMonitored && liveInput.changeMonitored
    isolated := !liveInput.keyRegistered && !liveInput.wmMonitored && !liveInput.legacyHookInstalled
        && liveInput.hotkeyNames.Length = 0 && !liveInput.llHandle && !liveInput.llAddress && !liveInput.timerActive
    Sleep(250)
    liveInput.Stop()
    unregistered := !liveInput.rawRegistered && !liveInput.rawMonitored && !liveInput.changeMonitored
    liveInput.Close()
    passed := registered && unregistered && isolated
} catch {
    ; Fixed outcome only; never export exception text or local paths.
    try liveInput.Stop()
}
report := "Live baseline Raw Input registration smoke.`r`n"
    . "registered=" (registered ? 1 : 0) "`r`nunregistered=" (unregistered ? 1 : 0)
    . "`r`nno_other_input_hooks=" (isolated ? 1 : 0)
    . "`r`ninput_read=0`r`nkeys_sent=0`r`nvolume_writes=0`r`ndriver_changes=0`r`n"
    . (passed ? "PASS" : "FAIL") "`r`n"
FileOpen(resultDir "\report.txt", "w", "UTF-8").Write(report)
ExitApp(passed ? 0 : 1)

LiveRegistrationCleanup(*) {
    global liveInput
    try liveInput.Stop()
}

class RegistrationOnlyInput extends DiagnosticInput {
    _RawInput(*) {
        return ; Preserve normal message cleanup without reading any event.
    }
    _DeviceChange(*) {
        return ; Do not inspect device identities or arrivals/removals.
    }
}
