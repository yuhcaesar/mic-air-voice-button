#Requires AutoHotkey v2.0 64-bit
#NoTrayIcon
#Include %A_ScriptDir%\..\ModernControls.ahk
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\modern-controls"
DirCreate(testDir)
g := Gui(, "Off-screen modern control test")
g.BackColor := "F8FAF9"
g.SetFont("s11", "Microsoft YaHei UI")
buttons := []
for style in ["primary", "secondary", "ghost", "danger"] {
    button := ModernButton(g, "w270 h44", "启用映射 · 测试", style)
    if Type(button) != "Gui.Button"
        throw Error("Button does not retain its native control type")
    buttons.Push(button)
}
g.Show("Hide w400 h300")
dc := DllCall("Gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
bitmap := DllCall("Gdi32\CreateBitmap", "Int", 400, "Int", 100, "UInt", 1, "UInt", 32, "Ptr", 0, "Ptr")
original := DllCall("Gdi32\SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
resultPath := testDir "\report.txt"
try {
    for button in buttons {
        style := DllCall("User32\GetWindowLongPtrW", "Ptr", button.Hwnd, "Int", -16, "Ptr")
        if (style & 0xF) != 0xB
            throw Error("Native button lost BS_OWNERDRAW after creation")
    }
    ; Exercise the real Windows drawing route, not only the callback directly.
    DllCall("User32\SendMessageW", "Ptr", buttons[1].Hwnd, "UInt", 0x318, "Ptr", dc, "Ptr", 4)
    if DllCall("Gdi32\GetPixel", "Ptr", dc, "Int", 25, "Int", 25, "UInt") != 0x2A2E17
        throw Error("Native button paint did not use the primary surface color")
    DrawPass()
    countBefore := DllCall("User32\GetGuiResources", "Ptr", -1, "UInt", 0, "UInt")
    loop 50
        DrawPass()
    countAfter := DllCall("User32\GetGuiResources", "Ptr", -1, "UInt", 0, "UInt")
    if countAfter > countBefore
        throw Error("GDI handle leak: " countBefore " -> " countAfter)
    buttons[1].Text := "启用"
    buttons[1].Enabled := false
    ModernRedraw(buttons[1])
    if buttons[1].Enabled || buttons[1].Text != "启用"
        throw Error("Native state setter verification failed")
    FileOpen(resultPath, "w", "UTF-8").Write("PASS: native owner-draw style and actual Windows painting route.`r`nPASS: 4 native button styles, normal/pressed/disabled/focus/hidden-cue rendering.`r`nPASS: Text/Enabled properties preserved.`r`nPASS: 1020 off-screen draws; GDI handles " countBefore " -> " countAfter ".`r`nNo visible window, synthetic input, driver calls or external app operations.")
} catch as err {
    FileOpen(resultPath, "w", "UTF-8").Write("FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
} finally {
    DllCall("Gdi32\SelectObject", "Ptr", dc, "Ptr", original, "Ptr")
    DllCall("Gdi32\DeleteObject", "Ptr", bitmap)
    DllCall("Gdi32\DeleteDC", "Ptr", dc)
    g.Destroy()
}
ExitApp(0)

DrawPass() {
    global buttons, dc
    for button in buttons {
        for state in [0, 1, 4, 16, 0x310] {
            item := Buffer(64, 0)
            NumPut("UInt", 4, item, 0)
            NumPut("UInt", 1, item, 12)
            NumPut("UInt", state, item, 16)
            NumPut("Ptr", button.Hwnd, item, 24)
            NumPut("Ptr", dc, item, 32)
            NumPut("Int", 0, "Int", 0, "Int", 400, "Int", 100, item, 40)
            if ModernButtonDraw(0, item.Ptr) != true
                throw Error("Unprocessed custom draw")
        }
    }
}
