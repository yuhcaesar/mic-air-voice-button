#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include %A_ScriptDir%\..\ModernControls.ahk
#Include %A_ScriptDir%\..\SetupWizard.ahk

; Hidden windows and callbacks only. No hooks, synthetic key presses, driver
; calls or real settings. The test fixture text is assigned directly to Edit.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\setup-wizard"
DirCreate(testDir)
report := "Mic Air setup wizard: hidden-window tests only.`r`n"
dialog := 0
ownerWindow := 0
try {
    foreground := DllCall("User32\GetForegroundWindow", "Ptr")
    buttonsBefore := ModernButtonState.Buttons.Count
    for language in ["zh", "en"] {
        AppLanguage.Current := language
        counts := {cancel: 0, retry: 0, yes: 0, no: 0, volume: 0}
        ownerWindow := Gui(, "Hidden setup test owner")
        ownerWindow.Show("Hide w100 h80")
        owner := SetupTestOwner(ownerWindow)
        dialog := MicSetupDialog(owner, (*) => counts.cancel++, (*) => counts.retry++,
            (*) => counts.yes++, (*) => counts.no++, false, (*) => counts.volume++)
        Check(MicSetupStore.Active = dialog && !dialog.closed, "Active dialog is tracked")
        Check(owner.disables = 1 && owner.enables = 0, "Owner disabled exactly once")
        Check(!DllCall("User32\IsWindowEnabled", "Ptr", owner.Hwnd, "Int"), "Native owner is disabled")
        Check(!DllCall("User32\IsWindowVisible", "Ptr", dialog.window.Hwnd, "Int"), "Dialog stays hidden")
        Check(DllCall("User32\GetForegroundWindow", "Ptr") = foreground, "Hidden construction does not activate a window")
        Check(dialog.heading.Text = (language = "en" ? "Find your Mic Air button" : "识别 Mic Air 按钮"), "Listening title")
        Check(!ControlIsShown(dialog.input) && !ControlIsShown(dialog.yesButton), "Listening hides trial controls")
        Check(!ControlIsShown(dialog.volumeIssueButton), "Listening hides volume-result action")
        dialog.VolumeIssue()
        Check(counts.volume = 0, "Listening cannot report a trial result")
        Check(!dialog.InputFocused() && !dialog.FocusInput(), "Hidden listening window cannot claim input focus")

        dialog.Ready("hid", 1, 3)
        Check(dialog.heading.Text = (language = "en" ? "Try Doubao voice input" : "试着启动豆包语音"), "Ready title")
        Check(Type(dialog.input) = "Gui.Edit" && ControlIsShown(dialog.input), "Ready exposes a real Edit")
        Check(!(ControlStyle(dialog.input) & 0x800), "The trial Edit is not read-only")
        Check(ControlIsShown(dialog.hint) && InStr(dialog.hint.Text, language = "en" ? "slider" : "滑块"), "Trial explains how to adjust volume while remapped")
        Check(!ControlIsShown(dialog.yesButton) && !ControlIsShown(dialog.retryButton)
            && !ControlIsShown(dialog.volumeIssueButton), "Ready has no premature answer or retry action")
        Check(!dialog.InputFocused() && !dialog.FocusInput(), "Ready does not focus a hidden window")
        Check(DllCall("User32\GetForegroundWindow", "Ptr") = foreground, "Ready leaves the foreground unchanged")
        dialog.input.Value := "TEST_FIXTURE_ONLY"

        ; Programmatic global changes cannot mix languages in an open wizard.
        AppLanguage.Current := language = "en" ? "zh" : "en"
        dialog.Waiting(1, 3)
        Check(dialog.heading.Text = (language = "en" ? "Voice works, volume unchanged?" : "语音和音量都正常吗？"), "Joint-result question retains opening language")
        Check(InStr(dialog.description.Text, language = "en" ? "Doubao started" : "豆包语音已启动")
            && InStr(dialog.description.Text, language = "en" ? "volume stayed unchanged" : "系统音量不变")
            && InStr(dialog.description.Text, language = "en" ? "no volume overlay" : "音量条没有弹出"),
            "Confirmation requires voice, unchanged volume and no overlay")
        Check(dialog.input.Value = "TEST_FIXTURE_ONLY" && ControlIsShown(dialog.input), "Waiting preserves trial text and Edit")
        Check(ControlIsShown(dialog.yesButton) && ControlIsShown(dialog.noButton), "Waiting shows both answers")
        Check(ControlIsShown(dialog.volumeIssueButton), "Waiting offers a separate volume-failure result")
        Check(InStr(dialog.yesButton.Text, language = "en" ? "Both" : "两项"), "Completion explicitly confirms both results")
        Check(DllCall("User32\GetForegroundWindow", "Ptr") = foreground, "Waiting never steals foreground focus")

        dialog.Busy(true)
        Check(dialog.input.Enabled, "Busy keeps the IME target editable")
        Check(!dialog.yesButton.Enabled && !dialog.noButton.Enabled
            && !dialog.volumeIssueButton.Enabled && !dialog.retryButton.Enabled
            && !dialog.cancelButton.Enabled, "Busy disables every action button")
        dialog.ChooseYes()
        dialog.ChooseNo()
        dialog.VolumeIssue()
        dialog.Retry()
        dialog.Cancel()
        Check(counts.yes + counts.no + counts.volume + counts.retry + counts.cancel = 0 && !dialog.closed, "Busy blocks callbacks, including Cancel")
        dialog.Busy(false)
        dialog.ChooseYes()
        dialog.ChooseNo()
        dialog.VolumeIssue()
        Check(counts.yes = 1 && counts.no = 1 && counts.volume = 1 && !dialog.closed,
            "Joint success, voice failure and volume failure notify separate callbacks without closing")

        dialog.Failure(N("请重试：{1}", "Please retry: {1}", N("接收器未连接", "Receiver disconnected")))
        Check(dialog.description.Text = (language = "en" ? "Please retry: Receiver disconnected" : "请重试：接收器未连接"), "Nested failure text retains opening language")
        Check(!ControlIsShown(dialog.input) && ControlIsShown(dialog.retryButton), "Failure offers retry and hides the trial field")
        Check(!ControlIsShown(dialog.hint) && !ControlIsShown(dialog.volumeIssueButton),
            "Failure no longer claims remapping is active or offers stale trial results")
        dialog.VolumeIssue()
        Check(counts.volume = 1, "Failure cannot repeat the prior volume-result callback")
        dialog.Retry()
        Check(counts.retry = 1, "Retry callback runs once")
        dialog.Failure(N("请稍后重试。", "Please try again later."), false)
        dialog.Retry()
        Check(!ControlIsShown(dialog.retryButton) && counts.retry = 1, "Nonretryable failure cannot retry")

        dialog.Listening()
        Check(!ControlIsShown(dialog.hint) && dialog.source = "", "New detection clears the previous source state")
        dialog.Ready("registered", 2, 3)
        Check(InStr(dialog.hint.Text, language = "en" ? "slider" : "滑块"), "Registered input also explains remapped volume behavior")
        Check(dialog.input.Value = "TEST_FIXTURE_ONLY", "Stage changes never clear or replace trial input")
        dialog.Cancel()
        dialog.Cancel()
        Check(counts.cancel = 1 && !dialog.closed && owner.enables = 0, "Cancel requests controller cleanup once")
        dialog.Close()
        dialog.Close()
        Check(dialog.closed && MicSetupStore.Active = 0 && owner.enables = 1, "Close is idempotent and restores the owner exactly once")
        Check(DllCall("User32\IsWindowEnabled", "Ptr", owner.Hwnd, "Int"), "Owner is enabled after close")
        Check(counts.cancel = 1, "Close does not invoke the cancellation callback")
        Check(ModernButtonState.Buttons.Count = buttonsBefore, "Destroyed controls release modern-button registrations")
        Check(DllCall("User32\GetForegroundWindow", "Ptr") = foreground, "Complete hidden flow leaves foreground unchanged")
        ownerWindow.Destroy()
        ownerWindow := 0
        report .= "PASS " language ": joint voice/volume confirmation, distinct failure actions, editable field, fixed language, busy guards, idempotent cleanup and no foreground activation.`r`n"
    }
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report)
    ExitApp(0)
} catch as err {
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report "FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
} finally {
    if IsObject(dialog)
        dialog.Close()
    if IsObject(ownerWindow)
        ownerWindow.Destroy()
}

Check(condition, message) {
    if !condition
        throw Error(message)
}

ControlStyle(control) {
    return DllCall("User32\GetWindowLongPtrW", "Ptr", control.Hwnd, "Int", -16, "Ptr")
}

ControlIsShown(control) {
    return !!(ControlStyle(control) & 0x10000000)
}

class SetupTestOwner {
    __New(window) {
        this.window := window
        this.Hwnd := window.Hwnd
        this.disables := 0
        this.enables := 0
    }
    Opt(options) {
        if options = "+Disabled"
            this.disables++
        else if options = "-Disabled"
            this.enables++
        this.window.Opt(options)
    }
}
