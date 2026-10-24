#Requires AutoHotkey v2.0 64-bit
#NoTrayIcon
#Include %A_ScriptDir%\..\AppArtwork.ahk
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\artwork"
DirCreate(testDir)
g := 0
try {
    fallback := A_ScriptDir "\..\assets\voice-illustration.png"
    if !FileExist(fallback)
        throw Error("Original fallback image is missing")
    for invalidRoot in ["", "relative\path", "\\server\share", "https://example.invalid"]
        if FindDoubaoIconInFolder(invalidRoot) != ""
            throw Error("Non-local or invalid installation path was accepted")
    fixture := testDir "\fixture"
    DirCreate(fixture)
    if FindDoubaoIconInFolder(fixture) != ""
        throw Error("Missing icon was reported as available")
    FileOpen(fixture "\doubao_logo.ico", "w", "UTF-8").Write("invalid test icon")
    if FindDoubaoIconInFolder(fixture) != fixture "\doubao_logo.ico"
        throw Error("Existing local icon path was not found")

    ; Verify the same load/fallback path used by Main, with no visible window.
    g := Gui()
    usedFallback := false
    try g.AddPicture("w112 h112", fixture "\doubao_logo.ico")
    catch {
        g.AddPicture("w112 h112", fallback)
        usedFallback := true
    }
    if !usedFallback
        throw Error("Invalid local icon failed to use original fallback")
    localIcon := FindDoubaoIcon()
    if localIcon != "" && (!FileExist(localIcon) || !RegExMatch(localIcon, "i)^[a-z]:\\.*\\doubao_logo\.ico$"))
        throw Error("Discovery returned an invalid local icon path")
    g.AddPicture("w112 h112", localIcon != "" ? localIcon : fallback)
    g.Destroy()
    g := 0
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(
        "PASS local-only icon discovery and missing-icon fallback.`r`n"
        "PASS invalid local icon loads the bundled original fallback.`r`n"
        "PASS installed icon (if found) is loaded in place; no official icon is copied.`r`n"
        "No visible windows, keyboard hooks, key sends or driver operations.")
    ExitApp(0)
} catch as err {
    if IsObject(g)
        try g.Destroy()
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write("FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
}
