; The wizard never infers success from interception_send. Only the user's
; explicit confirmation after an actual trial commits a machine profile.
MicSetupActive() {
    global S
    return S.HasOwnProp("settingUp") && S.settingUp
}

BeginMicSetup(*) {
    global S, UI
    if S.busy || S.maintenance || S.editing || S.held.keys.Length || S.pendingReboot
        return
    if MicSetupActive() {
        S.setup.dialog.window.Show()
        return
    }
    if !DriverReady()
        return
    wasEnabled := S.enabled
    StopMapping(false)
    S.settingUp := true
    S.setup := {dialog: 0, stage: "starting", profile: 0, candidates: [], index: 1,
        priorEnabled: wasEnabled, tested: false, notBefore: 0}
    try {
        S.setup.dialog := ShowMicSetup(UI["window"], CancelMicSetup, StartMicLearning,
            ConfirmMicSetup, NextMicOutput, MicSetupVolumeIssue)
        StartMicLearning()
    } catch as err {
        CancelMicSetup(false)
        S.notice := N("无法开始按钮设置：{1}", "Could not start button setup: {1}", ErrorText(err))
    }
    UpdateUI()
}

StartMicLearning(*) {
    global S, DataDir
    if !MicSetupActive() || S.busy || S.held.keys.Length
        return
    SetTimer(MicLearningTimeout, 0)
    try {
        if IsObject(S.button)
            S.button.Stop()
        if !IsObject(S.native)
            S.native := NativeOutput(DataDir "\components\interception.dll")
        S.devices := S.native.Enumerate()
        S.setup.candidates := GetOutputCandidates(S.devices, S.savedHid)
        if !S.setup.candidates.Length
            throw LocalError("没有找到可用连接。请连接键盘和 Mic Air 接收器，再重试。",
                "No usable connection was found. Connect a keyboard and the Mic Air receiver, then retry.")
        S.setup.index := 1
        S.setup.tested := false
        S.setup.profile := 0
        S.setup.stage := "learning"
        S.setup.dialog.Listening()
        S.button := MicButtonInput(DataDir "\components\volume-guard.dll")
        S.button.Learn(MicButtonDetected)
        SetTimer(MicLearningTimeout, -30000)
        Log("setup_listening")
    } catch as err {
        MicInputFault(ErrorText(err), "learn_start")
    }
}

MicLearningTimeout() {
    global S
    if MicSetupActive() && S.setup.stage = "learning"
        MicInputFault(N("还没识别到按钮。请确认接收器已连接，再点击重试。",
            "The button has not been identified. Check the receiver connection, then retry."), "learn_timeout")
}

MicButtonDetected(profile) {
    global S
    if !MicSetupActive() || S.setup.stage != "learning"
        return
    SetTimer(MicLearningTimeout, 0)
    S.setup.profile := profile
    Log("setup_button_detected mode=" profile.source)
    try {
        S.button.Stop()
        S.button.Start(profile, MicSetupPress, MicInputFault)
        PrepareMicTrial()
    } catch as err
        MicInputFault(ErrorText(err), "input_start")
}

PrepareMicTrial() {
    global S
    if !MicSetupActive()
        return
    if S.setup.index > S.setup.candidates.Length {
        MicInputFault(N("按钮已识别，但这些连接都未能启动豆包。请确认手动快捷键可用，并与本工具设置一致，再重试。",
            "The button was detected, but voice input did not start. Check that the manual shortcut works and matches AirKey, then retry."))
        return
    }
    S.setup.stage := "ready"
    S.setup.tested := false
    ; Ignore the tail of the initial learning press or the last trial.
    S.setup.notBefore := A_TickCount + 800
    S.setup.dialog.Ready(S.setup.profile.source, S.setup.index, S.setup.candidates.Length)
}

MicSetupPress(*) {
    global S
    if !MicSetupActive() || S.setup.stage != "ready" || S.busy
        || A_TickCount < S.setup.notBefore || S.held.keys.Length
        return
    if !S.setup.dialog.InputFocused() {
        S.setup.dialog.FocusInput()
        return
    }
    for key in ["LAlt", "RAlt", "LCtrl", "RCtrl", "LShift", "RShift", "LWin", "RWin", S.binding.keys[S.binding.keys.Length].ahkName] {
        if GetKeyState(key, "P") {
            Log("setup_trial_skipped held_key")
            return
        }
    }
    Critical("On")
    S.busy := true
    S.setup.stage := "sending"
    S.setup.dialog.Busy(true)
    trialFailed := false
    focusLost := false
    try {
        device := S.devices[S.setup.candidates[S.setup.index]]
        guardedOutput := MicSetupOutput(S.native, ObjBindMethod(S.setup.dialog, "InputFocused", true))
        SendConfiguredShortcut(guardedOutput, device.id, S.binding, S.held)
        S.setup.tested := true
        S.setup.stage := "confirming"
        S.setup.dialog.Waiting(S.setup.index, S.setup.candidates.Length)
        Log("setup_shortcut_sent candidate=" S.setup.index)
    } catch as err {
        trialFailed := true
        focusLost := err.HasOwnProp("focusLost") && err.focusLost
        S.setup.stage := "failed"
        S.setup.tested := false
        Log("setup_shortcut_failed candidate=" S.setup.index)
    } finally {
        ReleaseHeldKeys()
        S.busy := false
        S.setup.dialog.Busy(false)
        try {
            if S.held.keys.Length {
                MicInputFault(N("请手动按下并松开设置中的快捷键，再关闭并重新打开程序。",
                    "Press and release the configured shortcut manually, then close and reopen AirKey."))
            } else if trialFailed {
                if !focusLost
                    S.setup.index++
                PrepareMicTrial()
            }
        } finally Critical("Off")
    }
}

NextMicOutput(*) {
    global S
    if !MicSetupActive() || S.setup.stage != "confirming" || S.busy || S.held.keys.Length
        return
    Log("setup_user_result not_started candidate=" S.setup.index)
    S.setup.index++
    PrepareMicTrial()
}

ConfirmMicSetup(*) {
    global S, ConfigPath
    if !MicSetupActive() || S.setup.stage != "confirming" || !S.setup.tested || S.busy || S.held.keys.Length
        return
    try {
        chosen := S.devices[S.setup.candidates[S.setup.index]]
        currentDevices := S.native.Enumerate()
        if ProfileTopology(currentDevices) != ProfileTopology(S.devices)
            throw LocalError("连接已发生变化，请重新识别按钮。", "The connection changed. Please set up the button again.")
        chosenIndex := 0
        for index, device in currentDevices
            if device.id = chosen.id && device.hid = chosen.hid
                chosenIndex := index
        if !chosenIndex
            throw LocalError("连接已发生变化，请重新识别按钮。", "The connection changed. Please set up the button again.")
        profile := S.setup.profile
        profile.outputHid := chosen.hid
        profile.outputId := chosen.id
        profile.topology := ProfileTopology(currentDevices)
        profile.shortcut := S.binding.canonical
        ; Only the explicit "both normal" confirmation establishes this flag.
        profile.volumeVerified := true
        SaveMicProfile(ConfigPath, profile, S.machine)
        S.profile := profile
        S.savedHid := profile.outputHid
        S.devices := currentDevices
        S.selected := chosenIndex
        S.resume := true
        Log("setup_verified mode=" profile.source " candidate=" S.setup.index)
        if FinishMicSetup()
            EnableMapping()
    } catch as err {
        MicInputFault(N("设置没有保存：{1}", "Setup was not saved: {1}", ErrorText(err)), "save")
    }
}

MicSetupVolumeIssue(*) {
    global S
    if !MicSetupActive() || S.setup.stage != "confirming" || S.busy
        return
    S.setup.tested := false
    MicInputFault(N("音量仍在变化，本次设置没有保存。请点击重试重新识别；若仍出现此问题，请取消设置。",
        "The volume still changes, so this setup was not saved. Retry button detection; cancel setup if it still happens."), "volume_changed")
}

FinishMicSetup() {
    global S
    SetTimer(MicLearningTimeout, 0)
    if !MicSetupActive()
        return true
    stopped := true
    dialog := S.setup.dialog
    try {
        if IsObject(S.button)
            S.button.Stop()
    } catch {
        stopped := false
        S.notice := N("按钮监听未完全停止，请退出程序后重新打开。", "The button listener could not fully stop. Exit and reopen AirKey.")
        Log("button_stop_failed")
    } finally {
        ReleaseHeldKeys()
        S.settingUp := false
        S.setup := 0
        if IsObject(dialog)
            dialog.Close()
        UpdateUI()
    }
    return stopped && !S.held.keys.Length
}

CancelMicSetup(restore := true, *) {
    global S
    if !MicSetupActive() || S.busy
        return
    wasEnabled := S.setup.priorEnabled
    if !FinishMicSetup()
        return
    S.notice := N("设置已取消。完成按钮识别后即可启用。", "Setup cancelled. Finish button setup to enable voice input.")
    Log("setup_cancelled")
    if restore && wasEnabled && IsObject(S.profile)
        EnableMapping()
    UpdateUI()
}

; Recheck the intended text field before each key-down. Key-up cleanup must
; always be allowed, including after Doubao activates its recording popup.
class MicSetupOutput {
    __New(native, canSend) {
        this.native := native
        this.canSend := canSend
    }
    Send(device, code, state) {
        if !(state & 1) && !this.canSend.Call() {
            err := LocalError("请回到设置窗口的输入框，再按一次按钮。", "Return to the setup text box, then press the button again.")
            err.focusLost := true
            throw err
        }
        this.native.Send(device, code, state)
    }
}

MicInputFault(message, stage := "input") {
    global S, ConfigPath
    SetTimer(MicLearningTimeout, 0)
    if IsObject(S.button)
        try S.button.Stop()
    Log("button_input_fault stage=" stage)
    if MicSetupActive() {
        S.setup.stage := "failed"
        S.setup.tested := false
        S.setup.dialog.Failure(message, !S.held.keys.Length)
        return
    }
    StopMapping(true)
    S.profile := 0
    try InvalidateMicProfile(ConfigPath)
    S.notice := N("按钮接收已停止，请重新识别：{1}", "Button input stopped. Run button setup again: {1}", message)
    UpdateUI()
}
