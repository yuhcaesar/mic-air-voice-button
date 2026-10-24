#Requires AutoHotkey v2.0 64-bit
#NoTrayIcon
#Include %A_ScriptDir%\..\ShortcutConfig.ahk
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\shortcut"
DirCreate(testDir)
report := "ShortcutConfig mock tests — no DLL, hooks, native sends or driver changes.`r`n"
try {
    rightAlt := ParseShortcut()
    Check(rightAlt.canonical = "RAlt+Space", "Default canonical")
    Check(rightAlt.label = "右 Alt＋空格", "Default label")
    mock := ShortcutMockOutput()
    held := {}
    SendConfiguredShortcut(mock, 2, rightAlt, held)
    Check(mock.Sequence() = "2:38:2,2:39:0,2:39:1,2:38:3", "Default exact proven stroke sequence")
    Check(held.keys.Length = 0 && !held.busy, "Default no held keys")
    report .= "PASS default exact RAlt E0 / Space sequence and release.`r`n"

    combo := ParseShortcut(" shift + CTRL + space ")
    Check(combo.canonical = "LCtrl+LShift+Space", "Modifier ordering and aliases")
    mock := ShortcutMockOutput()
    SendConfiguredShortcut(mock, 4, combo, {})
    Check(mock.Sequence() = "4:1D:0,4:2A:0,4:39:0,4:39:1,4:2A:1,4:1D:1", "Ctrl Shift exact sequence")
    mock := ShortcutMockOutput()
    SendConfiguredShortcut(mock, 1, ParseShortcut("F8"), {})
    Check(mock.Sequence() = "1:42:0,1:42:1", "Unmodified F8")
    arrow := ParseShortcut("RCtrl+Down")
    Check(arrow.keys[1].stateDown = 2 && arrow.keys[1].stateUp = 3
        && arrow.keys[2].stateDown = 2 && arrow.keys[2].stateUp = 3, "E0 key flags")
    rightShift := ParseShortcut("RShift+Space")
    Check(rightShift.keys[1].code = 0x36 && rightShift.keys[1].stateDown = 0
        && rightShift.keys[1].stateUp = 1, "AHK RShift pseudo-extended flag is not sent to driver")
    loop 24
        Check(ParseShortcut("F" A_Index).keys.Length = 1, "F1-F24 supported")
    for key in ["A", "9", "Enter", "Tab", "Home", "NumpadEnter", "Numpad7", "Minus", "Quote", "Backtick"]
        Check(ParseShortcut(key).keys[1].code > 0, "Common key " key)
    report .= "PASS Ctrl+Shift+Space, F8, E0 keys, F1-F24 and ordinary keys.`r`n"

    for invalidShortcut in ["", "RAlt", "Ctrl+LCtrl+Space", "LAlt+RAlt+Space", "Space+Ctrl", "Alt++Space",
        "{RAlt down}{Space}", "^!Space", "vkA5", "sc138", "Volume_Up", "F25", "Ctrl+Run('bad')", "A`nB"] {
        rejected := false
        try ParseShortcut(invalidShortcut)
        catch ValueError
            rejected := true
        Check(rejected, "Reject unsupported syntax " invalidShortcut)
    }
    report .= "PASS invalid, duplicate, media and executable/send syntax rejected.`r`n"

    mock := ShortcutMockOutput(2)
    held := {}
    failed := false
    try SendConfiguredShortcut(mock, 2, rightAlt, held)
    catch
        failed := true
    Check(failed, "Down failure propagated")
    Check(mock.Sequence() = "2:38:2,2:39:0,2:39:1,2:38:3", "Attempted down included in cleanup")
    Check(held.keys.Length = 0 && !held.busy, "Failure cleanup completed")

    mock := ShortcutMockOutput(1)
    held := {}
    try SendConfiguredShortcut(mock, 3, rightAlt, held)
    catch {
    }
    Check(mock.Sequence() = "3:38:2,3:38:3", "First modifier failure still releases attempted key")

    mock := ShortcutMockOutput(2, true)
    held := {}
    try SendConfiguredShortcut(mock, 7, rightAlt, held)
    catch {
    }
    Check(held.keys.Length = 2 && !held.busy && held.lastError != "", "Failed releases remain for retry")
    attempts := mock.events.Length
    rejected := false
    try SendConfiguredShortcut(mock, 7, rightAlt, held)
    catch
        rejected := true
    Check(rejected && attempts = mock.events.Length, "No new presses with unresolved held keys")
    mock.failReleases := false
    Check(ReleaseConfiguredKeys(mock, held) && held.keys.Length = 0, "Retry releases all keys")
    Check(mock.events[mock.events.Length - 1].device = 7 && mock.events[mock.events.Length].device = 7,
        "Recovery preserves original device")
    report .= "PASS failures before/during down, reverse cleanup, failed-release retention and retry.`r`n"

    rightAlt.keys[1].code := 0xFF
    mock := ShortcutMockOutput()
    SendConfiguredShortcut(mock, 2, rightAlt, {})
    Check(mock.Sequence() = "2:38:2,2:39:0,2:39:1,2:38:3", "Reparse canonical instead of mutated records")
    report .= "PASS sender reparses whitelisted canonical instead of trusting mutable stroke records.`r`n"
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

class ShortcutMockOutput {
    __New(failAt := 0, failReleases := false) {
        this.events := []
        this.failAt := failAt
        this.failReleases := failReleases
    }
    Send(device, code, state) {
        this.events.Push({device: device, code: code, state: state})
        if this.events.Length = this.failAt || (this.failReleases && (state & 1))
            throw Error("Mock send failure")
    }
    Sequence() {
        sequence := ""
        for stroke in this.events
            sequence .= (sequence = "" ? "" : ",") Format("{}:{:X}:{}", stroke.device, stroke.code, stroke.state)
        return sequence
    }
}
