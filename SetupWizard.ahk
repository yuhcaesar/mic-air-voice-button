; AHK v2. Requires ModernControls.ahk in the parent script.
; UI only: no input capture/sending, driver access, timers or persistence.
; Callbacks take no arguments. Cancel requests the owner's cancellation flow;
; only Close destroys the dialog. The Edit's contents are never read or saved.
#Include Localization.ahk

ShowMicSetup(owner, onCancel, onRetry, onYes, onNo, onVolumeIssue := 0, onSwitchMode := 0, initialMode := "standard") {
    if IsObject(MicSetupStore.Active) && !MicSetupStore.Active.closed {
        MicSetupStore.Active.window.Show()
        return MicSetupStore.Active
    }
    return MicSetupDialog(owner, onCancel, onRetry, onYes, onNo, true, onVolumeIssue, onSwitchMode, initialMode)
}

class MicSetupStore {
    static Active := 0
}

class MicSetupDialog {
    __New(owner, onCancel, onRetry, onYes, onNo, showWindow := true, onVolumeIssue := 0, onSwitchMode := 0, initialMode := "standard") {
        this.owner := owner
        this.onCancel := onCancel
        this.onRetry := onRetry
        this.onYes := onYes
        this.onNo := onNo
        this.onVolumeIssue := IsObject(onVolumeIssue) ? onVolumeIssue : onCancel
        this.onSwitchMode := onSwitchMode
        this.window := 0
        this.closed := false
        this.ownerDisabled := false
        this.isBusy := false
        this.dispatching := false
        this.cancelRequested := false
        this.canRetry := false
        this.source := ""
        this.attempt := 0
        this.total := 0
        this.stage := "listening"
        this.language := AppLanguage.Current == "en" ? "en" : "zh"
        this.dialogWidth := this.language == "en" ? 640 : 560
        this.dialogHeight := this.language == "en" ? 500 : 480
        MicSetupStore.Active := this
        try {
            this.Build()
            this.SetMode(initialMode)
            this.Listening()
            owner.Opt("+Disabled")
            this.ownerDisabled := true
            ; Hide alone neither shows nor activates the window. Combining it
            ; with NoActivate would replace the hidden show mode in AHK.
            this.window.Show((showWindow ? "" : "Hide ") "w" this.dialogWidth " h" this.dialogHeight)
        } catch as err {
            this.Close()
            throw err
        }
    }

    Build() {
        g := Gui("+Owner" this.owner.Hwnd " -MinimizeBox -MaximizeBox", this.Say("设置 Mic Air", "Set up Mic Air"))
        this.window := g
        width := this.dialogWidth - 64
        lowerOffset := this.language == "en" ? 20 : 0
        g.BackColor := "F8FAF9"
        g.MarginX := 32
        g.MarginY := 24
        g.SetFont("s9 c71827B", this.Say("Microsoft YaHei UI", "Segoe UI"))
        this.stepLabel := g.AddText("x32 y24 w" width " h22", "")
        g.SetFont("s20 bold c172E2A")
        this.heading := g.AddText("x30 y62 w" (width + 4) " h40", "")
        g.SetFont("s11 norm c566D63")
        this.description := g.AddText("x32 y115 w" width " h60", "")
        g.SetFont("s10 c16816A")
        this.status := g.AddText("x32 y185 w" width " h26", "")
        g.SetFont("s9 c71827B")
        this.inputLabel := g.AddText("x32 y218 w" width " h22", this.Say("在这里试用语音输入", "Try voice input here"))
        g.SetFont("s12 norm c172E2A")
        this.input := g.AddEdit("x32 y244 w" width " h" (80 + lowerOffset // 2)
            " +Multi +WantReturn -VScroll", "")
        g.SetFont("s9 c71827B")
        this.hint := g.AddText("x32 y" (338 + lowerOffset // 2) " w" width " h42", "")
        actionY := 382 + lowerOffset
        halfWidth := (width - 12) // 2
        g.SetFont("s10 bold cFFFFFF")
        this.yesButton := ModernButton(g, "x32 y" actionY " w" halfWidth " h44",
            this.Say("两项正常，完成设置", "Both work, finish setup"), "primary")
        this.yesButton.OnEvent("Click", ObjBindMethod(this, "ChooseYes"))
        this.noButton := ModernButton(g, "x" (44 + halfWidth) " y" actionY " w" halfWidth " h44",
            this.Say("豆包未启动", "Voice did not start"), "secondary")
        this.noButton.OnEvent("Click", ObjBindMethod(this, "ChooseNo"))
        this.retryButton := ModernButton(g, "x32 y" actionY " w" width " h44",
            this.Say("重试", "Try again"), "primary")
        this.retryButton.OnEvent("Click", ObjBindMethod(this, "Retry"))
        this.switchModeButton := ModernButton(g, "x" (44 + halfWidth) " y" actionY " w" halfWidth " h44",
            "", "secondary")
        this.switchModeButton.OnEvent("Click", ObjBindMethod(this, "SwitchMode"))
        g.SetFont("s10 norm c71827B")
        this.cancelButton := ModernButton(g, "x32"
            " y" (438 + lowerOffset) " w112 h30", this.Say("取消", "Cancel"), "ghost")
        this.cancelButton.OnEvent("Click", ObjBindMethod(this, "Cancel"))
        this.volumeIssueButton := ModernButton(g, "x" (this.dialogWidth - 292)
            " y" (438 + lowerOffset) " w260 h30", this.Say("音量仍在变化", "Volume still changes"), "ghost")
        this.volumeIssueButton.OnEvent("Click", ObjBindMethod(this, "VolumeIssue"))
        g.OnEvent("Close", ObjBindMethod(this, "Cancel"))
        g.OnEvent("Escape", ObjBindMethod(this, "Cancel"))
    }

    Listening() {
        if this.closed
            return
        this.stage := "listening"
        this.source := ""
        this.attempt := 0
        this.total := 0
        this.canRetry := false
        this.stepLabel.Text := this.ModeName() " · 1 / 3"
        this.heading.Text := this.Say("识别 Mic Air 按钮", "Find your Mic Air button")
        this.description.Text := this.Say("松开键盘按键，再按一下 Mic Air 按钮。`n识别这一步可能调整一次音量。", "Release keyboard keys, then press Mic Air once.`nThis detection step may change volume once.")
        if this.mode = "compatibility"
            this.description.Text .= this.Say("`n此模式直接识别接收器的按钮消息。", "`nThis mode reads the receiver's button messages.")
        this.status.Text := this.Say("● 正在检测按钮…", "● Listening for your button…")
        this.Refresh()
    }

    Ready(source, attempt, total) {
        if this.closed
            return
        this.stage := "ready"
        this.source := source
        this.attempt := attempt
        this.total := total
        this.canRetry := false
        this.stepLabel.Text := this.ModeName() " · 2 / 3"
        this.heading.Text := this.Say("试着启动豆包语音", "Try Doubao voice input")
        this.description.Text := this.Say("点击下方输入框，再按一下 Mic Air 按钮。",
            "Click the box below, then press your Mic Air button once.")
        this.status.Text := this.Say("● 已识别按钮 · 尝试 {1} / {2}", "● Button found · Attempt {1} of {2}", attempt, total)
        this.Refresh()
        this.FocusInput()
    }

    Waiting(attempt, total) {
        if this.closed
            return
        this.stage := "waiting"
        this.attempt := attempt
        this.total := total
        this.canRetry := false
        this.stepLabel.Text := this.ModeName() " · 3 / 3"
        this.heading.Text := this.Say("语音和音量都正常吗？", "Voice works, volume unchanged?")
        this.description.Text := this.Say("请确认豆包语音已启动，而且系统音量不变、音量条没有弹出。两项都正常再完成设置。",
            "Confirm that Doubao started, volume stayed unchanged and no volume overlay appeared. Finish only when both work.")
        this.status.Text := this.Say("尝试 {1} / {2}", "Attempt {1} of {2}", attempt, total)
        ; Keep the same Edit and leave focus alone; Doubao may own a popup now.
        this.Refresh()
    }

    Failure(message, canRetry := true) {
        if this.closed
            return
        this.stage := "failure"
        this.canRetry := !!canRetry
        this.stepLabel.Text := this.ModeName()
        this.heading.Text := this.Say("还差一步", "One more step")
        this.description.Text := this.Render(message)
        this.status.Text := ""
        this.Refresh()
    }

    Busy(flag) {
        if this.closed
            return
        this.isBusy := !!flag
        this.Refresh()
    }

    SetMode(mode) {
        if !(mode = "standard" || mode = "compatibility")
            throw ValueError(this.Say("未知的按钮模式。", "Unknown button mode."))
        if this.closed
            return
        this.mode := mode
        this.switchModeButton.Text := mode = "standard"
            ? this.Say("改用兼容模式", "Use compatibility mode")
            : this.Say("改用标准模式", "Use standard mode")
        step := this.stage = "listening" ? 1 : this.stage = "ready" ? 2 : this.stage = "waiting" ? 3 : 0
        this.stepLabel.Text := this.ModeName() (step ? " · " step " / 3" : "")
        ModernRedraw(this.switchModeButton)
    }

    ModeName() => this.mode = "compatibility"
        ? this.Say("兼容模式", "Compatibility mode") : this.Say("标准模式", "Standard mode")

    Refresh() {
        if this.closed
            return
        showInput := this.stage = "ready" || this.stage = "waiting"
        showSwitch := this.stage = "failure" && this.canRetry && IsObject(this.onSwitchMode)
        this.description.Move(, , , this.stage = "failure" ? 172 : 60)
        this.status.Visible := this.stage != "failure"
        this.inputLabel.Visible := showInput
        this.input.Visible := showInput
        ; Keep the IME target editable while the controller sends the shortcut.
        ; Disabling it here would move focus away before Doubao starts.
        this.input.Enabled := showInput
        this.yesButton.Visible := this.stage = "waiting"
        this.noButton.Visible := this.stage = "waiting"
        this.volumeIssueButton.Visible := this.stage = "waiting"
        this.retryButton.Visible := this.stage = "failure" && this.canRetry
        this.switchModeButton.Visible := showSwitch
        this.retryButton.Move(, , showSwitch ? (this.dialogWidth - 76) // 2 : this.dialogWidth - 64)
        this.yesButton.Enabled := !this.isBusy && this.stage = "waiting"
        this.noButton.Enabled := !this.isBusy && this.stage = "waiting"
        this.volumeIssueButton.Enabled := !this.isBusy && this.stage = "waiting"
        this.retryButton.Enabled := !this.isBusy && this.stage = "failure" && this.canRetry
        this.switchModeButton.Enabled := !this.isBusy && showSwitch && !this.cancelRequested
        this.cancelButton.Enabled := !this.isBusy && !this.cancelRequested
        this.hint.Visible := showInput
        this.hint.Text := this.Say("音量＋已接管；调音量请用系统滑块。此处输入不会保存。", "Volume Up is remapped; use the system slider to adjust volume. This input is not saved.")
        this.hint.SetFont("c71827B")
        for button in [this.yesButton, this.noButton, this.volumeIssueButton, this.retryButton, this.switchModeButton, this.cancelButton]
            ModernRedraw(button)
    }

    FocusInput() {
        if this.closed || this.isBusy || !(this.stage = "ready" || this.stage = "waiting")
            || !WinActive("ahk_id " this.window.Hwnd)
            return false
        this.input.Focus()
        return this.InputFocused()
    }

    InputFocused(allowBusy := false) {
        return !this.closed && (allowBusy || !this.isBusy) && (this.stage = "ready" || this.stage = "waiting")
            && WinActive("ahk_id " this.window.Hwnd)
            && DllCall("User32\GetFocus", "Ptr") = this.input.Hwnd
    }

    ChooseYes(*) {
        if this.stage = "waiting"
            this.Invoke(this.onYes)
    }

    ChooseNo(*) {
        if this.stage = "waiting"
            this.Invoke(this.onNo)
    }

    VolumeIssue(*) {
        if this.stage = "waiting"
            this.Invoke(this.onVolumeIssue)
    }

    Retry(*) {
        if this.stage = "failure" && this.canRetry
            this.Invoke(this.onRetry)
    }

    SwitchMode(*) {
        if this.stage = "failure" && this.canRetry && !this.cancelRequested && IsObject(this.onSwitchMode)
            this.Invoke(this.onSwitchMode, this.mode = "standard" ? "compatibility" : "standard")
    }

    Cancel(*) {
        if this.closed || this.isBusy || this.cancelRequested || this.dispatching
            return true
        this.cancelRequested := true
        this.Refresh()
        try this.Invoke(this.onCancel)
        catch as err {
            this.cancelRequested := false
            this.Refresh()
            throw err
        }
        return true
    }

    Invoke(callback, args*) {
        if this.closed || this.isBusy || this.dispatching
            return
        this.dispatching := true
        try callback.Call(args*)
        finally this.dispatching := false
    }

    Close() {
        if this.closed
            return
        this.closed := true
        if IsObject(this.window)
            try this.window.Destroy()
        if this.ownerDisabled {
            this.ownerDisabled := false
            try this.owner.Opt("-Disabled")
        }
        if MicSetupStore.Active = this
            MicSetupStore.Active := 0
    }

    Say(zh, en, args*) {
        return this.Render(N(zh, en, args*))
    }

    Render(value) {
        ; Lock the wizard to its opening language without changing global state.
        if value is AppLocalizedMessage {
            values := []
            for argument in value.args
                values.Push(this.Render(argument))
            return Format(this.language = "en" ? value.en : value.zh, values*)
        }
        return Text(value)
    }
}
