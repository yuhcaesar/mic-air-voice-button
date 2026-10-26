#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include %A_ScriptDir%\..\MachineProfile.ahk
#Include %A_ScriptDir%\..\ShortcutConfig.ahk
#Include %A_ScriptDir%\..\MicSetupController.ahk
; Actual controller, actual sender and actual profile persistence. UI, input
; listener and output are in-memory fakes; no real GUI, hook or driver is loaded.
global DataDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\mic-controller"
DirCreate(DataDir)
global ConfigPath := DataDir "\controller.ini"
global S := 0, UI := Map("window", {}), Logs := [], EnableRequests := 0
global Report := "Mic setup controller tests — mock input/output/UI only.`r`n", Skipped := 0
try {
    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    Check(S.settingUp && S.setup.stage = "learning" && S.button.learning, "Learning starts without output")
    ConfirmMicSetup()
    Check(FileRead(ConfigPath) = original && S.native.events.Length = 0, "Undetected button cannot save")
    DetectButton()
    ConfirmMicSetup()
    Check(!S.setup.tested && FileRead(ConfigPath) = original, "Detected button without actual trial cannot save")
    Check(!S.setup.profile.HasOwnProp("volumeVerified") || !S.setup.profile.volumeVerified,
        "Detection alone never claims volume confirmation")
    S.setup.dialog.focused := false
    S.setup.notBefore := 0
    MicSetupPress()
    Check(S.native.events.Length = 0 && S.setup.dialog.focusRequests = 1
        && !S.setup.tested, "Focus guard only focuses test input")
    listener := S.button
    Check(listener.guardActive, "Detected trial starts the fake volume guard")
    CancelMicSetup()
    Check(!listener.guardActive && !listener.running, "Cancelling an unconfirmed trial stops its guard")
    Pass("learning/detection alone cannot save; unfocused trial cannot send")

    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    DetectButton()
    S.setup.dialog.loseFocusOnCheck := 3 ; Initial guard, RAlt down, then Space down.
    if Trial("focus lost during shortcut", false) {
        Check(S.native.Sequence() = "2:56:2,2:57:1,2:56:3",
            "Focus loss blocks next down but permits all cleanup key-ups")
        Check(S.held.keys.Length = 0 && !S.busy && !A_IsCritical,
            "Focus loss releases keys and exits busy/critical state")
        Check(S.setup.index = 1 && S.setup.stage = "ready" && !S.setup.tested,
            "Focus loss retries the same candidate without confirmation")
        ConfirmMicSetup()
        Check(FileRead(ConfigPath) = original, "Interrupted trial cannot save")
        Pass("mid-shortcut focus loss blocks new presses, releases keys and retains the candidate")
    }
    CancelMicSetup(false)

    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("confirmed output") {
        Check(S.setup.stage = "confirming" && S.setup.tested && FileRead(ConfigPath) = original, "Actual trial still requires explicit confirmation")
        Check(!S.setup.profile.HasOwnProp("volumeVerified") || !S.setup.profile.volumeVerified,
            "A delivered shortcut does not imply unchanged system volume")
        ConfirmMicSetup()
        saved := LoadMicProfile(ConfigPath, S.machine)
        Check(IsObject(saved) && saved.outputHid = "ACPI\TEST_A" && saved.shortcut = "RAlt+Space"
            && saved.volumeVerified, "Explicit joint confirmation saves tested output and volume result")
        Check(!S.settingUp && EnableRequests = 1 && S.button.stops >= 2 && !S.button.guardActive,
            "Successful completion cleans listener/guard before requesting enable")
        Pass("only explicit confirmation after actual mock trial commits profile")
    } else
        CancelMicSetup(false)

    ResetCase(true)
    original := FileRead(ConfigPath)
    oldProfile := S.profile
    BeginMicSetupMode("compatibility")
    DetectButton()
    MicSetupVolumeIssue()
    Check(S.setup.stage = "ready" && S.button.guardActive,
        "Volume-result action cannot run before an actual trial")
    if Trial("voice works but volume changes") {
        MicSetupVolumeIssue()
        Check(S.setup.stage = "failed" && !S.setup.tested && !S.button.running && !S.button.guardActive,
            "Reported volume change stops the trial listener and guard")
        ConfirmMicSetup()
        Check(FileRead(ConfigPath) = original && S.profile = oldProfile && EnableRequests = 0,
            "A voice-only success cannot overwrite prior verified settings or enable")
        Check(!S.setup.profile.HasOwnProp("volumeVerified") || !S.setup.profile.volumeVerified,
            "Failed volume result never becomes joint confirmation")
        Pass("volume-change result refuses save and enable, preserves prior settings and stops input/guard")
    }
    CancelMicSetup(false)

    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("next output") {
        NextMicOutput()
        Check(S.setup.index = 2 && S.setup.stage = "failed" && !S.setup.tested
            && S.setup.retryOutput && !S.button.guardActive, "No stops input and offers retry or explicit mode switch")
        ConfirmMicSetup()
        Check(FileRead(ConfigPath) = original, "No does not save and next candidate needs its own trial")
        RetryMicSetup()
        Check(S.setup.index = 2 && S.setup.stage = "ready", "Retry continues the next output without relearning")
        if Trial("all outputs exhausted") {
            NextMicOutput()
            Check(S.setup.stage = "failed" && FileRead(ConfigPath) = original, "Exhausted outputs show failure without saving")
            Check(S.native.events[1].device = 2 && S.native.events[5].device = 4, "Each candidate actually tried once")
            Pass("No advances through every candidate, with no implicit success or save")
        }
    }
    CancelMicSetup(false)

    ResetCase(true)
    oldProfile := S.profile
    original := FileRead(ConfigPath)
    S.native.devices := [S.native.devices[2], S.native.devices[1]]
    BeginMicSetupMode("compatibility")
    dialog := S.setup.dialog
    button := S.button
    CancelMicSetup()
    Check(!S.settingUp && dialog.closed && button.stops = 1 && !button.guardActive, "Cancellation closes dialog/listener and disarms guard")
    Check(S.profile = oldProfile && FileRead(ConfigPath) = original && EnableRequests = 1, "Cancellation preserves prior profile and restores enabled request")
    Check(FindProfileOutput(S.devices, S.profile) = 2, "Retained profile resolves correctly after enumeration reordering")
    Pass("cancel preserves old profile/configuration, cleans listener/window and retains resolvable output after reordering")

    ResetCase(true)
    original := FileRead(ConfigPath)
    oldProfile := S.profile
    BeginMicSetupMode("compatibility")
    dialog := S.setup.dialog
    S.button.failStop := true
    S.held.keys := [{device: 2, code: 56, stateUp: 3, name: "RAlt"}]
    CancelMicSetup()
    Check(!S.settingUp && !S.enabled && dialog.closed && S.held.keys.Length = 0,
        "Listener stop exception still releases keys and closes dialog")
    Check(!S.button.guardActive, "Stop failure leaves the mock guard disarmed")
    Check(EnableRequests = 0 && S.profile = oldProfile && FileRead(ConfigPath) = original,
        "Failed cancellation cleanup cannot restore enabled mapping or alter profile")
    Check(InStr(Text(S.notice), "监听未完全停止"), "Cancellation preserves cleanup error notice")
    Pass("listener Stop exception during cancellation still cleans up and preserves paused/error state")

    ResetCase()
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("confirmed setup cleanup failure") {
        dialog := S.setup.dialog
        S.button.failStop := true
        ConfirmMicSetup()
        Check(!S.settingUp && dialog.closed && !S.enabled && EnableRequests = 0,
            "Confirmed setup with cleanup failure closes dialog but never enables")
        Check(IsObject(LoadMicProfile(ConfigPath, S.machine)), "Explicitly confirmed profile remains saved")
        Check(InStr(Text(S.notice), "监听未完全停止"), "Confirmation preserves cleanup error notice")
        Pass("confirmation only enables after successful listener cleanup")
    } else
        CancelMicSetup(false)

    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    MicLearningTimeout()
    Check(S.setup.stage = "failed" && !S.button.learning && !S.button.guardActive
        && FileRead(ConfigPath) = original, "Timeout stops detection/guard without saving")
    ConfirmMicSetup()
    Check(FileRead(ConfigPath) = original, "Timed-out setup cannot confirm")
    CancelMicSetup(false)
    Pass("timeout stops listener and never saves or confirms")

    ResetCase()
    S.native.failAt := 2
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("send failure", false) {
        Check(S.held.keys.Length = 0 && !S.busy && !S.setup.tested, "Failed trial releases attempted keys")
        Check(S.native.Sequence() = "2:56:2,2:57:0,2:57:1,2:56:3", "Failure cleanup exact reverse key-up sequence")
        Check(S.setup.index = 2 && S.setup.stage = "failed" && S.setup.retryOutput
            && !S.button.guardActive && FileRead(ConfigPath) = original, "Failed send pauses with next output available and never saves")
        ConfirmMicSetup()
        Check(FileRead(ConfigPath) = original, "Failed send cannot be confirmed")
        Pass("failed sends release attempted keys, advance candidate and do not save")
    }
    CancelMicSetup(false)

    ResetCase()
    S.native.failAt := 2
    S.native.failReleases := true
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("persistent release failure", false) {
        Check(S.held.keys.Length > 0 && S.setup.stage = "failed" && !S.setup.dialog.canRetry,
            "Unreleased keys block retry and retain recovery state")
        Check(!S.button.guardActive && !S.button.running,
            "Unreleased-key fault stops the listener and guard")
        attempts := S.native.events.Length
        StartMicLearning()
        ConfirmMicSetup()
        Check(S.native.events.Length = attempts && FileRead(ConfigPath) = original,
            "Unreleased keys prevent new learning and saving")
        S.native.failReleases := false
        ReleaseHeldKeys()
        Check(S.held.keys.Length = 0, "Retained releases can be retried safely")
        Pass("persistent release failures retain keys, disable retry and prevent persistence")
    }
    CancelMicSetup(false)

    ResetCase(true)
    original := FileRead(ConfigPath)
    oldProfile := S.profile
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("save failure") {
        lock := DllCall("Kernel32\CreateFileW", "Str", ConfigPath, "UInt", 0x80000000,
            "UInt", 1, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
        Check(lock != -1, "Lock temporary configuration")
        try ConfirmMicSetup()
        finally DllCall("Kernel32\CloseHandle", "Ptr", lock)
        Check(S.settingUp && S.setup.stage = "failed" && S.profile = oldProfile,
            "Save failure leaves prior in-memory profile")
        Check(FileRead(ConfigPath) = original && EnableRequests = 0, "Save failure retains disk profile without enabling")
        Pass("atomic-save failure retains prior disk/memory profile and never enables")
    }
    CancelMicSetup(false)

    ResetCase()
    S.native.devices := [{id: 2, hid: "HID\DUPLICATE"}, {id: 4, hid: "HID\DUPLICATE"}]
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("duplicate topology changes") {
        ; The chosen id/HID still exists: only the surrounding topology changed.
        S.native.devices := [{id: 2, hid: "HID\DUPLICATE"}, {id: 5, hid: "HID\DUPLICATE"}]
        ConfirmMicSetup()
        Check(S.setup.stage = "failed" && FileRead(ConfigPath) = original,
            "Duplicate topology change rejected even with unchanged chosen id/HID")
        Pass("duplicate-HID topology changes between trial and confirmation refuse save")
    }
    CancelMicSetup(false)

    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    DetectButton()
    if Trial("connection changes") {
        S.native.devices := [{id: 7, hid: "ACPI\REPLACEMENT"}]
        ConfirmMicSetup()
        Check(S.setup.stage = "failed" && FileRead(ConfigPath) = original, "Disappeared output rejected before persistence")
        Pass("connection change between trial and confirmation refuses save")
    }
    CancelMicSetup(false)

    for enabledBefore in [true, false] {
        ResetCase(true)
        S.enabled := enabledBefore
        S.resume := enabledBefore
        original := FileRead(ConfigPath), oldProfile := S.profile
        BeginMicSetup()
        Check(S.setup.mode = "standard" && S.button.preference = "standard"
            && S.setup.dialog.mode = "standard", "Default setup follows existing standard profile")
        Check(S.setup.priorEnabled = enabledBefore && FileRead(ConfigPath) = original,
            "Opening setup preserves the prior enabled state and disk configuration")
        standardListener := S.button
        MicButtonDetected({source: "hid", device: "TEST_RECEIVER_PATH", usagePage: 12, usage: 1})
        Check(S.setup.stage = "failed" && S.setup.mode = "standard" && !S.setup.profile
            && !standardListener.running, "Standard mode rejects a HID result without silently switching")
        SwitchMicSetupMode("compatibility")
        Check(S.setup.mode = "compatibility" && S.button.preference = "compatibility"
            && !standardListener.learning && S.profile = oldProfile && FileRead(ConfigPath) = original,
            "Explicit compatibility switch cleans the old listener without changing saved profile")
        compatibilityListener := S.button
        DetectButton()
        Check(compatibilityListener.guardActive, "Compatibility trial owns the fake guard")
        SwitchMicSetupMode("standard")
        Check(!compatibilityListener.guardActive && !compatibilityListener.running
            && S.setup.mode = "standard" && S.button.preference = "standard"
            && !S.setup.tested && !S.setup.profile, "Switch stops compatibility guard before learning standard mode")
        CancelMicSetup()
        Check(S.profile = oldProfile && FileRead(ConfigPath) = original
            && EnableRequests = (enabledBefore ? 1 : 0) && S.enabled = enabledBefore,
            "Cancelled mode changes restore exactly the previous enabled or paused state")
    }
    Pass("explicit mode changes preserve old profile, stop guard and restore prior enabled or paused state")

    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("invalid")
    Check(!S.settingUp && !S.button && FileRead(ConfigPath) = original, "Invalid mode does not start or persist anything")
    BeginMicSetup()
    Check(S.setup.mode = "standard" && S.button.preference = "standard", "Fresh setup defaults to standard mode")
    MicLearningTimeout()
    Check(S.setup.mode = "standard" && S.setup.stage = "failed" && S.setup.dialog.canRetry,
        "Standard timeout offers failure actions without an automatic compatibility fallback")
    RetryMicSetup()
    Check(S.setup.mode = "standard" && S.button.preference = "standard", "Retry keeps the explicitly selected input mode")
    MicButtonDetected({source: "registered", device: "", usagePage: 12, usage: 1})
    Check(S.setup.stage = "ready" && !S.button.guardActive, "Standard registered input can start its trial without a HID guard")
    if Trial("standard mode confirmed output") {
        ConfirmMicSetup()
        Check(MicProfileMode(LoadMicProfile(ConfigPath, S.machine)) = "standard",
            "Actual standard trial plus joint confirmation saves standard input")
    } else
        CancelMicSetup(false)
    Pass("standard timeout/retry stays standard and only a confirmed actual trial saves it")

    ResetCase()
    original := FileRead(ConfigPath)
    BeginMicSetupMode("compatibility")
    MicButtonDetected({source: "key", device: "", usagePage: 12, usage: 1})
    Check(S.setup.stage = "failed" && !S.setup.profile && S.setup.mode = "compatibility"
        && FileRead(ConfigPath) = original, "Compatibility mode rejects key input without switching or saving")
    RetryMicSetup()
    DetectButton()
    oldListener := S.button
    oldListener.failStop := true
    SwitchMicSetupMode("standard")
    Check(S.setup.mode = "compatibility" && S.button = oldListener && S.setup.stage = "failed"
        && !S.setup.dialog.canRetry && !S.setup.retryOutput && FileRead(ConfigPath) = original,
        "Failed listener cleanup blocks mode change and any new learner")
    oldListener.failStop := false
    CancelMicSetup(false)
    Pass("cross-mode source rejection and cleanup failure cannot start a replacement listener or save")

    ResetCase(true)
    S.profile.source := "hid", S.profile.device := "TEST_RECEIVER_PATH"
    SaveMicProfile(ConfigPath, S.profile, S.machine)
    BeginMicSetup()
    Check(S.setup.mode = "compatibility" && S.button.preference = "compatibility", "Existing HID profile opens compatibility setup")
    CancelMicSetup()
    Pass("existing compatibility profile remains the default for setup")

    S.enabled := false
    S.profile := 0
    IniWrite(0, ConfigPath, "Button", "Verified")
    original := FileRead(ConfigPath)
    BeginMicSetup()
    Check(S.setup.mode = "compatibility" && !S.enabled && !S.profile,
        "Invalidated same-machine profile retains only compatibility preference")
    CancelMicSetup()
    Check(FileRead(ConfigPath) = original && !S.enabled && !S.profile,
        "Cancelling preference-only setup never re-verifies or enables old settings")
    S.machine := ProfileDigest("DIFFERENT_TEST_MACHINE_ONLY")
    BeginMicSetup()
    Check(S.setup.mode = "standard", "Copied-machine preferences cannot override standard default")
    CancelMicSetup(false)
    Pass("same-machine invalidated preference survives shortcut edits without enabling or following a copied machine")

    CheckSafeLogs()
    Report .= "SKIP cases=" Skipped "`r`n"
    FileOpen(DataDir "\report.txt", "w", "UTF-8").Write(Report)
    ExitApp(0)
} catch as err {
    try CancelMicSetup(false)
    FileOpen(DataDir "\report.txt", "w", "UTF-8").Write(Report "FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
}

ResetCase(prior := false) {
    global S, Logs, EnableRequests, ConfigPath
    CheckSafeLogs()
    Logs := [], EnableRequests := 0
    if FileExist(ConfigPath)
        FileDelete(ConfigPath)
    IniWrite("en", ConfigPath, "UI", "Language")
    S := {busy: false, maintenance: false, editing: false, enabled: prior, pendingReboot: false,
        held: {keys: []}, binding: ParseShortcut(), button: 0, native: NativeOutput(),
        devices: [], selected: 0, savedHid: "", profile: 0, machine: ProfileDigest("TEST_MACHINE_ONLY"),
        settingUp: false, setup: 0, resume: prior, notice: ""}
    if prior {
        S.devices := S.native.Enumerate()
        S.selected := 1
        S.profile := {source: "key", device: "", usagePage: 12, usage: 1,
            outputHid: S.devices[1].hid, outputId: 2,
            topology: ProfileTopology(S.devices), shortcut: "RAlt+Space", volumeVerified: true}
        S.savedHid := S.profile.outputHid
        SaveMicProfile(ConfigPath, S.profile, S.machine)
    }
}

DetectButton() {
    MicButtonDetected({source: "hid", device: "TEST_RECEIVER_PATH", usagePage: 12, usage: 1})
}

Trial(label, expectSuccess := true) {
    global S, Skipped, Report, Logs
    S.setup.notBefore := 0
    before := S.native.events.Length
    MicSetupPress()
    if S.native.events.Length = before {
        Check(Logs.Length && Logs[Logs.Length] = "setup_trial_skipped held_key",
            "A skipped trial must be explained by the actual physical-key guard")
        Skipped++
        Report .= "SKIP " label ": a physical modifier or Space was held; no real input sent.`r`n"
        return false
    }
    if expectSuccess
        Check(S.setup.stage = "confirming" && S.setup.tested, "Actual trial reached confirmation")
    return true
}

CheckSafeLogs() {
    global Logs, DataDir, S
    for line in Logs
        Check(!InStr(line, DataDir) && !InStr(line, "TEST_RECEIVER_PATH") && !InStr(line, "ACPI\")
            && (!IsObject(S) || !InStr(line, S.machine)), "Diagnostic logs omit machine/device identifiers and paths")
}

ShowMicSetup(owner, cancel, retry, yes, no, volume, switchMode, mode) {
    dialog := MockDialog()
    dialog.mode := mode
    return dialog
}
DriverReady() => true
UpdateUI(*) {
}
StopMapping(*) {
    global S
    S.enabled := false
    ReleaseHeldKeys()
}
ReleaseHeldKeys() {
    global S
    ReleaseConfiguredKeys(S.native, S.held)
}
EnableMapping(*) {
    global EnableRequests, S
    EnableRequests++
    S.enabled := true
}
Log(message) {
    global Logs
    Logs.Push(message)
}
Check(condition, message) {
    if !condition
        throw Error(message)
}
Pass(label) {
    global Report
    Report .= "PASS " label "`r`n"
}

class MockDialog {
    focused := true, focusRequests := 0, closed := false, canRetry := true
    focusChecks := 0, loseFocusOnCheck := 0
    SetMode(mode) {
        this.mode := mode
    }
    Listening(*) {
    }
    Ready(*) {
    }
    Waiting(*) {
    }
    Busy(*) {
    }
    Failure(message, canRetry := true) {
        this.canRetry := canRetry
    }
    InputFocused(allowBusy := false) {
        this.focusChecks++
        if this.loseFocusOnCheck && this.focusChecks >= this.loseFocusOnCheck
            this.focused := false
        return this.focused
    }
    FocusInput() {
        this.focusRequests++
        this.focused := true
    }
    Close() {
        this.closed := true
    }
}
class MicButtonInput {
    learning := false, running := false, stops := 0, failStop := false, guardActive := false
    __New(*) {
        ; Production may supply a DLL path; this fake never opens it.
    }
    Learn(callback, preference := "standard") {
        this.learning := true
        this.preference := preference
    }
    Start(profile, *) {
        this.running := true
        this.guardActive := profile.source = "hid"
    }
    Stop() {
        this.stops++
        ; Native guard's contract is disarm-before-unhook, even on failure.
        this.guardActive := false
        if this.failStop
            throw Error("Requested mock listener stop failure")
        this.learning := false
        this.running := false
    }
}
class NativeOutput {
    __New(*) {
        this.devices := [{id: 2, hid: "ACPI\TEST_A"}, {id: 4, hid: "HID\VID_TEST_B"}]
        this.events := [], this.failAt := 0, this.failReleases := false
    }
    Enumerate() => this.devices
    Send(device, code, state) {
        this.events.Push({device: device, code: code, state: state})
        if this.events.Length = this.failAt || (this.failReleases && (state & 1))
            throw Error("Requested mock failure")
    }
    Sequence() {
        result := ""
        for event in this.events
            result .= (result = "" ? "" : ",") event.device ":" event.code ":" event.state
        return result
    }
}
