#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include %A_ScriptDir%\..\MachineProfile.ahk
; Synthetic identifiers only. GetMachineProfileKey is deliberately never called.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\machine-profile"
DirCreate(testDir)
path := testDir "\profile.ini"
report := "Machine profile tests — temporary files and synthetic identifiers only.`r`n"
lock := 0
try {
    machine := ProfileDigest("TEST_MACHINE_A")
    otherMachine := ProfileDigest("TEST_MACHINE_B")
    Check(machine != otherMachine && StrLen(machine) = 64, "Synthetic machine digests")
    Check(ProfileDigest("abc") = "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", "SHA256 implementation")
    devices := [{id: 2, hid: "ACPI\TEST_A"}, {id: 4, hid: "HID\VID_TEST"}]
    profile := {source: "key", device: "", usagePage: 12, usage: 1,
        outputHid: devices[1].hid, outputId: 2, topology: ProfileTopology(devices), shortcut: "RAlt+Space",
        volumeVerified: true}
    IniWrite("en", path, "UI", "Language")
    IniWrite("TEST_BOOT", path, "Driver", "BootId")
    before := FileRead(path)
    Check(!LoadMicProfile(path, machine) && FileRead(path) = before, "Unconfirmed setup is not accepted or written")
    SaveMicProfile(path, profile, machine)
    loaded := LoadMicProfile(path, machine)
    Check(IsObject(loaded) && loaded.source = "key" && loaded.outputId = 2
        && loaded.shortcut = "RAlt+Space" && loaded.volumeVerified, "Confirmed profile round trip")
    Check(IniRead(path, "Button", "Version") = "2"
        && IniRead(path, "Button", "VolumeVerified") = "1", "Current schema persists explicit volume confirmation")
    Check(IniRead(path, "UI", "Language") = "en" && IniRead(path, "Driver", "BootId") = "TEST_BOOT", "Unrelated settings preserved")
    Check(IniRead(path, "Mapping", "EnableOnLaunch") = "1"
        && IniRead(path, "Mapping", "HardwareId") = profile.outputHid, "Mapping updated in same saved profile")
    Check(!LoadMicProfile(path, otherMachine) && !LoadMicProfile(path, ""), "Copied settings rejected on another/unknown machine")
    report .= "PASS synthetic SHA256; confirmed profile round trip; copied-machine rejection; unrelated settings preserved.`r`n"

    ; The old voice-only confirmation must not silently become volume confirmation.
    IniWrite(1, path, "Button", "Version")
    IniWrite(1, path, "Button", "Verified")
    before := FileRead(path)
    Check(!LoadMicProfile(path, machine) && FileRead(path) = before,
        "Version 1 remains rejected even with both confirmation flags present")
    Check(IniRead(path, "Mapping", "Shortcut") = "RAlt+Space"
        && IniRead(path, "Mapping", "HardwareId") = profile.outputHid
        && IniRead(path, "UI", "Language") = "en", "Legacy rejection preserves migration inputs")
    IniWrite(2, path, "Button", "Version")
    for confirmation in ["0", ""] {
        if confirmation = ""
            IniDelete(path, "Button", "VolumeVerified")
        else
            IniWrite(confirmation, path, "Button", "VolumeVerified")
        before := FileRead(path)
        Check(!LoadMicProfile(path, machine) && FileRead(path) = before,
            "Missing/false volume confirmation cannot load or rewrite settings")
    }
    SaveMicProfile(path, profile, machine)
    before := FileRead(path)
    for missing in [false, true] {
        unconfirmed := profile.Clone()
        if missing
            unconfirmed.DeleteProp("volumeVerified")
        else
            unconfirmed.volumeVerified := false
        rejected := false
        try SaveMicProfile(path, unconfirmed, machine)
        catch
            rejected := true
        Check(rejected && FileRead(path) = before,
            "Unconfirmed volume cannot replace a verified profile")
    }
    registered := profile.Clone()
    registered.source := "registered"
    SaveMicProfile(path, registered, machine)
    loaded := LoadMicProfile(path, machine)
    Check(IsObject(loaded) && loaded.source = "registered" && loaded.volumeVerified,
        "Confirmed registered input source round trip")
    SaveMicProfile(path, profile, machine)
    report .= "PASS legacy voice-only profiles and absent/false volume confirmation rejected without data loss; confirmed registered source round trip.`r`n"

    before := FileRead(path)
    invalid := profile.Clone()
    invalid.outputId := 0
    rejected := false
    try SaveMicProfile(path, invalid, machine)
    catch
        rejected := true
    Check(rejected && FileRead(path) = before, "Invalid save preserves original file")
    lock := DllCall("Kernel32\CreateFileW", "Str", path, "UInt", 0x80000000,
        "UInt", 1, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
    Check(lock != -1, "Lock isolated destination against replacement")
    replacement := profile.Clone()
    replacement.shortcut := "LCtrl+LShift+Space"
    rejected := false
    try SaveMicProfile(path, replacement, machine)
    catch
        rejected := true
    finally {
        DllCall("Kernel32\CloseHandle", "Ptr", lock)
        lock := 0
    }
    Check(rejected && FileRead(path) = before, "Failed atomic replacement preserves original bytes")
    leftovers := 0
    loop files path ".setup-*.tmp"
        leftovers++
    Check(leftovers = 0, "Failed replacement removes temporary file")
    InvalidateMicProfile(path)
    Check(!LoadMicProfile(path, machine) && IniRead(path, "UI", "Language") = "en", "Invalidation preserves unrelated settings")
    report .= "PASS invalid/locked-destination saves preserve original bytes, clean temporary files, and invalidation rejects old setup.`r`n"

    duplicate := [{id: 2, hid: "HID\DUPLICATE"}, {id: 5, hid: "HID\DUPLICATE"}]
    selected := {outputHid: "HID\DUPLICATE", outputId: 5, topology: ProfileTopology(duplicate)}
    Check(FindProfileOutput(duplicate, selected) = 2, "Duplicate HID selected only with matching topology/id")
    changed := [{id: 2, hid: "HID\DUPLICATE"}, {id: 6, hid: "HID\DUPLICATE"}]
    Check(!FindProfileOutput(changed, selected), "Duplicate topology change rejected")
    selected.outputId := 9
    Check(!FindProfileOutput(duplicate, selected), "Unknown duplicate output ID rejected")
    Check(FindProfileOutput([{id: 7, hid: profile.outputHid}], profile) = 1, "Unique HID rematched despite changing numeric ID")
    Check(!FindProfileOutput([], profile) && !FindProfileOutput(devices, 0), "Missing profile/output rejected")
    report .= "PASS duplicate-HID topology checks, exact output ID and unique-HID rematching.`r`n"

    candidates := [{id: 9, hid: "OTHER"}, {id: 3, hid: "HID\VID_TEST"},
        {id: 2, hid: "ACPI\TEST"}, {id: 6, hid: "BTH\Dev_VID_TEST"},
        {id: 8, hid: "SAVED"}, {id: 3, hid: "DUPLICATE_ID"},
        {id: 0, hid: "INVALID"}, {id: 11, hid: "INVALID"}, {id: 7, hid: ""}]
    order := GetOutputCandidates(candidates, "SAVED")
    expected := [5, 3, 2, 4, 1]
    Check(order.Length = expected.Length, "All and only valid unique candidate IDs")
    for index, value in expected
        Check(order[index] = value, "Candidate priority and completeness")
    report .= "PASS all valid output candidates considered exactly once, with saved/ACPI/USB/Bluetooth priority.`r`n"
    ; Reports contain labels only, never identifiers, paths or saved contents.
    Check(!InStr(report, machine) && !InStr(report, profile.outputHid) && !InStr(report, testDir), "No identifying values in report")
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report)
    ExitApp(0)
} catch as err {
    if lock && lock != -1
        DllCall("Kernel32\CloseHandle", "Ptr", lock)
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report "FAIL: " err.Message)
    ExitApp(1)
}

Check(condition, message) {
    if !condition
        throw Error(message)
}
