; AHK v2. Requires ShortcutConfig.ahk and ModernControls.ahk in the parent script.
; ShowShortcutRecorder(ownerGui,currentBinding,onSaved,onClosed) -> dialog object.
; onSaved(binding) runs only for Save; a save failure keeps the candidate/window open.
; onClosed() follows successful destruction and owner restoration, including Cancel.
; CloseShortcutRecorderForExit() stops capture/timers and destroys without callbacks.
; No native shortcut sends or driver operations. Input is intercepted only after
; explicitly clicking Start, and capture stops immediately if the dialog loses focus.

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
        this.readyMessage := "先点击“开始录入”，再按你在豆包中设置的快捷键。"
        ShortcutRecorderStore.Active := this
        try {
            this.binding := ParseShortcut(IsObject(currentBinding) ? currentBinding.canonical : currentBinding)
            this.Build()
            owner.Opt("+Disabled")
            this.ownerDisabled := true
            this.window.Show((showWindow ? "" : "Hide ") "w500 h432")
        } catch as err {
            this.Finalize(false)
            throw err
        }
    }

    Build() {
        g := Gui("+Owner" this.owner.Hwnd " -MinimizeBox -MaximizeBox", "修改快捷键")
        this.window := g
        g.BackColor := "F8FAF9"
        g.MarginX := 28
        g.MarginY := 24
        g.SetFont("s18 bold c172E2A", "Microsoft YaHei UI")
        g.AddText("x28 y24 w444 h36", "修改快捷键")
        g.SetFont("s10 norm c71827B")
        g.AddText("x30 y72 w440 h42", "请与豆包输入法中的语音快捷键保持一致。`n这里只更改 Mic Air 按钮发出的按键。")
        g.SetFont("s9 c71827B")
        g.AddText("x30 y133 w440 h22", "准备使用的快捷键")
        g.SetFont("s17 bold c172E2A")
        this.label := g.AddText("x30 y163 w440 h44", this.binding.label)
        g.SetFont("s9 norm c71827B")
        this.status := g.AddText("x30 y216 w440 h46", this.readyMessage)
        g.SetFont("s10 bold cFFFFFF")
        this.record := ModernButton(g, "x28 y276 w444 h44", "开始录入", "primary")
        this.record.OnEvent("Click", ObjBindMethod(this, "Begin"))
        g.SetFont("s9 norm c71827B")
        this.defaults := ModernButton(g, "x22 y330 w226 h32", "恢复默认：右 Alt＋空格", "ghost")
        this.defaults.OnEvent("Click", ObjBindMethod(this, "UseDefault"))
        g.SetFont("s10 norm c29433C")
        this.cancelButton := ModernButton(g, "x244 y378 w108 h36", "取消", "secondary")
        this.cancelButton.OnEvent("Click", ObjBindMethod(this, "Cancel"))
        this.saveButton := ModernButton(g, "x364 y378 w108 h36", "保存", "primary")
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
        this.QueueRelease("start", "请先松开键盘按键，再开始录入。")
    }

    StartCapture() {
        if this.closed || !WinActive("ahk_id " this.window.Hwnd) {
            this.readyMessage := "录入已暂停。返回此窗口后，点击“开始录入”。"
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
        this.status.Text := "现在按下完整快捷键，松开后即可保存。`n单独按 Esc 取消；左右 Alt、Ctrl、Shift 会分别识别。"
        this.RefreshButtons()
        try this.hook.Start()
        catch as err {
            this.StopCapture()
            this.status.Text := "无法开始录入：" err.Message
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
            this.status.Text := "这个按键暂不支持。请使用空格、字母、数字或 F1–F24 等常用键。"
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
            this.status.Text := err.Message "`n松开按键后可重新输入。"
            return
        }
        this.binding := candidate
        this.label.Text := candidate.label
        this.readyMessage := "已记录。确认与豆包设置一致后，点击“保存”。"
        this.QueueRelease("ready", "已记录，请松开刚才的全部按键。")
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
        this.readyMessage := "录入已暂停。返回此窗口后，点击“开始录入”。"
        this.QueueRelease("ready", "录入已暂停，请松开按键。")
    }

    UseDefault(*) {
        if this.closed || this.waiting
            return
        this.binding := ParseShortcut()
        this.label.Text := this.binding.label
        this.readyMessage := "已恢复默认组合。点击“保存”后生效。"
        this.QueueRelease("ready", "请松开键盘按键。")
    }

    Save(*) {
        if this.closed || this.capturing || this.waiting
            return
        this.QueueRelease("save", "请松开键盘按键，随后保存。")
    }

    Cancel(*) {
        if this.closed
            return true
        this.QueueRelease("cancel", "请松开键盘按键，随后关闭。")
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
        this.record.Text := this.capturing ? "正在录入…" : "开始录入"
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
                this.readyMessage := "保存失败：" err.Message
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
