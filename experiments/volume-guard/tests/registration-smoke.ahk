#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
; Real registration check with NO deadline property: every command passes through.
; No key injection or audio writes. Never activate the guard in this check.
module := DllCall("LoadLibraryExW", "Str", A_ScriptDir "\..\native\volume-guard.dll", "Ptr", 0, "UInt", 0x1100, "Ptr")
if !module
    ExitApp(1)
bridge := Gui("+ToolWindow", "AirKey.VolumeGuard.Probe.v1")
DllCall("SetPropW", "Ptr", bridge.Hwnd, "Str", "AirKey.VolumeGuard.OwnerPID", "Ptr", DllCall("GetCurrentProcessId", "UInt"))
start := DllCall("GetProcAddress", "Ptr", module, "AStr", "AirKeyGuardStart", "Ptr")
stop := DllCall("GetProcAddress", "Ptr", module, "AStr", "AirKeyGuardStop", "Ptr")
ok := false
try {
    if DllCall("GetPropW", "Ptr", bridge.Hwnd, "Str", "AirKey.VolumeGuard.Deadline", "Ptr")
        throw Error("Guard must stay disarmed")
    if !DllCall(start, "Ptr", bridge.Hwnd, "CDecl Int")
        throw OSError()
    if !DllCall(stop, "CDecl Int") || !DllCall(stop, "CDecl Int")
        throw OSError()
    FileAppend("PASS: Native shell hook registered and removed while disarmed. No blocking, key sends or audio writes.`n", "*", "UTF-8")
    ok := true
} catch as err {
    FileAppend("FAIL: " err.Message "`n", "*", "UTF-8")
} finally {
    DllCall(stop, "CDecl Int")
    DllCall("RemovePropW", "Ptr", bridge.Hwnd, "Str", "AirKey.VolumeGuard.OwnerPID", "Ptr")
    bridge.Destroy()
    ; Keep module until process exit, even after Unhook succeeds.
}
ExitApp(ok ? 0 : 1)
