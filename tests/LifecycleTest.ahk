#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
; Safe source-extraction test launcher. No Main startup or native driver code is loaded.
sourcePath := A_ScriptDir "\..\Main.ahk"
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\lifecycle"
DirCreate(testDir)
try {
    source := FileRead(sourcePath, "UTF-8")
    names := ["SendShortcut", "ReleaseHeldKeys", "StopMapping", "RearmVolume",
        "UpdateUI", "RequestExit", "DriverReady", "Log", "SaveShortcut", "FinishShortcutEdit"]
    functions := ""
    for name in names
        functions .= ExtractFunction(source, name) "`r`n"
    ; The worker contains only this fixed allowlist. The real EnableMapping, NativeOutput,
    ; DriverOperation, driver install helpers and Main's top-level code are absent.
    ; ShortcutConfig contains only declarative parsing/sequencing function definitions.
    shortcutSourcePath := A_ScriptDir "\..\ShortcutConfig.ahk"
    functions .= FileRead(shortcutSourcePath, "UTF-8")
    harness := FileRead(A_ScriptDir "\lifecycle-harness.ahk.txt", "UTF-8")
    workerPath := testDir "\worker.ahk"
    FileOpen(workerPath, "w", "UTF-8").Write(harness "`r`n" functions)
    FileOpen(testDir "\source-metadata.txt", "w", "UTF-8").Write(
        "Source: " sourcePath "`r`nModified: " FileGetTime(sourcePath, "M")
        "`r`nExtracted functions: " names.Length "`r`nShortcutConfig: " shortcutSourcePath
        "`r`nShortcutConfig modified: " FileGetTime(shortcutSourcePath, "M") "`r`n")
    code := RunWait('"' A_AhkPath '" /ErrorStdOut=UTF-8 "' workerPath '"', testDir, "Hide")
    ExitApp(code)
} catch as err {
    FileOpen(testDir "\launcher-error.txt", "w", "UTF-8").Write(err.Message "`r`n" err.Stack)
    ExitApp(2)
}

ExtractFunction(source, name) {
    if !RegExMatch(source, "m)^" name "\([^\r\n]*\) \{\r?$", &start)
        throw Error("Function definition missing: " name)
    remaining := SubStr(source, start.Pos + start.Len)
    nextPos := RegExMatch(remaining, "m)^[A-Za-z_][A-Za-z_0-9]*\([^\r\n]*\) \{\r?$", &next)
    text := SubStr(source, start.Pos, nextPos ? start.Len + nextPos - 1 : StrLen(source))
    if !RegExMatch(text, "\}\s*$")
        throw Error("Unexpected extracted function boundary: " name)
    return text
}
