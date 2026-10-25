#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Warn All, StdOut
; Extract real controller/worker definitions, replacing only OS/action seams.
; The generated child is a mock test process, never a diagnostic input worker.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\controller"
DirCreate(testDir)
try {
    root := A_ScriptDir "\.."
    main := FileRead(root "\Main.ahk", "UTF-8")
    start := InStr(main, "class DiagnosticApp {")
    if !start
        throw Error("Main controller extraction boundary changed")
    definitions := SubStr(main, start) "`r`n" FileRead(root "\DiagnosticWorker.ahk", "UTF-8")
    for name in ["DllCall", "SetTimer", "Run", "ExitApp", "Critical", "GetKeyState", "DiagNow", "FileExist", "FileAppend", "DiagReadSnapshot", "DiagWriteSnapshot", "ProfileTopology", "DiagLaunchChild"]
        definitions := RegExReplace(definitions, "\b" name "\(", "Controller" name "(")
    prefix := "#Requires AutoHotkey v2.0 64-bit`r`n#SingleInstance Off`r`n#NoTrayIcon`r`n#Warn All, StdOut`r`n"
    for name in ["Localization", "ModernControls", "DriverManager", "NativeOutput", "ShortcutConfig", "MachineProfile"] {
        module := RegExReplace(FileRead(root "\shared\" name ".ahk", "UTF-8"), "m)^#Include[^\r\n]*\r?$", "")
        if name = "ShortcutConfig"
            module := RegExReplace(module, "\bSleep\(", "ControllerSleep(")
        definitions .= "`r`n" module
    }
    for name in ["DiagnosticInput", "DiagnosticReport", "DiagnosticWire"]
        definitions .= "`r`n" FileRead(root "\" name ".ahk", "UTF-8")
    own := FileRead(A_ScriptFullPath, "UTF-8")
    marker := "; BEGIN" " CONTROLLER HARNESS"
    body := RegExReplace(SubStr(own, InStr(own, marker) + StrLen(marker)), "\*/\s*$", "")
    worker := testDir "\mock-controller.ahk"
    FileOpen(worker, "w", "UTF-8").Write(prefix definitions "`r`n" body)
    code := RunWait('"' A_AhkPath '" /ErrorStdOut=UTF-8 "' worker '"', root, "Hide")
    ExitApp(code)
} catch as err {
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write("FAIL launcher: " err.Message "`r`n" err.Stack)
    ExitApp(2)
}

/*
; BEGIN CONTROLLER HARNESS
global CT := {}
controllerReport := "Controller mocks: no GUI, hooks, process launch, native key sends, audio, or driver changes.`r`n"
try {
    for test in [
        ["Parent identity and heartbeat expiration", TestParentIdentity],
        ["Worker timeout, cancellation and parent loss", TestWorkerBoundaries],
        ["Cleanup before final snapshot and truthful completion", TestWorkerFinish],
        ["Next phase waits for exit and requires confirmation", TestParentCompletion],
        ["Cancellation reaps child and cannot claim completion", TestParentCleanup],
        ["Report write failure remains visible", TestFinishFailure],
        ["Output focus, held keys and connection guard", TestOutputGuards],
        ["Focus lost mid-shortcut still releases keys", TestOutputFocusLoss],
        ["Successful send still awaits user result", TestOutputConfirmation]
    ] {
        CTReset()
        test[2].Call()
        controllerReport .= "PASS " test[1] ".`r`n"
    }
    FileOpen(A_ScriptDir "\report.txt", "w", "UTF-8").Write(controllerReport)
    ExitApp(0)
} catch as err {
    FileOpen(A_ScriptDir "\report.txt", "w", "UTF-8").Write(controllerReport "FAIL " err.Message "`r`n" err.Stack)
    ExitApp(1)
}

CTReset() {
    global CT
    CT := {calls: [], now: 10000, window: true, pid: 42, marked: 42, deadline: 12000,
        stop: false, keyHeld: false, writeFails: false, snapshot: 0, written: 0, exit: -1, waits: [0], terminated: 0}
}
CTCheck(condition, message) {
    if !condition
        throw Error(message)
}
ControllerDllCall(api, args*) {
    global CT
    CT.calls.Push(api)
    switch api {
        case "User32\IsWindow": return CT.window
        case "User32\GetWindowThreadProcessId":
            ControllerAssignRef(args[4], CT.pid)
            return 1
        case "User32\GetPropW": return args[4] = DiagnosticWorker.OwnerProperty ? CT.marked : CT.deadline
        case "Kernel32\GetTickCount": return CT.now
        case "Kernel32\GetCurrentProcessId": return 42
        case "Kernel32\CloseHandle", "User32\RemovePropW": return 1
        case "Kernel32\WaitForSingleObject": return CT.waits.Length ? CT.waits.RemoveAt(1) : 0
        case "Kernel32\TerminateProcess": return ++CT.terminated
        case "User32\GetAsyncKeyState": return CT.keyHeld ? 0x8000 : 0
        default: throw Error("Unexpected OS call blocked: " api)
    }
}
ControllerAssignRef(&target, value) => target := value
ControllerSetTimer(*) => 0
ControllerCritical(*) => 0
ControllerSleep(*) => 0
ControllerGetKeyState(*) {
    global CT
    return CT.keyHeld
}
ControllerDiagNow() {
    global CT
    return CT.now
}
ControllerFileExist(*) {
    global CT
    return CT.stop
}
ControllerFileAppend(*) => 0
ControllerDiagLaunchChild(*) => ControllerRun()
ControllerRun(*) {
    throw Error("Process launch blocked by controller test")
}
ControllerExitApp(code := 0) {
    global CT
    CT.exit := code
}
ControllerDiagReadSnapshot(*) {
    global CT
    return CT.snapshot
}
ControllerDiagWriteSnapshot(path, snapshot, reason := "running", cleanupOk := false) {
    global CT
    if CT.writeFails
        throw Error("TEST_WRITE_FAILED")
    CT.written := {snapshot: snapshot, reason: reason, cleanupOk: cleanupOk}
}
ControllerProfileTopology(devices) => devices.Length ? devices[1].hid : ""

class ControllerInput {
    __New() {
        this.stops := 0, this.stopFails := false, this.snapshotCalls := []
    }
    Stop() {
        this.stops++
        if this.stopFails
            throw Error("TEST_STOP_FAILED")
    }
    Snapshot() {
        this.snapshotCalls.Push(this.stops)
        return {phaseId: "legacy", active: true, completed: false, errors: this.stopFails ? [{code: "CLEANUP_FAILED"}] : []}
    }
}
class ControllerWorker extends DiagnosticWorker {
    __New() {
        this.parentWindow := 10, this.parentPid := 42, this.phase := "legacy", this.path := "mock"
        this.ending := false, this.born := 0, this.timer := (*) => 0
        this.input := ControllerInput(), this.reason := ""
    }
    Finish(reason) => this.reason := reason
}
class ControllerFinishingWorker extends ControllerWorker {
    Finish(reason) => DiagnosticWorker.Prototype.Finish.Call(this, reason)
}
class ControllerNative {
    __New(owner) {
        this.owner := owner, this.events := [], this.devices := [{id: 2, hid: "fixture"}]
        this.failAt := 0, this.loseAt := 0, this.closed := false
    }
    Close() => this.closed := true
    Enumerate() => this.devices
    Send(device, code, state) {
        this.events.Push({device: device, code: code, state: state})
        if this.loseAt = this.events.Length
            this.owner.focused := false
        if this.failAt = this.events.Length
            throw Error("TEST_SEND_FAILED")
    }
    Sequence() {
        result := ""
        for event in this.events
            result .= (result = "" ? "" : ",") Format("{:X}:{}", event.code, event.state)
        return result
    }
}
class ControllerApp extends DiagnosticApp {
    __New() {
        this.worker := 0, this.closing := false, this.busy := true, this.mode := "output_sending"
        this.phaseNames := ["baseline", "legacy", "registered", "hook"], this.phaseIndex := 1
        this.timer := (*) => 0, this.sendTimer := (*) => 0, this.confirmed := false
        this.window := {Hwnd: 10}, this.snapshotPath := "mock", this.latest := 0
        this.phases := [], this.trials := [], this.finishAfterWorker := false
        this.started := 0, this.manual := 0, this.finished := 0, this.saved := 0, this.retries := 0
        this.binding := ParseShortcut("RAlt+Space"), this.held := {keys: []}, this.focused := true
        this.native := ControllerNative(this), this.devices := [{id: 2, hid: "fixture"}]
        this.candidates := [{id: 2, index: 1, roles: ["legacy_first"]}], this.candidateIndex := 1
        this.outputSuccess := false, this.priorityCount := 1
        this.appMutex := 0, this.diagMutex := 0, this.reportPath := "mock", this.saveOk := true
        for name in ["primary", "secondary", "other", "description", "live", "hint", "input", "heading", "progress"]
            this.%name% := {Enabled: true, Visible: true, Text: ""}
    }
    StartPhase() => this.started++
    ShowManual() => this.manual++
    SaveReport() {
        this.saved++
        return this.saveOk
    }
    Disarm() => 0
    Buttons(*) => 0
    InputFocused() => this.focused
    ShowCandidate() => this.retries++
    Finish() => this.finished++
}

TestParentIdentity() {
    global CT
    worker := ControllerWorker()
    CTCheck(worker.ParentAlive(), "Matching PID, window and fresh deadline")
    CT.pid := 43
    CTCheck(!worker.ParentAlive(), "PID mismatch must reject recycled window")
    CT.pid := 42, CT.marked := 0
    CTCheck(!worker.ParentAlive(), "Missing owner marker must reject")
    CT.marked := 42, CT.deadline := CT.now
    CTCheck(!worker.ParentAlive(), "Expired deadline must reject")
    CT.deadline := CT.now + 3001
    CTCheck(!worker.ParentAlive(), "Invalid future deadline must reject")
    CTCheck(DiagDeadlineFresh(700, 0xFFFFFF00), "Heartbeat safely crosses tick wrap")
}
TestWorkerBoundaries() {
    global CT
    worker := ControllerWorker()
    CT.window := false
    worker.Tick()
    CTCheck(worker.reason = "parent_lost", "Parent disappearance stops worker")
    CT.window := true, CT.stop := true
    worker.reason := "", worker.Tick()
    CTCheck(worker.reason = "confirmed", "Stop request is processed before timeout")
    CT.stop := false, CT.now := 50000, CT.deadline := 52000
    worker.reason := "", worker.Tick()
    CTCheck(worker.reason = "timeout", "Unconfirmed 40-second expiry is timeout")
    CT.now := 10000, CT.deadline := 12000, CT.writeFails := true
    worker.reason := "", worker.Tick()
    CTCheck(worker.reason = "report_failed", "Snapshot failure stops collection")
    worker.ending := true, worker.reason := "", worker.Tick()
    CTCheck(worker.reason = "", "Already ending worker cannot restart work")
}
TestWorkerFinish() {
    global CT
    worker := ControllerFinishingWorker()
    worker.Finish("confirmed")
    CTCheck(worker.input.stops = 1 && worker.input.snapshotCalls[1] = 1, "Final snapshot follows cleanup")
    CTCheck(CT.written.cleanupOk && CT.written.snapshot.completed && CT.exit = 0, "Clean confirmed completion")
    worker.Finish("confirmed")
    CTCheck(worker.input.stops = 1, "Finish is idempotent")
    worker := ControllerFinishingWorker(), worker.input.stopFails := true
    worker.Finish("confirmed")
    CTCheck(!CT.written.cleanupOk && !CT.written.snapshot.completed && CT.exit = 2, "Cleanup failure is never completed")
    CTCheck(CT.written.snapshot.errors.Length = 1, "Final snapshot includes cleanup error")
    worker := ControllerFinishingWorker(), worker.Finish("timeout")
    CTCheck(!CT.written.snapshot.completed, "Timeout is never a completed press test")
}
TestParentCompletion() {
    global CT
    app := ControllerApp(), app.worker := 99
    app.NextPhase()
    CTCheck(app.phaseIndex = 1 && !app.started, "Live child prevents next phase")
    for state in [[false, true, false], [true, false, false], [true, true, true]] {
        app := ControllerApp(), app.worker := 99, app.confirmed := state[1]
        CT.snapshot := {completed: true, cleanupOk: state[2]}
        app.WorkerEnded()
        CTCheck(!app.worker && app.phases.Length = 1 && app.phases[1].workerExited, "Exit retained in report")
        CTCheck(!!app.phases[1].completed = state[3], "User confirmation and cleanup both required")
        CTCheck(!!app.started = state[3], "Only completed phase advances automatically")
    }
    app := ControllerApp(), app.worker := 99, app.finishAfterWorker := true
    CT.snapshot := {completed: true, cleanupOk: true}
    app.WorkerEnded()
    CTCheck(app.finished = 1 && !app.started, "Finish-after-worker cancels future phases")
}
TestParentCleanup() {
    global CT
    for exits in [[0], [258, 0], [258, 258]] {
        app := ControllerApp(), app.worker := 99
        CT.waits := exits.Clone(), CT.terminated := 0
        CT.snapshot := {completed: true, cleanupOk: true}
        app.Cleanup()
        CTCheck(app.closing && !app.worker && app.native.closed, "Close must release child handle and native interface")
        CTCheck(app.phases.Length = 1 && !app.phases[1].completed && !app.phases[1].userConfirmedPresses, "Cancellation remains incomplete despite a prior success snapshot")
        CTCheck(app.phases[1].workerExited = (exits[exits.Length] = 0), "Unconfirmed process exit must not be reported as complete")
        CTCheck(app.phases[1].workerEndReason = "cancelled", "User close recorded as cancellation")
        CTCheck(CT.terminated = (exits.Length = 2), "Terminate only after graceful wait times out")
        CTCheck(app.saved = 1, "Cancelled sample saved")
        app.Cleanup()
        CTCheck(app.saved = 1, "Repeated cleanup remains idempotent")
    }
}
TestFinishFailure() {
    app := ControllerApp(), app.busy := false, app.saveOk := false
    DiagnosticApp.Prototype.Finish.Call(app)
    CTCheck(!app.reportSaved && app.heading.Text = "报告暂时没有保存", "Failed report write cannot be presented as ready")
}
TestOutputGuards() {
    global CT
    app := ControllerApp(), app.focused := false
    app.SendTrial()
    CTCheck(!app.native.events.Length && app.retries = 1, "Unfocused output must not send")
    app := ControllerApp(), CT.keyHeld := true
    app.SendTrial()
    CTCheck(!app.native.events.Length && app.retries = 1, "Physically held keys prevent sending")
    CT.keyHeld := false, app := ControllerApp(), app.native.devices := [{id: 2, hid: "changed"}]
    app.SendTrial()
    CTCheck(!app.native.events.Length && app.sendError = "CONNECTION_CHANGED", "Changed output topology prevents sending")
    CTCheck(!app.primary.Enabled && !app.trials.Length, "Failed send cannot be confirmed as successful")
}
TestOutputFocusLoss() {
    app := ControllerApp(), app.native.loseAt := 1
    app.SendTrial()
    CTCheck(app.native.Sequence() = "38:2,39:1,38:3", "Focus loss blocks next down while always allowing releases")
    CTCheck(!app.held.keys.Length && !app.sent && app.retries = 1, "Focus-lost attempt releases keys and retries same candidate")
    CTCheck(!app.trials.Length && app.candidateIndex = 1, "Incomplete attempt cannot select next candidate")
    app := ControllerApp(), app.native.failAt := 2
    app.SendTrial()
    CTCheck(app.native.Sequence() = "38:2,39:0,39:1,38:3", "Failed down retains cleanup responsibility")
    CTCheck(!app.held.keys.Length && app.sendError = "SEND_FAILED", "Failed native output releases all keys")
}
TestOutputConfirmation() {
    app := ControllerApp()
    app.SendTrial()
    CTCheck(app.native.Sequence() = "38:2,39:0,39:1,38:3", "Actual default shortcut sequence")
    CTCheck(app.sent && app.mode = "output_result" && !app.trials.Length, "Driver send is not a voice success result")
    app.RecordTrial("failure")
    CTCheck(app.trials.Length = 1 && app.trials[1].confirmed = "failure" && !app.outputSuccess, "User result controls success")
}

*/
