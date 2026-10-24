#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include %A_ScriptDir%\..\TrayWindow.ahk

; The second process only talks to a unique test IPC identity. It cannot target
; the real app, send keys, open its settings, or call a driver.
if A_Args.Length && A_Args[1] = "--ipc-worker" {
    DetectHiddenWindows(false)
    SetTitleMatchMode(2)
    found := RequestExistingTrayWindow(1000, A_Args[2])
    restoredOptions := !A_DetectHiddenWindows && A_TitleMatchMode = 2
    FileOpen(A_Args[3], "w", "UTF-8").Write(found && restoredOptions ? "PASS" : "FAIL")
    ExitApp(found && restoredOptions ? 0 : 1)
}

testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\tray-window"
DirCreate(testDir)
reportPath := testDir "\report.txt"
identity := "MicAirDoubao.TrayWindow.Test." DllCall("GetCurrentProcessId", "UInt")
hiddenGui := Gui(, "Tray module hidden test")
hiddenGui.Show("Hide w160 h80")
state := {calls: 0, mappingEnabled: true, sends: 0}
callbackGui := FakeTrayGui()
restoreCallback := (*) => (state.calls += 1, RestoreTrayWindow(callbackGui))

try {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Test open", restoreCallback)
    A_TrayMenu.Add("Test retained", (*) => 0)
    A_TrayMenu.Default := "Test open"
    menuCount := DllCall("User32\GetMenuItemCount", "Ptr", A_TrayMenu.Handle, "Int")
    ConfigureTrayWindow(hiddenGui, restoreCallback, identity)
    Assert(A_TrayMenu.ClickCount = 1, "Single-click native tray setting")
    Assert(A_TrayMenu.Default = "Test open", "Existing default menu item retained")
    Assert(DllCall("User32\GetMenuItemCount", "Ptr", A_TrayMenu.Handle, "Int") = menuCount,
        "Configure must not rebuild the tray menu")

    fakeMain := FakeTrayGui()
    TrayWindowSize(fakeMain, 0, 160, 80)
    TrayWindowSize(fakeMain, 1, 160, 80)
    Assert(fakeMain.hidden = 0, "Ordinary resize/maximize must not hide")
    TrayWindowSize(fakeMain, -1, 160, 80)
    Assert(fakeMain.hidden = 1, "Minimize hides exactly once")
    Assert(state.mappingEnabled && state.sends = 0 && state.calls = 0,
        "Minimize must not stop mapping or send any keys")

    Assert(RestoreTrayWindow(fakeMain) = fakeMain, "Main restoration target")
    Assert(fakeMain.shows.Length = 1 && fakeMain.shows[1] = "", "Main activates through Gui.Show")
    fakeModal := FakeTrayGui()
    Assert(RestoreTrayWindow(fakeMain, () => fakeModal) = fakeModal, "Modal takes precedence")
    Assert(fakeMain.shows[2] = "NoActivate" && fakeModal.shows[1] = "",
        "Disabled owner must not receive activation")
    staleModal := FakeTrayGui(true)
    Assert(RestoreTrayWindow(fakeMain, () => staleModal) = fakeMain,
        "Destroyed modal falls back to the main Gui")

    ; Rejected messages never invoke the callback, including correct data sent
    ; to the user-facing Gui instead of the hidden script window.
    TrayWindowState.HandleMessage(0, 0, TrayWindowState.Message, A_ScriptHwnd)
    TrayWindowState.HandleMessage(TrayWindowState.Magic, 1, TrayWindowState.Message, A_ScriptHwnd)
    TrayWindowState.HandleMessage(TrayWindowState.Magic, 0, TrayWindowState.Message, hiddenGui.Hwnd)
    Assert(state.calls = 0, "Invalid IPC messages ignored")
    Assert(!RequestExistingTrayWindow(0, identity), "IPC excludes its own script window")
    Assert(!RequestExistingTrayWindow(0, identity "-different"), "IPC requires an exact identity")

    workerResult := testDir "\ipc-worker.txt"
    command := '"' A_AhkPath '" /ErrorStdOut=UTF-8 "' A_ScriptFullPath
        . '" --ipc-worker "' identity '" "' workerResult '"'
    exitCode := RunWait(command, A_ScriptDir, "Hide")
    Assert(exitCode = 0 && FileRead(workerResult, "UTF-8") = "PASS", "Cross-process IPC acknowledged")
    Assert(state.calls = 1, "IPC restores exactly once")
    Assert(callbackGui.shows.Length = 1, "IPC callback reaches the restore helper")
    Assert(!DllCall("User32\IsWindowVisible", "Ptr", hiddenGui.Hwnd, "Int"), "Test Gui remained hidden")
    Assert(state.mappingEnabled && state.sends = 0, "IPC only calls the supplied restore callback")

    ; AHK 2.0.30 hook.h defines AHK_NOTIFYICON as WM_USER + 4. Its
    ; script2.cpp handles the one-click default on WM_LBUTTONDOWN, not UP.
    ; Notify this test's own hidden script window; no real mouse input occurs.
    DllCall("User32\PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x404, "UPtr", 0, "Ptr", 0x201)
    deadline := A_TickCount + 500
    while state.calls < 2 && A_TickCount < deadline
        Sleep(10)
    DllCall("User32\PostMessageW", "Ptr", A_ScriptHwnd, "UInt", 0x404, "UPtr", 0, "Ptr", 0x202)
    Sleep(30)
    Assert(state.calls = 2 && callbackGui.shows.Length = 2,
        "Native single-click default invokes restore once for the down/up pair")
    FileOpen(reportPath, "w", "UTF-8").Write(
        "PASS: native one-click notification invokes default/restore once; existing menu retained.`r`n"
        "PASS: minimize-only Hide; mapping and key sends untouched.`r`n"
        "PASS: normal restore, modal priority and stale-modal fallback (mock Guis).`r`n"
        "PASS: invalid/self/mismatched IPC ignored; hidden exact-identity cross-process restore ACK.`r`n"
        "No visible windows, native key sends, driver operations or production settings changes.")
} catch as err {
    FileOpen(reportPath, "w", "UTF-8").Write("FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
} finally {
    hiddenGui.Destroy()
}
ExitApp(0)

Assert(condition, message) {
    if !condition
        throw Error(message)
}

class FakeTrayGui {
    __New(failShow := false) {
        this.hidden := 0
        this.shows := []
        this.failShow := failShow
    }
    Hide() {
        this.hidden += 1
    }
    Show(options := "") {
        if this.failShow
            throw Error("Simulated destroyed modal")
        this.shows.Push(options)
    }
}
