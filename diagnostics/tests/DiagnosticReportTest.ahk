#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include ..\DiagnosticReport.ahk

; Pure fixtures and a disposable INI only. No hooks, key sends, normal settings,
; driver queries, service queries, GUI windows, or normal user data are touched.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\diagnostic-report"
DirCreate(testDir)
testReport := "Diagnostic report tests — pure fixtures and temporary INI only.`r`n"
try {
    poison := "PRIVATE_SENTINEL C:\Users\private-person\secret.ini PRIVATE_HWID PRIVATE_SERIAL 192.0.2.1"
    driver := {known: true, installed: true, running: false, pending: false, partial: false, serviceConflict: false,
        keyboardRunning: true, mouseRunning: false, keyboardFilters: "kbdclass`r`nkeyboard`r`n" poison,
        mouseFilters: "mouse`n" poison, detail: poison, bootId: poison, description: poison}
    config := {present: true, version: "2", source: "hid", verified: "1", volumeVerified: "0", outputHid: poison,
        Machine: poison, device: poison, topology: poison, shortcut: poison}
    raw := {osVersion: "10.0.26100", osBuild: "26100.1", ahkVersion: "2.0.19", admin: false, elevated: true,
        hidService: "running", username: poison, hostname: poison, path: poison}
    environment := ProjectDiagnosticEnvironment(raw, [{id: 8, hid: poison}], driver, config)
    Check(environment.profile.outputMatch = "matched" && environment.profile.candidateIndex = 1, "Unique match exports only anonymous array index")
    Check(environment.keyboardCount = 1 && environment.driver.keyboardFilter = 1 && environment.driver.mouseFilter = 1, "Counts and expected filter booleans are projected")
    Check(environment.admin = 0 && environment.elevated = 1 && environment.profile.verified = 1, "Explicit true and false preserved")
    Check(!HasReportText(environment, "PRIVATE") && !HasReportText(environment, "192.0.2.1"), "No private input copied into environment")
    duplicate := ProjectDiagnosticEnvironment(raw, [{id: 1, hid: poison}, {id: 2, hid: poison}], driver, config)
    Check(duplicate.profile.outputMatch = "ambiguous" && duplicate.profile.candidateIndex = 0, "Duplicate identifiers cannot imply exact selection")
    missing := ProjectDiagnosticEnvironment(raw, [], driver, config)
    Check(missing.profile.outputMatch = "missing", "No current match is distinguished from unknown")
    unknown := ProjectDiagnosticEnvironment({osVersion: poison, osBuild: poison, ahkVersion: poison, admin: poison, elevated: 7,
        hidService: poison}, 0, {known: false, installed: true, keyboardFilters: "keyboard"}, {source: poison, version: poison, verified: poison})
    Check(unknown.driver.installed = "unknown" && unknown.driver.keyboardFilter = "unknown", "Unconfirmed driver snapshot does not report absent or installed")
    Check(unknown.admin = "unknown" && unknown.elevated = "unknown" && unknown.osVersion = "未知", "Poisoned versions and bools discarded")
    testReport .= "PASS environment allowlists, private identifier comparison, conservative duplicate handling and unknown states.`r`n"

    iniPath := testDir "\fixture.ini"
    IniWrite("2", iniPath, "Button", "Version")
    IniWrite("registered", iniPath, "Button", "Source")
    IniWrite("1", iniPath, "Button", "Verified")
    IniWrite("1", iniPath, "Button", "VolumeVerified")
    IniWrite(poison, iniPath, "Button", "OutputHardwareId")
    IniWrite(poison, iniPath, "Button", "Machine")
    IniWrite(poison, iniPath, "Unrelated", "Secret")
    before := FileRead(iniPath)
    readConfig := ReadDiagnosticConfig(iniPath)
    Check(readConfig.source = "registered" && readConfig.verified = "1" && !readConfig.HasOwnProp("Machine"), "Reads only explicit INI keys")
    Check(FileRead(iniPath) = before, "Reading config never changes settings")
    projected := ProjectDiagnosticEnvironment(raw, [{hid: poison}], driver, readConfig)
    Check(!HasReportText(projected, "PRIVATE"), "INI hardware identifier remains local to comparison")
    Check(!ReadDiagnosticConfig(testDir "\absent.ini").present, "Absent settings are safe")
    testReport .= "PASS selected INI reads and no writes, unrelated settings or stored machine fingerprint exposure.`r`n"

    noPress := FixturePhase()
    noPress.userConfirmedPresses := false
    analysis := AnalyzeDiagnosticResults([noPress])
    Check(HasReportText(analysis.needsVerification, "采样未完成") && !analysis.notObserved.Length, "No event and no press confirmation cannot imply path failure")
    confirmedEmpty := AnalyzeDiagnosticResults([FixturePhase()])
    Check(HasReportText(confirmedEmpty.notObserved, "本次未记录到") && !HasReportText(confirmedEmpty.confirmed, "故障"), "A clean confirmed sample only says not observed this time")
    for name in ["completed", "workerExited", "cleanupOk"] {
        phase := FixturePhase()
        phase.%name% := false
        analysis := AnalyzeDiagnosticResults([phase])
        Check(!analysis.notObserved.Length && HasReportText(analysis.needsVerification, "采样未完成"), "Incomplete lifecycle prevents zero-event conclusions: " name)
    }
    for reason in ["timeout", "cancelled", "parent_lost", "start_failed", poison] {
        phase := FixturePhase()
        phase.workerEndReason := reason
        Check(!AnalyzeDiagnosticResults([phase]).notObserved.Length, "Unconfirmed termination cannot imply absence: " reason)
    }
    phase := FixturePhase("hook")
    phase.counts := {hidDown: 2, hidUp: 2, hookDown: 0, eligible: 2}
    analysis := AnalyzeDiagnosticResults([phase])
    Check(HasReportText(analysis.confirmed, "媒体按钮按下事件 2 次") && HasReportText(analysis.needsVerification, "不能判断驱动或硬件故障"), "HID observation with hook absence cannot diagnose driver failure")
    Check(HasReportText(analysis.confirmed, "不代表已经发送或启动豆包"), "Eligible is not send delivery or IME success")
    phase.completed := false
    Check(HasReportText(AnalyzeDiagnosticResults([phase]).confirmed, "媒体按钮按下事件 2 次"), "Positive observations retained even if lifecycle incomplete")
    testReport .= "PASS incomplete/unpressed/unclean samples, positive observations, conservative no-event statements and gate semantics.`r`n"

    baseline := FixturePhase("baseline")
    baseline.counts := {rawKeyboardDown: 1, hidDown: 2, llDown: 0, hookDown: 0}
    analysis := AnalyzeDiagnosticResults([baseline])
    Check(HasReportText(analysis.confirmed, "对应监听回调 3 次") && !HasReportText(analysis.notObserved, "对应监听回调"), "Raw-only baseline uses raw keyboard plus HID callbacks, never an uninstalled LL hook")
    Check(!HasReportText(analysis.needsVerification, "未观察到键盘 Hook 回调"), "Baseline does not diagnose a hook it never installed")
    for phaseId in ["legacy", "registered"] {
        phase := FixturePhase(phaseId)
        phase.counts := {hidDown: 2, hookDown: 0, legacyHotkey: 2, registeredHotkey: 2}
        Check(!HasReportText(AnalyzeDiagnosticResults([phase]).needsVerification, "未观察到键盘 Hook 回调"), "Non-hook phase cannot compare AHK hook callbacks: " phaseId)
    }
    for name in ["completed", "workerExited", "cleanupOk"] {
        phase := FixturePhase("hook")
        phase.counts := {hidDown: 2, hookDown: 0}
        phase.%name% := false
        Check(!HasReportText(AnalyzeDiagnosticResults([phase]).needsVerification, "未观察到键盘 Hook 回调"), "Incomplete hook sample cannot establish path difference: " name)
    }
    for reason in ["timeout", "cancelled", "parent_lost", "start_failed"] {
        phase := FixturePhase("hook")
        phase.counts := {hidDown: 2, hookDown: 0}
        phase.workerEndReason := reason
        Check(!HasReportText(AnalyzeDiagnosticResults([phase]).needsVerification, "未观察到键盘 Hook 回调"), "Unconfirmed hook termination cannot establish path difference")
    }
    phase := FixturePhase("hook")
    phase.counts := {hidDown: 2, hookDown: 0}
    phase.errors := [{stage: "hook", code: "HOOK_SETUP_FAILED", win32: 5}]
    Check(!HasReportText(AnalyzeDiagnosticResults([phase]).needsVerification, "未观察到键盘 Hook 回调"), "Hook installation failure cannot establish path difference")
    conflict := FixturePhase("registered")
    conflict.registration := {attempted: true, ok: false, errorCode: 1409}
    conflict.counts := {hidDown: 2}
    analysis := AnalyzeDiagnosticResults([conflict])
    Check(HasReportText(analysis.confirmed, "本次注册未成功（Windows 返回码 1409）"), "1409 is reported only as a present registration result")
    Check(!HasReportText(analysis, "fallback") && !HasReportText(analysis, "自动切换") && !HasReportText(analysis, "1.1"), "Registration conflict is not evidence of historical automatic fallback")
    testReport .= "PASS raw-only baseline callbacks, hook-phase-only complete comparisons and no historical fallback inference from 1409.`r`n"

    manual := {kind: "manual", sent: false, confirmed: "success"}
    failed := {kind: "legacy_first", sent: true, confirmed: "failure", candidateIndex: 1}
    success := {kind: "matched", sent: true, confirmed: "success", candidateIndex: 2}
    analysis := AnalyzeDiagnosticResults([], [manual, failed, success])
    Check(HasReportText(analysis.confirmed, "本次输出选择差异") && HasReportText(analysis.confirmed, "不能证明历史故障"), "Manual baseline and different trial outcomes support only a current difference")
    Check(HasReportText(analysis.confirmed, "输入法未响应") && !HasReportText(analysis.confirmed, "驱动故障"), "Delivered but failed is an IME response observation")
    success.candidateIndex := 1
    Check(!HasReportText(AnalyzeDiagnosticResults([], [manual, failed, success]).confirmed, "本次输出选择差异"), "Aliases of the same candidate are not A/B evidence")
    success.candidateIndex := 2
    Check(!HasReportText(AnalyzeDiagnosticResults([], [failed, success]).confirmed, "本次输出选择差异"), "Manual success is required for output-selection conclusion")
    success.sent := false
    analysis := AnalyzeDiagnosticResults([], [manual, success])
    Check(HasReportText(analysis.needsVerification, "没有发送交付记录") && !HasReportText(analysis.confirmed, "当前保存"), "Success without delivery cannot be attributed to automated trial")
    Check(HasReportText(AnalyzeDiagnosticResults([], [{kind: "manual", confirmation: "success"}]).confirmed, "豆包语音已启动"), "Manual baseline supports confirmation alias without a send")
    Check(HasReportText(AnalyzeDiagnosticResults([], [{kind: "legacy_slot1", sent: true, confirmed: "untested"}]).needsVerification, "当前槽位 1"), "Current slot 1 is distinct from legacy selection rules")
    testReport .= "PASS manual/automated outcome separation, delivered versus response, anonymous A/B identity and historical limits.`r`n"

    poisoned := FixturePhase(poison)
    poisoned.durationMs := poison
    poisoned.counts := {hookDown: poison, rawKeyboardDown: -1, hidDown: 1e20, eligible: {secret: poison}, private: poison}
    poisoned.gates := {disabled: poison, busy: -20, private: poison}
    poisoned.registration := {attempted: true, ok: false, errorCode: poison}
    poisoned.errors := [{stage: poison, code: poison, win32: poison}, {stage: "raw", code: "RAW_READ_FAILED", win32: 5}]
    poisoned.devices := [{id: poison, path: poison, serial: poison}]
    poisoned.events := [{text: poison, device: poison}]
    poisoned.modifierMask := poison
    poisoned.legacyRegisteredType := poison
    environment.extra := poison
    environment.osVersion := poison
    environment.profile.outputMatch := poison
    reportText := BuildDiagnosticReport(environment, [poisoned], [{kind: poison, sent: poison, confirmed: poison, candidateIndex: poison, errorCode: poison}])
    Check(!InStr(reportText, "PRIVATE") && !InStr(reportText, "192.0.2.1") && !InStr(reportText, "private-person"), "Report re-sanitizes environment, counters, errors and trial metadata")
    Check(InStr(reportText, "raw/RAW_READ_FAILED win32=5") && InStr(reportText, "unknown/OTHER win32=0"), "Only known error labels and safe numeric codes survive")
    Check(InStr(reportText, "hookDown=0") && InStr(reportText, "hidDown=0"), "Invalid/negative/oversized counts cannot become observations")
    Check(!HasReportText(DRPhases([poisoned]), "PRIVATE") && !HasReportText(DRTrials([{kind: poison, errorCode: poison}]), "PRIVATE"), "Nested projections discard unknown payloads")
    Check(DRCount("12") = 12 && DRCount("12`nPRIVATE") = 0 && DRBool("false") = "unknown", "Numeric and boolean conversion is exact")
    many := []
    loop 20
        many.Push(FixturePhase())
    Check(DRPhases(many).Length = 8 && DRTrials(many).Length = 12, "Report size bounds are enforced")
    testReport .= "PASS second-boundary report redaction, enum/error allowlists, hostile counts and bounded output.`r`n"
    FileAppend(testReport, testDir "\report.txt", "UTF-8")
    FileAppend(testReport, "*")
    ExitApp(0)
} catch as err {
    ; Test failures are fixed assertions only; no fixture data is printed.
    FileAppend(testReport "FAIL: " err.Message "`r`n", testDir "\report.txt", "UTF-8")
    FileAppend("FAIL: " err.Message "`n", "**")
    ExitApp(1)
}

FixturePhase(id := "legacy") => {phaseId: id, completed: true, userConfirmedPresses: true, targetPresses: 2,
    durationMs: 2000, workerEndReason: "confirmed", workerExited: true, cleanupOk: true,
    registration: {attempted: true, ok: true, errorCode: 0}, counts: {}, gates: {}, errors: []}
Check(condition, message) {
    if !condition
        throw Error(message)
}
HasReportText(value, needle) {
    if value is Array {
        for item in value
            if HasReportText(item, needle)
                return true
    } else if value is Map {
        for key, item in value
            if HasReportText(key, needle) || HasReportText(item, needle)
                return true
    } else if IsObject(value) {
        for key, item in value.OwnProps()
            if HasReportText(key, needle) || HasReportText(item, needle)
                return true
    } else if InStr(value "", needle)
        return true
    return false
}
