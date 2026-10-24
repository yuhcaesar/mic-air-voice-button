; AHK v2: configure after Main adds its tray items and sets A_TrayMenu.Default.
; ConfigureTrayWindow(gui, restoreCallback [, identity]) changes no menu items.
; RequestExistingTrayWindow([timeoutMs, identity]) returns true only on an IPC ACK.
; RestoreTrayWindow(gui [, modalGetter]) restores the active modal, if present.
; identity is optional for isolated tests; production callers use the default.

ConfigureTrayWindow(mainGui, restoreCallback, identity := "MicAirDoubao.TrayWindow.IPC.v1") {
    static messageHandler := ObjBindMethod(TrayWindowState, "HandleMessage")
    TrayWindowState.RestoreCallback := restoreCallback
    A_TrayMenu.ClickCount := 1
    mainGui.OnEvent("Size", TrayWindowSize)
    OnMessage(TrayWindowState.Message, messageHandler)
    ; Publish only after the callback is ready. This is AHK's hidden script
    ; window, not the user-facing Gui or an unrelated application's window.
    if !DllCall("User32\SetWindowTextW", "Ptr", A_ScriptHwnd, "Str", identity, "Int")
        throw OSError()
}

RequestExistingTrayWindow(timeoutMs := 2000, identity := "MicAirDoubao.TrayWindow.IPC.v1") {
    oldHidden := A_DetectHiddenWindows
    oldMatch := A_TitleMatchMode
    DetectHiddenWindows(true)
    SetTitleMatchMode(3)
    deadline := A_TickCount + Max(0, timeoutMs)
    try {
        loop {
            for hwnd in WinGetList(identity " ahk_class AutoHotkey") {
                if hwnd = A_ScriptHwnd
                    continue
                try {
                    ; A newly launched process may hand its foreground allowance
                    ; to the existing instance before asking that instance to show.
                    DllCall("User32\AllowSetForegroundWindow", "UInt", WinGetPID(hwnd), "Int")
                    ack := SendMessage(TrayWindowState.Message, TrayWindowState.Magic,
                        0, , hwnd, , , , Max(1, Min(500, deadline - A_TickCount)))
                    if ack = TrayWindowState.Magic
                        return true
                }
            }
            if A_TickCount >= deadline
                return false
            Sleep(Min(50, deadline - A_TickCount))
        }
    } finally {
        SetTitleMatchMode(oldMatch)
        DetectHiddenWindows(oldHidden)
    }
}

RestoreTrayWindow(mainGui, modalGetter := 0) {
    modal := 0
    if IsObject(modalGetter)
        try modal := modalGetter.Call()
    if IsObject(modal) {
        try {
            ; NoActivate restores a hidden/minimized owner without focusing it.
            mainGui.Show("NoActivate")
            modal.Show()
            return modal
        }
    }
    ; Gui.Show restores a minimized Gui and activates it (AHK v2's native path).
    mainGui.Show()
    return mainGui
}

TrayWindowSize(gui, minMax, width, height) {
    if minMax = -1
        gui.Hide()
}

class TrayWindowState {
    static Message := 0x84D1 ; private WM_APP message; never a tray notification
    static Magic := 0x4D414952
    static RestoreCallback := 0

    static HandleMessage(wParam, lParam, msg, hwnd) {
        if hwnd != A_ScriptHwnd || wParam != TrayWindowState.Magic || lParam != 0
            return
        try {
            TrayWindowState.RestoreCallback.Call()
            return TrayWindowState.Magic
        } catch {
            return 0
        }
    }
}
