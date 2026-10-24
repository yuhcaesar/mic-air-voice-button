; AHK v2. Requires ShortcutConfig.ahk and ModernControls.ahk in the parent script.
; ShowShortcutRecorder(ownerGui,currentBinding,onSaved,onClosed) -> dialog object.
; onSaved(binding) runs only for Save; a save failure keeps the candidate/window open.
; onClosed() follows successful destruction and owner restoration, including Cancel.
; CloseShortcutRecorderForExit() stops capture/timers and destroys without callbacks.
; No native shortcut sends or driver operations. Input is intercepted only after
; explicitly clicking Start, and capture stops immediately if the dialog loses focus.
#Include Localization.ahk

ShowShortcutRecorder(ownerGui, currentBinding, onSaved, onClosed) {
    if IsObject(ShortcutRecorderStore.Active) && !ShortcutRecorderStore.Active.closed {
        ShortcutRecorderStore.Active.window.Show()
        return ShortcutRecorderStore.Active
    }
    if !ShortcutRecorderStore.registered {
        OnMessage(0x0006, ShortcutRecorderActivation) ; WM_ACTIVATE
        ShortcutRecorderStore.registered := true
    }
    return ShortcutRecorderDialog(ownerGui, currentBinding, onSaved, onClosed)
}

CloseShortcutRecorderForExit() {
    if IsObject(ShortcutRecorderStore.Active)
        ShortcutRecorderStore.Active.Finalize(false, true)
}

ShortcutRecorderActivation(wParam, lParam, message, hwnd) {
    dialog := ShortcutRecorderStore.Active
    if IsObject(dialog) && !dialog.closed && IsObject(dialog.window)
        && hwnd = dialog.window.Hwnd && (wParam & 0xFFFF) = 0
        dialog.PauseForFocusLoss()
}

class ShortcutRecorderStore {
    static Active := 0
    static registered := false
}

class ShortcutRecorderDialog {
    __New(owner, currentBinding, onSaved, onClosed, showWindow := true) {
        this.owner := owner
        this.onSaved := onSaved
        this.onClosed := onClosed
        this.window := 0
        this.ownerDisabled := false
        this.closed := false
        this.capturing := false
        this.waiting := false
        this.afterRelease := ""
        this.hook := 0
        this.pressed := Map()
        this.modifiers := Map()
        this.releaseTimer := ObjBindMethod(this, "CheckReleased")
        this.readyMessage := L("先点击“开始录入”，再按你在豆包中设置的快捷键。",
            "Click Start recording, then press the shortcut you set in Doubao.")
        this.dialogWidth := AppLanguage.Current == "en" ? 560 : 500
        this.dialogHeight := AppLanguage.Current == "en" ? 464 : 432
        ShortcutRecorderStore.Active := this
        try {
            this.binding := ParseShortcut(IsObject(currentBinding) ? currentBinding.canonical : currentBinding)
            this.Build()
            owner.Opt("+Disabled")
            this.ownerDisabled := true
            this.window.Show((showWindow ? "" : "Hide ") "w" this.dialogWidth " h" this.dialogHeight)
        } catch as err {
            this.Finalize(false)
            throw err
        }
    }

    Build() {
        g := Gui("+Owner" this.owner.Hwnd " -MinimizeBox -MaximizeBox", L("修改快捷键", "Change shortcut"))
        this.window := g
        contentWidth := this.dialogWidth - 56
        english := AppLanguage.Current == "en"
        lowerOffset := english ? 32 : 0
        g.BackColor := "F8FAF9"
        g.MarginX := 28
        g.MarginY := 24
        g.SetFont("s18 bold c172E2A", L("Microsoft YaHei UI", "Segoe UI"))
        g.AddText("x28 y24 w" contentWidth " h36", L("修改快捷键", "Change shortcut"))
        g.SetFont("s10 norm c71827B")
        g.AddText("x30 y72 w" (contentWidth - 4) " h52", L(
            "请与豆包输入法中的语音快捷键保持一致。`n这里只更改 Mic Air 按钮发出的按键。",
            "Match the voice shortcut set in Doubao Input Method.`nThis only changes the keys sent by the Mic Air button."))
        g.SetFont("s9 c71827B")
        g.AddText("x30 y133 w" (contentWidth - 4) " h22", L("准备使用的快捷键", "Shortcut to use"))
        g.SetFont((english ? "s15" : "s17") " bold c172E2A")
        this.label := g.AddText("x30 y163 w" (contentWidth - 4) " h" (english ? 68 : 44), ShortcutDisplayLabel(this.binding))
        g.SetFont("s9 norm c71827B")
        this.status := g.AddText("x30 y" (216 + lowerOffset) " w" (contentWidth - 4) " h46", this.readyMessage)
        g.SetFont("s10 bold cFFFFFF")
        this.record := ModernButton(g, "x28 y" (276 + lowerOffset) " w" contentWidth " h44",
            L("开始录入", "Start recording"), "primary")
        this.record.OnEvent("Click", ObjBindMethod(this, "Begin"))
        g.SetFont("s9 norm c71827B")
        this.defaults := ModernButton(g, "x22 y" (330 + lowerOffset) " w" (english ? 286 : 226) " h32",
            L("恢复默认：右 Alt＋空格", "Reset: Right Alt + Space"), "ghost")
        this.defaults.OnEvent("Click", ObjBindMethod(this, "UseDefault"))
        g.SetFont("s10 norm c29433C")
        this.cancelButton := ModernButton(g, "x" (this.dialogWidth - 256) " y" (378 + lowerOffset) " w108 h36",
            L("取消", "Cancel"), "secondary")
        this.cancelButton.OnEvent("Click", ObjBindMethod(this, "Cancel"))
        this.saveButton := ModernButton(g, "x" (this.dialogWidth - 136) " y" (378 + lowerOffset) " w108 h36",
            L("保存", "Save"), "primary")
        this.saveButton.OnEvent("Click", ObjBindMethod(this, "Save"))
        g.OnEvent("Close", ObjBindMethod(this, "Cancel"))
        g.OnEvent("Escape", ObjBindMethod(this, "Cancel"))
    }

    Begin(*) {
        if this.closed || this.capturing || this.waiting
            return
        ; Keep physical key-state tracking reliable after the InputHook stops.
        ; Do not uninstall it here: the mapping owner also relies on physical state.
        InstallKeybdHook()
        this.pressed := Map()
        this.modifiers := Map()
        this.QueueRelease("start", L("请先松开键盘按键，再开始录入。", "Release all keys before recording."))
    }

    StartCapture() {
        if this.closed || !WinActive("ahk_id " this.window.Hwnd) {
            this.readyMessage := L("录入已暂停。返回此窗口后，点击“开始录入”。",
                "Recording paused. Return to this window and click Start recording.")
            this.status.Text := this.readyMessage
            this.RefreshButtons()
            return
        }
        this.pressed := Map()
        this.modifiers := Map()
        this.hook := InputHook("L0 I1")
        this.hook.KeyOpt("{All}", "NS")
        this.hook.OnKeyDown := ObjBindMethod(this, "KeyDown")
        this.hook.OnKeyUp := ObjBindMethod(this, "KeyUp")
        this.capturing := true
        this.status.Text := L("现在按下完整快捷键，松开后即可保存。`n单独按 Esc 取消；左右 Alt、Ctrl、Shift 会分别识别。",
            "Press the full shortcut, then release all keys.`nEsc alone cancels; left/right Alt, Ctrl and Shift are distinct.")
        this.RefreshButtons()
        try this.hook.Start()
        catch as err {
            this.StopCapture()
            this.status.Text := L("无法开始录入：{1}", "Could not start recording: {1}", err.Message)
            this.RefreshButtons()
        }
    }

    KeyDown(input, vk, sc) {
        if this.closed || !this.capturing
            return
        if !WinActive("ahk_id " this.window.Hwnd) {
            this.PauseForFocusLoss()
            return
        }
        physicalName := sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
        this.pressed[physicalName] := true
        name := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
        try name := ShortcutNormalizeName(name)
        catch ValueError {
            this.status.Text := L("这个按键暂不支持。请使用空格、字母、数字或 F1–F24 等常用键。",
                "This key is not supported. Use Space, letters, numbers, or F1–F24.")
            return
        }
        if ShortcutIsModifier(name) {
            this.modifiers[name] := true
            return
        }
        canonical := ""
        ; Event tracking preserves the chord even when key-up callbacks are queued.
        for modifier in ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"]
            if this.modifiers.Has(modifier)
                canonical .= modifier "+"
        if name = "Esc" && canonical = "" {
            this.Cancel()
            return
        }
        try candidate := ParseShortcut(canonical name)
        catch ValueError as err {
            this.status.Text := L("{1}`n松开按键后可重新输入。", "{1}`nRelease the keys, then try again.", err.Message)
            return
        }
        this.binding := candidate
        this.label.Text := ShortcutDisplayLabel(candidate)
        this.readyMessage := L("已记录。确认与豆包设置一致后，点击“保存”。",
            "Recorded. Check that this matches Doubao, then click Save.")
        this.QueueRelease("ready", L("已记录，请松开刚才的全部按键。", "Recorded. Release all keys in the shortcut."))
    }

    KeyUp(input, vk, sc) {
        if this.closed || !this.capturing
            return
        physicalName := sc ? Format("sc{:03X}", sc) : Format("vk{:02X}", vk)
        if this.pressed.Has(physicalName)
            this.pressed.Delete(physicalName)
        try {
            name := ShortcutNormalizeName(GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc)))
            if this.modifiers.Has(name)
                this.modifiers.Delete(name)
        }
    }

    StopCapture() {
        this.capturing := false
        if IsObject(this.hook) {
            this.hook.Stop()
            this.hook.OnKeyDown := ""
            this.hook.OnKeyUp := ""
            this.hook := 0
        }
    }

    PauseForFocusLoss() {
        if this.closed || (!this.capturing && !(this.waiting && this.afterRelease = "start"))
            return
        this.readyMessage := L("录入已暂停。返回此窗口后，点击“开始录入”。",
            "Recording paused. Return to this window and click Start recording.")
        this.QueueRelease("ready", L("录入已暂停，请松开按键。", "Recording paused. Release all keys."))
    }

    UseDefault(*) {
        if this.closed || this.waiting
            return
        this.binding := ParseShortcut()
        this.label.Text := ShortcutDisplayLabel(this.binding)
        this.readyMessage := L("已恢复默认组合。点击“保存”后生效。", "Default shortcut restored. Click Save to apply it.")
        this.QueueRelease("ready", L("请松开键盘按键。", "Release all keys."))
    }

    Save(*) {
        if this.closed || this.capturing || this.waiting
            return
        this.QueueRelease("save", L("请松开键盘按键，随后保存。", "Release all keys to save."))
    }

    Cancel(*) {
        if this.closed
            return true
        this.QueueRelease("cancel", L("请松开键盘按键，随后关闭。", "Release all keys to close."))
        return true
    }

    QueueRelease(action, message) {
        this.StopCapture()
        this.waiting := true
        this.afterRelease := action
        this.status.Text := message
        this.RefreshButtons()
        SetTimer(this.releaseTimer, 25)
    }

    CheckReleased() {
        if this.closed {
            SetTimer(this.releaseTimer, 0)
            return
        }
        ; Also cover Enter/Space/Esc used to activate or dismiss GUI buttons.
        for key in ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin", "Enter", "Space", "Esc"]
            if GetKeyState(key, "P")
                return
        for key in this.pressed
            if GetKeyState(key, "P")
                return
        SetTimer(this.releaseTimer, 0)
        this.waiting := false
        action := this.afterRelease
        this.afterRelease := ""
        if action = "start"
            this.StartCapture()
        else if action = "save"
            this.Finalize(true)
        else if action = "cancel"
            this.Finalize(false)
        else {
            this.status.Text := this.readyMessage
            this.RefreshButtons()
        }
    }

    RefreshButtons() {
        if this.closed || !IsObject(this.window)
            return
        this.record.Text := this.capturing ? L("正在录入…", "Recording…") : L("开始录入", "Start recording")
        this.record.Enabled := !this.capturing && !this.waiting
        this.saveButton.Enabled := !this.capturing && !this.waiting
        this.defaults.Enabled := !this.waiting
        for button in [this.record, this.saveButton, this.defaults, this.cancelButton]
            ModernRedraw(button)
    }

    Finalize(save, forExit := false) {
        if this.closed
            return
        if save && !forExit {
            try this.onSaved.Call(ParseShortcut(this.binding.canonical))
            catch as err {
                SetTimer(this.releaseTimer, 0)
                this.waiting := false
                this.afterRelease := ""
                this.readyMessage := L("保存失败：{1}", "Could not save: {1}", err.Message)
                this.status.Text := this.readyMessage
                this.RefreshButtons()
                return
            }
        }
        this.closed := true
        SetTimer(this.releaseTimer, 0)
        this.StopCapture()
        ShortcutRecorderStore.Active := 0
        if this.ownerDisabled {
            try this.owner.Opt("-Disabled")
            this.ownerDisabled := false
        }
        if IsObject(this.window)
            this.window.Destroy()
        if !forExit {
            try WinActivate("ahk_id " this.owner.Hwnd)
            this.onClosed.Call()
        }
    }
}
