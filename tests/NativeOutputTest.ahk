#Requires AutoHotkey v2.0 64-bit
#NoTrayIcon
#Include %A_ScriptDir%\..\NativeOutput.ahk

; Test selection with fake records only. Never construct NativeOutput, load its
; DLL, enumerate real devices, send input or install/uninstall a driver.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\native-output"
DirCreate(testDir)
report := "NativeOutput device-selection tests — fake records only; no DLL or driver calls.`r`n"
try {
    sample := [{id: 1, hid: "ACPI\TEST"}, {id: 2, hid: "USB\TEST"}]
    Check(FindDeviceSelection(sample, "USB\TEST") = 2, "Exact saved match")
    Check(FindDeviceSelection(sample, "missing") = 0, "Disconnected saved device is not replaced")
    sample.Push({id: 3, hid: "USB\TEST"})
    Check(FindDeviceSelection(sample, "USB\TEST") = 0, "Ambiguous saved match is rejected")
    report .= "PASS exact, disconnected and ambiguous saved-device selection.`r`n"

    automaticSample := [{id: 1, hid: "LdVKeyboard"}, {id: 4, hid: "HID\VID_1234&PID_5678"}]
    Check(FindDeviceSelection(automaticSample, "") = 2, "Automatic physical device selection")
    report .= "PASS automatic selection prefers the physical-device candidate.`r`n"
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
