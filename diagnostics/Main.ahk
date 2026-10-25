;@Ahk2Exe-SetName AirKey Diagnostics
;@Ahk2Exe-SetDescription Portable AirKey button-path diagnostics
;@Ahk2Exe-SetVersion 0.1.0.0
;@Ahk2Exe-SetOrigFilename AirKey-Diagnostics.exe
#Requires AutoHotkey v2.0 64-bit
#Warn All, StdOut
#SingleInstance Off
#NoTrayIcon
#Include shared\Localization.ahk
#Include shared\ModernControls.ahk
#Include shared\DriverManager.ahk
#Include shared\NativeOutput.ahk
#Include shared\ShortcutConfig.ahk
#Include shared\MachineProfile.ahk
#Include DiagnosticInput.ahk
#Include DiagnosticReport.ahk
#Include DiagnosticWire.ahk
#Include DiagnosticWorker.ahk

global Diagnostic := 0
try {
    if A_Args.Length && A_Args[1] = "--worker" {
        if A_Args.Length != 6
            ExitApp(2)
        Diagnostic := DiagnosticWorker(A_Args[2], A_Args[3], Integer(A_Args[4]), Integer(A_Args[5]), A_Args[6])
    } else if A_Args.Length = 2 && A_Args[1] = "--self-test" {
        ExtractDiagnosticAssets(A_Args[2])
        FileOpen(A_Args[2] "\component-check.txt", "w", "UTF-8").Write("AirKey Diagnostics 0.1.0`r`nPASS embedded DLL SHA256 and license extraction.`r`nNo input registration, key sends, driver changes or normal settings access.`r`n")
        ExitApp(0)
    } else if !A_Args.Length || (A_Args.Length = 1 && A_Args[1] = "--preview")
        Diagnostic := DiagnosticApp(A_Args.Length = 1)
    else
        ExitApp(2)
    Persistent()
} catch {
    if !A_Args.Length
        MsgBox("检测工具未能启动。请将 EXE 放到可写入的本地文件夹再试。", "AirKey 按钮检测", "Icon!")
    ExitApp(2)
}
class DiagnosticApp {
    __New(preview := false) {
        this.preview := preview, this.mode := "intro", this.closing := false, this.busy := false
        this.native := 0, this.worker := 0, this.latest := 0, this.reportPath := "", this.environment := 0
        this.phases := [], this.trials := [], this.devices := [], this.candidates := [], this.phaseIndex := 0
        this.held := {keys: []}, this.appMutex := 0, this.diagMutex := 0, this.stopRequested := false
        this.localData := EnvGet("LOCALAPPDATA")
        this.configPath := this.localData "\MicAirDoubao\settings.ini"
        this.binding := ParseShortcut("RAlt+Space")
        this.timer := ObjBindMethod(this, "Tick")
        this.exitCallback := ObjBindMethod(this, "Cleanup")
        this.sendTimer := ObjBindMethod(this, "SendTrial")
        this.phaseNames := ["baseline", "legacy", "registered", "hook"]
        this.phaseTitles := ["先看电脑收到什么", "重现旧版的按钮接收", "单独检查系统热键", "单独检查键盘监听"]
        if !preview {
            this.diagMutex := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 0, "Str", "Local\AirKey.Diagnostics.v1", "Ptr")
            if !this.diagMutex || A_LastError = 183
                throw Error("DUPLICATE")
        }
        this.window := Gui(, "AirKey 按钮检测")
        this.window.BackColor := "F8FAF9"
        this.window.SetFont("s11 c172E2A", "Microsoft YaHei UI")
        this.window.OnEvent("Close", ObjBindMethod(this, "Close"))
        this.window.OnEvent("Escape", ObjBindMethod(this, "Close"))
        this.window.SetFont("s11 bold c63776D")
        this.window.AddText("x30 y24 w330 h25", "AirKey  /  按钮检测")
        this.progress := this.window.AddText("x390 y26 w200 h24 Right", preview ? "界面预览 · 未检测" : "约 2–3 分钟")
        this.window.SetFont("s21 bold c172E2A")
        this.heading := this.window.AddText("x30 y70 w560 h42", "查清按钮卡在哪一步")
        this.window.SetFont("s11 norm c62766C")
        this.description := this.window.AddText("x32 y132 w556 h88", "连接 Mic Air 接收器，先退出 AirKey 和音量实验工具。`n检测会引导你按按钮，再在这里试用豆包语音。`n不安装驱动，不改动现有设置。")
        this.window.SetFont("s10 c198575")
        this.live := this.window.AddText("x32 y234 w556 h55", "为还原旧版行为，部分检测步骤可能改变音量。`n检测完成或关闭窗口后，所有临时监听都会退出。")
        this.window.SetFont("s11 c172E2A")
        this.input := this.window.AddEdit("x32 y299 w556 h94 Multi Hidden")
        this.window.SetFont("s9 c71827B")
        this.hint := this.window.AddText("x32 y405 w556 h45", "报告只保留检测结果，不包含账号、电脑名、完整硬件编号或打字内容。")
        this.window.SetFont("s11 bold")
        this.primary := ModernButton(this.window, "x30 y466 w560 h48", "开始检测")
        this.primary.OnEvent("Click", ObjBindMethod(this, "HandlePrimary"))
        this.window.SetFont("s10 norm")
        this.secondary := ModernButton(this.window, "x30 y524 w260 h34 Hidden", "重测此步", "secondary")
        this.secondary.OnEvent("Click", ObjBindMethod(this, "HandleSecondary"))
        this.other := ModernButton(this.window, "x310 y524 w280 h34 Hidden", "结束检测，保存报告", "ghost")
        this.other.OnEvent("Click", ObjBindMethod(this, "HandleOther"))
        this.primary.Enabled := !preview
        OnExit(this.exitCallback)
        this.window.Show("w620 h588")
    }

    HandlePrimary(*) {
        if this.busy || this.closing
            return
        switch this.mode {
            case "intro": this.Begin()
            case "listening": this.ConfirmPhase()
            case "phase_done": this.NextPhase()
            case "manual": this.ManualResult("success")
            case "output_ready": this.QueueTrial()
            case "output_result": this.RecordTrial("success")
            case "done":
                if this.reportSaved {
                    try Run('notepad.exe "' this.reportPath '"')
                } else
                    this.Finish()
        }
    }
    HandleSecondary(*) {
        if this.busy || this.closing
            return
        switch this.mode {
            case "phase_done": this.StartPhase()
            case "manual": this.ManualResult("failure")
            case "output_result": this.RecordTrial("failure")
            case "done": if this.reportSaved && this.reportPath != ""
                A_Clipboard := FileRead(this.reportPath, "UTF-8")
        }
    }
    HandleOther(*) {
        if this.busy || this.closing
            return
        if this.mode = "done"
            return this.Close()
        if this.worker {
            this.finishAfterWorker := true
            this.RequestWorkerStop(false)
        } else
            this.Finish()
    }
    Buttons(primary, secondary := "", other := "结束检测，保存报告") {
        this.primary.Text := primary, this.primary.Enabled := true
        this.secondary.Text := secondary, this.secondary.Visible := secondary != ""
        this.other.Text := other, this.other.Visible := other != ""
        for button in [this.primary, this.secondary, this.other]
            ModernRedraw(button)
    }
    Begin() {
        this.primary.Enabled := false
        try {
            this.appMutex := DllCall("Kernel32\CreateMutexW", "Ptr", 0, "Int", 0,
                "Str", "Local\MicAirDoubao.ControlPanel.v1", "Ptr")
            if !this.appMutex || A_LastError = 183 {
                this.ReleaseAppMutex()
                this.live.Text := "请先从托盘彻底退出 AirKey，再点击开始检测。"
                return
            }
            probeMutex := DllCall("Kernel32\OpenMutexW", "UInt", 0x100000, "Int", false,
                "Str", "Local\AirKey.VolumeGuard.Probe.v1", "Ptr")
            probeBusy := probeMutex || A_LastError = 5
            if probeMutex
                DllCall("Kernel32\CloseHandle", "Ptr", probeMutex)
            if probeBusy {
                this.ReleaseAppMutex()
                this.live.Text := "请先退出独立的音量实验工具，再开始检测。"
                return
            }
            this.mode := "preparing"
            this.description.Text := "正在读取与按钮有关的系统状态…"
            this.workDir := A_Temp "\AirKey-Diagnostic-" FormatTime(, "yyyyMMdd-HHmmss") "-" Random(100000, 999999)
            DirCreate(this.workDir)
            ExtractDiagnosticAssets(this.workDir)
            try this.binding := ParseShortcut(IniRead(this.configPath, "Mapping", "Shortcut", "RAlt+Space"))
            catch
                this.binding := ParseShortcut("RAlt+Space")
            driver := GetDriverStatus()
            if driver.known && driver.running {
                try {
                    this.native := NativeOutput(this.workDir "\interception.dll")
                    this.devices := this.native.Enumerate()
                }
            }
            this.environment := CollectDiagnosticEnvironment(this.configPath, this.devices, driver)
            this.PrepareCandidates()
            this.phaseIndex := 1
            this.SaveReport()
            this.StartPhase()
        } catch {
            this.mode := "intro"
            this.live.Text := "检测准备未完成。请确认 EXE 所在位置可写入，再重新打开工具。"
            this.ReleaseAppMutex()
        } finally {
            if this.mode = "intro"
                this.primary.Enabled := true
        }
    }
    Heartbeat() {
        deadline := (DllCall("Kernel32\GetTickCount", "UInt") + 2500) & 0xFFFFFFFF
        if !DllCall("User32\SetPropW", "Ptr", this.window.Hwnd, "Str", DiagnosticWorker.OwnerProperty, "Ptr", DllCall("Kernel32\GetCurrentProcessId", "UInt"), "Int")
            || !DllCall("User32\SetPropW", "Ptr", this.window.Hwnd, "Str", DiagnosticWorker.DeadlineProperty, "Ptr", deadline ? deadline : 1, "Int")
            throw Error("HEARTBEAT")
    }
    StartPhase() {
        if this.worker
            return ; Never overlap modes, including while a previous child exits.
        phase := this.phaseNames[this.phaseIndex]
        this.mode := "starting", this.stopRequested := false, this.confirmed := false, this.finishAfterWorker := false
        this.latest := 0, this.workerBorn := DiagNow(), this.input.Visible := false
        this.snapshotPath := this.workDir "\" phase "-" DiagNow() ".txt"
        this.progress.Text := "按钮接收  " this.phaseIndex " / 4"
        this.heading.Text := this.phaseTitles[this.phaseIndex]
        this.description.Text := "请只按 Mic Air 的按钮两次，每次间隔 3 秒。`n松开其他键盘按键。按完后点击下方继续，`n即使没有任何反应，也请如实继续。"
        this.live.Text := "正在开启这一轮检测…"
        this.hint.Text := "本步骤只接收按钮，不启动豆包；音量可能正常变化。"
        this.Buttons("正在准备…")
        this.primary.Enabled := false
        try {
            this.Heartbeat()
            executable := A_IsCompiled ? this.Quote(A_ScriptFullPath) : this.Quote(A_AhkPath) " " this.Quote(A_ScriptFullPath)
            command := executable " --worker " phase " " this.Quote(this.snapshotPath) " " this.window.Hwnd
                . " " DllCall("Kernel32\GetCurrentProcessId", "UInt") " " this.Quote(this.binding.keys[this.binding.keys.Length].ahkName)
            this.worker := DiagLaunchChild(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, command, A_ScriptDir)
            SetTimer(this.timer, 200)
        } catch {
            this.Disarm()
            this.mode := "phase_done"
            this.live.Text := "本步骤未能启动，不会记为按键失败。可以重测，或继续检查其他步骤。"
            this.Buttons("继续下一步", "重测此步")
        }
    }
    Tick(*) {
        if this.closing || !this.worker
            return
        try this.Heartbeat()
        catch
            this.RequestWorkerStop(false)
        try {
            snapshot := DiagReadSnapshot(this.snapshotPath, this.phaseNames[this.phaseIndex])
            if IsObject(snapshot)
                this.latest := snapshot
        }
        exited := DllCall("Kernel32\WaitForSingleObject", "Ptr", this.worker, "UInt", 0, "UInt") = 0
        if exited
            return this.WorkerEnded()
        elapsed := DiagNow() - this.workerBorn
        if this.mode = "starting" && IsObject(this.latest) && this.latest.started {
            this.mode := "listening"
            this.Buttons("已按两次，继续")
        }
        if this.mode = "listening" {
            this.primary.Enabled := elapsed >= 5500
            count := IsObject(this.latest) ? Max(this.latest.counts.rawKeyboardDown, this.latest.counts.hidDown,
                this.latest.counts.legacyHotkey, this.latest.counts.registeredHotkey, this.latest.counts.hookDown) : 0
            this.live.Text := "本轮已收到 " count " 个按钮按下事件。`n剩余 " Max(0, Ceil((40000 - elapsed) / 1000)) " 秒；请按两次后点击继续。"
        }
        if (this.stopRequested && DiagNow() - this.stopAt > 3000) || elapsed > 45000 {
            ; Only this app's retained input-only child handle; never by name/PID reuse.
            DllCall("Kernel32\TerminateProcess", "Ptr", this.worker, "UInt", 3, "Int")
            this.confirmed := false
        }
    }
    ConfirmPhase() {
        if this.mode != "listening" || DiagNow() - this.workerBorn < 5500
            return
        this.RequestWorkerStop(true)
    }
    RequestWorkerStop(confirmed) {
        if !this.worker || this.stopRequested
            return
        this.confirmed := confirmed, this.stopRequested := true, this.stopAt := DiagNow()
        this.mode := "stopping", this.primary.Enabled := false
        this.live.Text := "正在结束本轮检测，随后进入下一步…"
        try FileAppend("stop", this.snapshotPath ".stop", "UTF-8")
    }
    WorkerEnded() {
        SetTimer(this.timer, 0)
        DllCall("Kernel32\CloseHandle", "Ptr", this.worker)
        this.worker := 0
        this.Disarm()
        try {
            snapshot := DiagReadSnapshot(this.snapshotPath, this.phaseNames[this.phaseIndex])
            if IsObject(snapshot)
                this.latest := snapshot
        }
        if IsObject(this.latest) {
            this.latest.userConfirmedPresses := this.confirmed
            this.latest.workerExited := true
            this.latest.completed := this.latest.completed && this.confirmed && this.latest.cleanupOk
            this.phases.Push(this.latest)
        }
        this.SaveReport()
        if this.finishAfterWorker
            return this.Finish()
        if IsObject(this.latest) && this.latest.completed
            return this.NextPhase()
        this.mode := "phase_done"
        this.live.Text := "本轮未完成，已保存实际观察到的结果。`n不会把超时或未按按钮算成某种接收方式失效。"
        this.Buttons("继续下一步", "重测此步")
    }
    NextPhase() {
        if this.worker
            return
        this.phaseIndex++
        if this.phaseIndex <= 4
            this.StartPhase()
        else
            this.ShowManual()
    }
    PrepareCandidates() {
        oldIndex := FindDeviceSelection(this.devices, "")
        if oldIndex
            this.AddCandidate(this.devices[oldIndex], "legacy_first")
        matched := 0
        try {
            profile := {outputHid: IniRead(this.configPath, "Button", "OutputHardwareId", ""),
                outputId: Integer(IniRead(this.configPath, "Button", "OutputId", "0")),
                topology: IniRead(this.configPath, "Button", "Topology", "")}
            if profile.outputHid != ""
                matched := FindProfileOutput(this.devices, profile)
            else {
                savedHid := IniRead(this.configPath, "Mapping", "HardwareId", "")
                if savedHid != ""
                    matched := FindDeviceSelection(this.devices, savedHid)
            }
        }
        if matched
            this.AddCandidate(this.devices[matched], "matched")
        for device in this.devices {
            if device.id = 1
                this.AddCandidate(device, "legacy_slot1")
        }
        this.priorityCount := this.candidates.Length
        for device in this.devices
            this.AddCandidate(device, "alternate")
    }
    AddCandidate(device, role) {
        for candidate in this.candidates {
            if candidate.id = device.id {
                if role != "alternate"
                    candidate.roles.Push(role)
                return
            }
        }
        this.candidates.Push({id: device.id, hid: device.hid, roles: [role], index: this.candidates.Length + 1})
    }
    ShowManual() {
        this.mode := "manual"
        this.progress.Text := "语音试用  /  手动确认"
        this.heading.Text := "先确认豆包本身能启动"
        this.description.Text := "点击下面的输入框，手动按「" ShortcutDisplayLabel(this.binding) "」。`n确认豆包语音是否启动。若启动了，先结束这次录音，`n再选择下方结果。输入框内容不会保存。"
        this.live.Text := "这里使用 AirKey 当前保存的快捷键，不会修改豆包设置。"
        this.hint.Text := "后续试发也只使用这个输入框和同一组快捷键。"
        this.input.Visible := true
        this.Buttons("手动按键能启动豆包", "手动也没有启动", "跳过试发，生成报告")
        this.input.Focus()
    }
    ManualResult(result) {
        this.trials.Push({kind: "manual", sent: false, confirmed: result, candidateIndex: 0, errorCode: "NONE"})
        this.SaveReport()
        if result != "success" || !IsObject(this.native) || !this.candidates.Length
            return this.Finish()
        this.candidateIndex := 1, this.outputSuccess := false
        this.ShowCandidate()
    }
    ShowCandidate() {
        if this.candidateIndex > this.candidates.Length
            || (this.outputSuccess && this.candidateIndex > this.priorityCount)
            return this.Finish()
        this.mode := "output_ready", this.sent := false, this.sendError := "NONE"
        this.progress.Text := "语音试用  /  方式 " this.candidateIndex
        this.heading.Text := "检查快捷键能否到达豆包"
        this.description.Text := "点击「试发一次」后，请松开键盘按键。`n工具将在下方输入框发送一次「" ShortcutDisplayLabel(this.binding) "」。`n只需告诉工具豆包有没有启动。"
        this.live.Text := "会优先比较旧版自动选择的连接与当前保存的连接。"
        this.hint.Text := "不需要认识设备编号；测试结果不会修改 AirKey 的配置。"
        this.Buttons("试发一次", "", "跳过其余试发，生成报告")
    }
    QueueTrial() {
        this.mode := "output_sending", this.busy := true
        this.primary.Enabled := false, this.other.Enabled := false
        this.input.Focus()
        this.live.Text := "请松开键盘，保持光标在本窗口的输入框中…"
        SetTimer(this.sendTimer, -1200)
    }
    InputFocused() {
        return DllCall("User32\GetForegroundWindow", "Ptr") = this.window.Hwnd
            && DllCall("User32\GetFocus", "Ptr") = this.input.Hwnd
    }
    SendTrial(*) {
        if this.closing || this.mode != "output_sending"
            return
        this.sent := false, this.sendError := "NONE"
        Critical("On")
        try {
            if !this.InputFocused()
                throw Error("FOCUS_LOST")
            for key in ["LAlt", "RAlt", "LCtrl", "RCtrl", "LShift", "RShift", "LWin", "RWin", this.binding.keys[this.binding.keys.Length].ahkName] {
                if GetKeyState(key, "P") || (DllCall("User32\GetAsyncKeyState", "Int", GetKeyVK(key), "Short") & 0x8000)
                    throw Error("HELD_KEY")
            }
            if ProfileTopology(this.native.Enumerate()) != ProfileTopology(this.devices)
                throw Error("CONNECTION_CHANGED")
            guarded := DiagnosticGuardedOutput(this.native, ObjBindMethod(this, "InputFocused"))
            SendConfiguredShortcut(guarded, this.candidates[this.candidateIndex].id, this.binding, this.held)
            this.sent := true
        } catch as err {
            this.sendError := InStr("|FOCUS_LOST|HELD_KEY|CONNECTION_CHANGED|", "|" err.Message "|") ? err.Message : "SEND_FAILED"
        } finally {
            if IsObject(this.native) && !ReleaseConfiguredKeys(this.native, this.held)
                this.sendError := "RELEASE_FAILED"
            this.busy := false, this.other.Enabled := true
            Critical("Off")
        }
        if this.held.keys.Length {
            this.RecordTrial("untested")
            this.Finish()
            this.live.Text := "有按键未能释放。请手动按下并松开「" ShortcutDisplayLabel(this.binding) "」，然后关闭工具。"
            return
        }
        if !this.sent && (this.sendError = "FOCUS_LOST" || this.sendError = "HELD_KEY") {
            this.ShowCandidate()
            this.live.Text := "本次没有完成试发。请保持输入框焦点并松开键盘，再试一次。"
            return
        }
        this.mode := "output_result"
        this.description.Text := this.sent ? "快捷键已交给驱动，但这不代表豆包已启动。`n请确认实际效果。若已开始录音，先结束录音，`n再选择下方结果。" : "这次试发未完成。请选择没有启动，继续检查其他连接。"
        this.live.Text := this.sent ? "豆包语音是否启动？" : "已记录发送失败，原始异常文本不会进入报告。"
        this.Buttons("豆包已启动", "豆包没有启动", "结束试发，生成报告")
        this.primary.Enabled := this.sent
    }
    RecordTrial(result) {
        candidate := this.candidates[this.candidateIndex]
        for role in candidate.roles
            this.trials.Push({kind: role, candidateIndex: candidate.index, sent: this.sent,
                confirmed: result, errorCode: this.sendError})
        if this.sent && result = "success"
            this.outputSuccess := true
        this.SaveReport()
        this.candidateIndex++
        this.ShowCandidate()
    }
    SaveReport() {
        if !IsObject(this.environment)
            return false
        try {
            if this.reportPath = "" {
                folder := A_ScriptDir "\AirKey-Reports"
                try DirCreate(folder)
                catch {
                    folder := this.localData "\AirKeyDiagnostics\Reports"
                    DirCreate(folder)
                }
                this.reportPath := folder "\AirKey-检测报告-" FormatTime(, "yyyyMMdd-HHmmss") "-" Random(1000, 9999) ".txt"
            }
            report := BuildDiagnosticReport(this.environment, this.phases, this.trials)
            report .= "`r`n本次试发快捷键：" this.binding.canonical "`r`n"
            report .= "`r`n按钮事件时序（相对毫秒；只含音量＋相关事件）`r`n"
            for phase in this.phases {
                report .= "[" phase.phaseId "]`r`n"
                for event in phase.events
                    report .= event.ms " ms  " event.source "  down=" event.down "  flags=" event.flags "`r`n"
            }
            try {
                reportFile := FileOpen(this.reportPath, "w", "UTF-8")
                reportFile.Write(report), reportFile.Close()
            } catch {
                fallbackFolder := this.localData "\AirKeyDiagnostics\Reports"
                DirCreate(fallbackFolder)
                fallbackPath := fallbackFolder "\AirKey-检测报告-" FormatTime(, "yyyyMMdd-HHmmss") "-" Random(1000, 9999) ".txt"
                reportFile := FileOpen(fallbackPath, "w", "UTF-8")
                reportFile.Write(report), reportFile.Close()
                this.reportPath := fallbackPath
            }
            return true
        } catch {
            this.live.Text := "报告写入失败。请将工具移到可写入的本地文件夹再试。"
            return false
        }
    }
    Finish() {
        if this.worker || this.busy
            return
        this.mode := "done"
        SetTimer(this.timer, 0)
        this.Disarm(), this.ReleaseAppMutex()
        this.reportSaved := this.SaveReport()
        this.progress.Text := "检测已结束"
        this.heading.Text := this.reportSaved ? "报告已准备好" : "报告暂时没有保存"
        this.description.Text := "请把生成的 TXT 报告发回来。`n报告会区分已确认的事实、没有观察到的事件，`n以及仍需验证的原因，不会把猜测当作结论。"
        this.live.Text := "临时监听已退出，现在可以重新打开 AirKey。"
        this.input.Visible := false
        this.hint.Text := this.reportPath
        this.Buttons(this.reportSaved ? "打开检测报告" : "重试保存报告", this.reportSaved ? "复制报告内容" : "", "关闭")
    }
    Quote(value) {
        if InStr(value, '"') || InStr(value, "`r") || InStr(value, "`n")
            throw Error("INVALID_ARGUMENT")
        return '"' value '"'
    }
    Disarm() => DllCall("User32\RemovePropW", "Ptr", this.window.Hwnd, "Str", DiagnosticWorker.DeadlineProperty, "Ptr")
    ReleaseAppMutex() {
        if this.appMutex {
            DllCall("Kernel32\CloseHandle", "Ptr", this.appMutex)
            this.appMutex := 0
        }
    }
    Close(*) {
        if this.busy && this.mode != "output_sending"
            return
        this.Cleanup()
        ExitApp()
    }
    Cleanup(*) {
        if this.closing
            return
        this.closing := true
        SetTimer(this.timer, 0), SetTimer(this.sendTimer, 0)
        this.Disarm()
        if this.worker {
            try FileAppend("stop", this.snapshotPath ".stop", "UTF-8")
            exited := DllCall("Kernel32\WaitForSingleObject", "Ptr", this.worker, "UInt", 1200, "UInt") = 0
            if !exited {
                DllCall("Kernel32\TerminateProcess", "Ptr", this.worker, "UInt", 3, "Int")
                exited := DllCall("Kernel32\WaitForSingleObject", "Ptr", this.worker, "UInt", 2000, "UInt") = 0
            }
            try {
                snapshot := DiagReadSnapshot(this.snapshotPath, this.phaseNames[this.phaseIndex])
                if IsObject(snapshot) {
                    snapshot.userConfirmedPresses := false, snapshot.completed := false
                    snapshot.workerExited := exited, snapshot.workerEndReason := "cancelled"
                    this.phases.Push(snapshot)
                }
            }
            DllCall("Kernel32\CloseHandle", "Ptr", this.worker)
            this.worker := 0
        }
        if IsObject(this.native) {
            try ReleaseConfiguredKeys(this.native, this.held)
            this.native.Close()
        }
        this.SaveReport(), this.ReleaseAppMutex()
        if this.diagMutex
            DllCall("Kernel32\CloseHandle", "Ptr", this.diagMutex)
    }
}

ExtractDiagnosticAssets(directory) {
    if !RegExMatch(directory, "i)^[A-Z]:\\") || InStr(directory, '"')
        throw Error("INVALID_DIRECTORY")
    DirCreate(directory)
    DirCreate(directory "\licenses")
    FileInstall "assets\interception.dll", directory "\interception.dll", 1
    FileInstall "LICENSE", directory "\licenses\Project-MIT.txt", 1
    FileInstall "THIRD_PARTY_NOTICES.md", directory "\licenses\THIRD_PARTY_NOTICES.md", 1
    FileInstall "assets\AutoHotkey-license.txt", directory "\licenses\AutoHotkey-license.txt", 1
    FileInstall "assets\LGPL-3.0.txt", directory "\licenses\LGPL-3.0.txt", 1
    FileInstall "assets\GPL-3.0.txt", directory "\licenses\GPL-3.0.txt", 1
    if SHA256File(directory "\interception.dll") != "AB88164C11B1B48488772D4C3BFAA4509D5B0AE9DBC5A691DC4F96F0260443C8"
        throw Error("COMPONENT_HASH")
}
