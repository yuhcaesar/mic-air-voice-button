; AHK v2 x64 — native, accessible owner-drawn buttons, with no external assets.
; ModernButton(gui, options, text, style := "primary") returns a real Gui.Button.
; Supports normal .Text / .Enabled / .OnEvent("Click", ...) / .SetFont(...).
; Styles: primary, secondary, ghost, danger. Set gui.BackColor := "F8FAF9".
; ModernRedraw(button) can be called after changing text, enabled state or font.
; Button font comes from WM_GETFONT; corners/focus strokes scale with window DPI.
; WM_DRAWITEM paints only registered buttons; all other window messages pass through.

ModernButton(gui, options, text, style := "primary") {
    static registered := false
    if !registered {
        OnMessage(0x002B, ModernButtonDraw, -1) ; WM_DRAWITEM
        registered := true
    }
    if !ModernButtonState.Palettes.Has(style)
        throw ValueError("Unknown modern button style: " style)
    button := gui.AddButton(options " +0x000B", text) ; BS_OWNERDRAW
    background := gui.BackColor
    surface := RegExMatch(background, "i)^[0-9a-f]{6}$") ? Integer("0x" background) : 0xF8FAF9
    ModernButtonState.Buttons[button.Hwnd] := {style: style, surface: surface}
    ; AHK normalizes AddButton's low style bits to PUSHBUTTON/DEFPUSHBUTTON.
    ; Set OWNERDRAW after creation, and preserve it when the dialog manager
    ; sends BM_SETSTYLE while moving default-button focus.
    if !ModernButtonState.SubclassCallback
        ModernButtonState.SubclassCallback := CallbackCreate(ModernButtonSubclass, "Fast", 6)
    if !DllCall("Comctl32\SetWindowSubclass", "Ptr", button.Hwnd,
        "Ptr", ModernButtonState.SubclassCallback, "UPtr", 0x4D4142, "UPtr", 0, "Int")
        throw OSError()
    ModernRedraw(button)
    return button
}

ModernRedraw(button) {
    hwnd := button.Hwnd
    style := DllCall("User32\GetWindowLongPtrW", "Ptr", hwnd, "Int", -16, "Ptr")
    if (style & 0xF) != 0xB
        DllCall("User32\SendMessageW", "Ptr", hwnd, "UInt", 0x00F4,
            "Ptr", (style & 0xFFF0) | 0xB, "Ptr", true, "Ptr")
    ; Invalidate only; Windows batches painting, so rapid status changes stay smooth.
    DllCall("User32\InvalidateRect", "Ptr", hwnd, "Ptr", 0, "Int", false)
}

class ModernButtonState {
    static Buttons := Map()
    static SubclassCallback := 0
    static Palettes := Map(
        "primary", {fill: 0x172E2A, pressed: 0x0D211D, text: 0xFFFFFF,
            disabledFill: 0xDFE7E2, disabledText: 0x7C8B82, focus: 0x8CB5A4},
        "secondary", {fill: 0xE9F0ED, pressed: 0xDCE7E1, text: 0x29433C,
            disabledFill: 0xEDF2EF, disabledText: 0x89978F, focus: 0x7EAA98},
        "ghost", {fill: 0xF8FAF9, pressed: 0xE9F0ED, text: 0x566D63,
            disabledFill: 0xF8FAF9, disabledText: 0x9AA69F, focus: 0xA0BEB0},
        "danger", {fill: 0xF8EEEE, pressed: 0xF0DEDC, text: 0x955D57,
            disabledFill: 0xF4F1EF, disabledText: 0xA69790, focus: 0xC49A94})
}

ModernButtonSubclass(hwnd, message, wParam, lParam, subclassId, reference) {
    if message = 0x00F4 ; BM_SETSTYLE: retain all flags except native button type.
        wParam := (wParam & ~0xF) | 0xB
    else if message = 0x0082 { ; WM_NCDESTROY
        DllCall("Comctl32\RemoveWindowSubclass", "Ptr", hwnd,
            "Ptr", ModernButtonState.SubclassCallback, "UPtr", subclassId)
        if ModernButtonState.Buttons.Has(hwnd)
            ModernButtonState.Buttons.Delete(hwnd)
    }
    return DllCall("Comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", message,
        "Ptr", wParam, "Ptr", lParam, "Ptr")
}

ModernButtonDraw(wParam, lParam, *) {
    if !lParam || NumGet(lParam, 0, "UInt") != 4 ; ODT_BUTTON
        return
    hwndOffset := A_PtrSize = 8 ? 24 : 20
    hwnd := NumGet(lParam, hwndOffset, "Ptr")
    if !ModernButtonState.Buttons.Has(hwnd)
        return
    hdc := NumGet(lParam, hwndOffset + A_PtrSize, "Ptr")
    rectOffset := hwndOffset + A_PtrSize * 2
    left := NumGet(lParam, rectOffset, "Int")
    top := NumGet(lParam, rectOffset + 4, "Int")
    right := NumGet(lParam, rectOffset + 8, "Int")
    bottom := NumGet(lParam, rectOffset + 12, "Int")
    state := NumGet(lParam, 16, "UInt")
    disabled := !!(state & 0x0004)
    pressed := !!(state & 0x0001) && !disabled
    focused := !!(state & 0x0010) && !(state & 0x0200) && !disabled
    info := ModernButtonState.Buttons[hwnd]
    colors := ModernButtonState.Palettes[info.style]
    fill := disabled ? colors.disabledFill : pressed ? colors.pressed : colors.fill
    textColor := disabled ? colors.disabledText : colors.text
    dpi := A_ScreenDPI
    try {
        detectedDpi := DllCall("User32\GetDpiForWindow", "Ptr", hwnd, "UInt")
        if detectedDpi
            dpi := detectedDpi
    }
    scale := dpi / 96
    diameter := Max(2, Round(24 * scale))
    saved := DllCall("Gdi32\SaveDC", "Ptr", hdc, "Int")
    surfaceBrush := 0, bodyBrush := 0, focusPen := 0
    try {
        rect := Buffer(16)
        NumPut("Int", left, "Int", top, "Int", right, "Int", bottom, rect)
        surfaceBrush := DllCall("Gdi32\CreateSolidBrush", "UInt", ModernColorRef(info.surface), "Ptr")
        DllCall("User32\FillRect", "Ptr", hdc, "Ptr", rect, "Ptr", surfaceBrush)
        bodyBrush := DllCall("Gdi32\CreateSolidBrush", "UInt", ModernColorRef(fill), "Ptr")
        DllCall("Gdi32\SelectObject", "Ptr", hdc, "Ptr", bodyBrush, "Ptr")
        nullPen := DllCall("Gdi32\GetStockObject", "Int", 8, "Ptr") ; NULL_PEN
        DllCall("Gdi32\SelectObject", "Ptr", hdc, "Ptr", nullPen, "Ptr")
        DllCall("Gdi32\RoundRect", "Ptr", hdc, "Int", left, "Int", top,
            "Int", right, "Int", bottom, "Int", diameter, "Int", diameter)
        if focused {
            inset := Max(2, Round(3 * scale))
            focusPen := DllCall("Gdi32\CreatePen", "Int", 0, "Int", Max(1, Round(2 * scale)),
                "UInt", ModernColorRef(colors.focus), "Ptr")
            DllCall("Gdi32\SelectObject", "Ptr", hdc, "Ptr", focusPen, "Ptr")
            hollowBrush := DllCall("Gdi32\GetStockObject", "Int", 5, "Ptr") ; NULL_BRUSH
            DllCall("Gdi32\SelectObject", "Ptr", hdc, "Ptr", hollowBrush, "Ptr")
            DllCall("Gdi32\RoundRect", "Ptr", hdc, "Int", left + inset, "Int", top + inset,
                "Int", right - inset, "Int", bottom - inset,
                "Int", Max(2, diameter - inset * 2), "Int", Max(2, diameter - inset * 2))
        }
        font := DllCall("User32\SendMessageW", "Ptr", hwnd, "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr")
        if !font
            font := DllCall("Gdi32\GetStockObject", "Int", 17, "Ptr") ; DEFAULT_GUI_FONT
        DllCall("Gdi32\SelectObject", "Ptr", hdc, "Ptr", font, "Ptr")
        DllCall("Gdi32\SetBkMode", "Ptr", hdc, "Int", 1)
        DllCall("Gdi32\SetTextColor", "Ptr", hdc, "UInt", ModernColorRef(textColor))
        textLength := DllCall("User32\GetWindowTextLengthW", "Ptr", hwnd, "Int")
        caption := Buffer((textLength + 1) * 2)
        DllCall("User32\GetWindowTextW", "Ptr", hwnd, "Ptr", caption, "Int", textLength + 1)
        pad := Max(4, Round(12 * scale))
        offset := pressed ? Max(1, Round(scale)) : 0
        NumPut("Int", left + pad, "Int", top + offset,
            "Int", right - pad, "Int", bottom + offset, rect)
        flags := 0x0001 | 0x0004 | 0x0020 | 0x8000 ; CENTER, VCENTER, SINGLELINE, END_ELLIPSIS
        if state & 0x0100 ; ODS_NOACCEL
            flags |= 0x100000 ; DT_HIDEPREFIX
        DllCall("User32\DrawTextW", "Ptr", hdc, "Ptr", caption, "Int", textLength,
            "Ptr", rect, "UInt", flags, "Int")
    } finally {
        if saved
            DllCall("Gdi32\RestoreDC", "Ptr", hdc, "Int", saved)
        if focusPen
            DllCall("Gdi32\DeleteObject", "Ptr", focusPen)
        if bodyBrush
            DllCall("Gdi32\DeleteObject", "Ptr", bodyBrush)
        if surfaceBrush
            DllCall("Gdi32\DeleteObject", "Ptr", surfaceBrush)
    }
    return true
}

ModernColorRef(rgb) {
    return ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
}
