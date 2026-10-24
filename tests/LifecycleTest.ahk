#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
; Safe source-extraction test launcher. No Main startup or native driver code is loaded.
sourcePath := A_ScriptDir "\..\Main.ahk"
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\lifecycle"
DirCreate(testDir)
try {
    source := FileRead(sourcePath, "UTF-8")
    names := ["SendShortcut", "ReleaseHeldKeys", "StopMapping", "RearmVolume", "CloseNative",
        "UpdateUI", "RequestExit", "DriverReady", "Log", "SaveShortcut", "FinishShortcutEdit", "SwitchLanguage"]
    functions := ""
    for name in names {
        body := ExtractFunction(source, name)
        ; Count refresh requests while keeping the real early-return behavior.
        ; The harness never provides controls to the actual UI renderer.
        if name = "UpdateUI"
            body := RegExReplace(body, "^UpdateUI\(", "MainUpdateUI(")
        functions .= body "`r`n"
    }
    ; The worker contains only this fixed allowlist. The real EnableMapping, NativeOutput,
    ; DriverOperation, driver install helpers and Main's top-level code are absent.
    ; These modules contain only declarative definitions, with no startup code.
    localizationSourcePath := A_ScriptDir "\..\Localization.ahk"
    functions .= FileRead(localizationSourcePath, "UTF-8") "`r`n"
    shortcutSourcePath := A_ScriptDir "\..\ShortcutConfig.ahk"
    ; Localization is already embedded above. Do not resolve its relative include
    ; from the generated worker directory or create duplicate definitions.
    shortcutSource := FileRead(shortcutSourcePath, "UTF-8")
    functions .= RegExReplace(shortcutSource, "m)^#Include Localization\.ahk\r?$", "")
    profileSource := FileRead(A_ScriptDir "\..\MachineProfile.ahk", "UTF-8")
    functions .= "`r`n" RegExReplace(profileSource, "m)^#Include Localization\.ahk\r?$", "")
    ; Execute the real startup profile/shortcut consistency guard without any
    ; other startup statements, registry identity reads or native construction.
    if !RegExMatch(source, "m)^    S\.profile := LoadMicProfile\(ConfigPath, S\.machine\)\r?\n    if IsObject\(S\.profile\) && S\.profile\.shortcut != S\.binding\.canonical\r?\n        S\.profile := 0", &profileLoad)
        throw Error("Startup profile guard changed; review the safe extraction boundary")
    functions .= "`r`nLoadMainProfileForTest() {`r`n    global S, ConfigPath`r`n" profileLoad[0] "`r`n}`r`n"
    harness := FileRead(A_ScriptDir "\lifecycle-harness.ahk.txt", "UTF-8")
    workerPath := testDir "\worker.ahk"
    FileOpen(workerPath, "w", "UTF-8").Write(harness "`r`n" functions)
    FileOpen(testDir "\source-metadata.txt", "w", "UTF-8").Write(
        "Source: " sourcePath "`r`nModified: " FileGetTime(sourcePath, "M")
        "`r`nExtracted functions: " names.Length "`r`nShortcutConfig: " shortcutSourcePath
        "`r`nShortcutConfig modified: " FileGetTime(shortcutSourcePath, "M")
        "`r`nLocalization: " localizationSourcePath
        "`r`nLocalization modified: " FileGetTime(localizationSourcePath, "M") "`r`n")
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
    functionSource := SubStr(source, start.Pos, nextPos ? start.Len + nextPos - 1 : StrLen(source))
    if !RegExMatch(functionSource, "\}\s*$")
        throw Error("Unexpected extracted function boundary: " name)
    return functionSource
}
