; Read-only diagnostic collection and deliberately conservative report analysis.
; No input, hooks, driver changes, persistence, GUI, or action on #Include.
; GetDriverStatus and keyboard enumeration are performed once by the caller.
; All exported objects/text use explicit field allowlists. Hardware IDs exist
; only during the local equality check and are never returned.

CollectDiagnosticEnvironment(configPath, keyboards := [], driverStatus := 0, hidServiceStatus := unset) {
    raw := {osVersion: A_OSVersion, osBuild: "", ahkVersion: A_AhkVersion,
        admin: A_IsAdmin, elevated: DiagnosticProcessElevated()}
    try {
        build := RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentBuildNumber", "")
        revision := RegRead("HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "UBR", "")
        raw.osBuild := build (revision != "" ? "." revision : "")
    }
    raw.hidService := IsSet(hidServiceStatus) ? hidServiceStatus : DiagnosticHidServiceState()
    return ProjectDiagnosticEnvironment(raw, keyboards, driverStatus, ReadDiagnosticConfig(configPath))
}

; This pure projection is also the privacy boundary used by tests.
ProjectDiagnosticEnvironment(raw, keyboards := [], driverStatus := 0, config := 0) {
    driverKnown := DRBool(DRGet(driverStatus, "known"))
    driver := {known: driverKnown}
    for name in ["installed", "running", "pending", "partial", "serviceConflict", "keyboardRunning", "mouseRunning"]
        driver.%name% := driverKnown = 1 ? DRBool(DRGet(driverStatus, name)) : "unknown"
    driver.keyboardFilter := driverKnown = 1 ? DRHasFilter(DRGet(driverStatus, "keyboardFilters"), "keyboard") : "unknown"
    driver.mouseFilter := driverKnown = 1 ? DRHasFilter(DRGet(driverStatus, "mouseFilters"), "mouse") : "unknown"
    count := keyboards is Array ? Min(keyboards.Length, 100) : "unknown"
    profile := {present: DRBool(DRGet(config, "present")), version: DRVersion(DRGet(config, "version")),
        source: DREnum(DRGet(config, "source"), "registered|key|hid"), verified: DRBool(DRGet(config, "verified")),
        volumeVerified: DRBool(DRGet(config, "volumeVerified")), outputMatch: "unknown", candidateIndex: 0}
    outputHid := DRGet(config, "outputHid", "")
    if Type(outputHid) = "String" && outputHid != "" && keyboards is Array {
        matches := []
        for index, keyboard in keyboards {
            if index > 100
                break
            hid := DRGet(keyboard, "hid", "")
            if Type(hid) = "String" && hid = outputHid
                matches.Push(index)
        }
        profile.outputMatch := matches.Length = 1 ? "matched" : (matches.Length > 1 ? "ambiguous" : "missing")
        if matches.Length = 1
            profile.candidateIndex := matches[1]
    } else if Type(outputHid) = "String" && outputHid = ""
        profile.outputMatch := "not_configured"
    return {osVersion: DRVersion(DRGet(raw, "osVersion")), osBuild: DRVersion(DRGet(raw, "osBuild")),
        ahkVersion: DRVersion(DRGet(raw, "ahkVersion")), admin: DRBool(DRGet(raw, "admin")),
        elevated: DRBool(DRGet(raw, "elevated")),
        hidService: DREnum(DRGet(raw, "hidService"), "running|stopped|start_pending|stop_pending|continue_pending|pause_pending|paused|missing"),
        keyboardCount: count, driver: driver, profile: profile}
}

ReadDiagnosticConfig(path) {
    result := {present: false, version: "", source: "", verified: "unknown", volumeVerified: "unknown", outputHid: ""}
    try {
        if !FileExist(path)
            return result
        result.present := true
        result.version := IniRead(path, "Button", "Version", "")
        result.source := IniRead(path, "Button", "Source", "")
        result.verified := IniRead(path, "Button", "Verified", "unknown")
        result.volumeVerified := IniRead(path, "Button", "VolumeVerified", "unknown")
        result.outputHid := IniRead(path, "Button", "OutputHardwareId", "")
        if result.outputHid = ""
            result.outputHid := IniRead(path, "Mapping", "HardwareId", "")
    }
    return result
}

AnalyzeDiagnosticResults(phases, trials := []) {
    result := {confirmed: [], notObserved: [], needsVerification: []}
    safePhases := DRPhases(phases), safeTrials := DRTrials(trials)
    if !safePhases.Length
        result.needsVerification.Push("尚未完成按钮采样。")
    for phase in safePhases {
        label := DRPhaseLabel(phase.phaseId), c := phase.counts
        valid := phase.phaseId != "unknown" && phase.completed = 1 && (phase.userConfirmedPresses = 1 || c.rawKeyboardDown > 0 || c.hidDown > 0)
            && phase.workerExited = 1 && phase.cleanupOk = 1 && phase.workerEndReason = "confirmed"
        if !valid
            result.needsVerification.Push(label "：采样未完成或未确认安全结束；零计数不能用于判断此方式是否可用。")
        if phase.registration.attempted = 1 && phase.registration.ok = 0
            result.confirmed.Push(label "：本次注册未成功（Windows 返回码 " phase.registration.errorCode "）。")
        if c.rawKeyboardDown > 0
            result.confirmed.Push(label "：收到原始键盘按下事件 " c.rawKeyboardDown " 次。")
        if c.hidDown > 0
            result.confirmed.Push(label "：收到媒体按钮按下事件 " c.hidDown " 次。")
        callbackCount := phase.phaseId = "legacy" ? c.legacyHotkey : phase.phaseId = "registered" ? c.registeredHotkey
            : phase.phaseId = "hook" ? c.hookDown : phase.phaseId = "baseline" ? c.rawKeyboardDown + c.hidDown : 0
        if callbackCount > 0
            result.confirmed.Push(label "：收到对应监听回调 " callbackCount " 次。")
        else if valid
            result.notObserved.Push(label "：本次未记录到对应监听回调；这不等于此方式始终不可用。")
        if c.wmHotkey > 0
            result.confirmed.Push(label "：观察到 WM_HOTKEY " c.wmHotkey " 次。")
        if c.eligible > 0
            result.confirmed.Push(label "：" c.eligible " 次通过模拟发送前的条件检查；此计数不代表已经发送或启动豆包。")
        if valid && c.rawKeyboardDown = 0 && c.hidDown = 0
            result.notObserved.Push(label "：用户确认已按按钮，本次未记录到原始键盘或媒体按钮事件。")
        if phase.phaseId = "hook" && valid && !phase.errors.Length && c.hidDown > 0 && c.hookDown = 0
            result.needsVerification.Push(label "：有媒体事件，但未观察到键盘 Hook 回调。仅凭这一点不能判断驱动或硬件故障。")
        if phase.errors.Length
            result.needsVerification.Push(label "：存在采样或清理错误，请结合技术计数重新测试。")
    }
    manualSuccess := false, successes := Map(), failures := Map()
    for trial in safeTrials {
        label := DRTrialLabel(trial.kind)
        if trial.kind = "manual" {
            if trial.confirmed = "success" {
                manualSuccess := true
                result.confirmed.Push(label "：用户确认豆包语音已启动。")
            } else if trial.confirmed = "failure"
                result.confirmed.Push(label "：用户确认本次没有启动豆包语音。")
            else
                result.needsVerification.Push(label "：尚未由用户确认结果。")
            continue
        }
        if trial.sent = 1 {
            if trial.confirmed = "success" {
                result.confirmed.Push(label "：快捷键已交付，用户确认豆包语音已启动。")
                if trial.candidateIndex
                    successes[trial.candidateIndex] := true
            } else if trial.confirmed = "failure" {
                result.confirmed.Push(label "：快捷键已交付，用户确认输入法未响应。")
                if trial.candidateIndex
                    failures[trial.candidateIndex] := true
            } else
                result.needsVerification.Push(label "：快捷键已交付，尚未由用户确认豆包是否启动。")
        } else if trial.confirmed = "success"
            result.needsVerification.Push(label "：有成功确认但没有发送交付记录，暂不能归因于此发送方式。")
        else
            result.needsVerification.Push(label "：未完成快捷键交付测试。")
    }
    different := false
    if manualSuccess {
        for successIndex in successes
            for failureIndex in failures
                if successIndex != failureIndex
                    different := true
    }
    if different
        result.confirmed.Push("手动快捷键有效，且两个不同的本机候选连接一成一败：支持‘本次输出选择差异’，不能证明历史故障的根因。")
    if !safeTrials.Length
        result.needsVerification.Push("尚未进行手动快捷键和本机输出方式测试。")
    return result
}

BuildDiagnosticReport(environment, phases, trials := []) {
    ; Re-project every rendered field: callers cannot accidentally leak extra data.
    analysis := AnalyzeDiagnosticResults(phases, trials)
    result := "AirKey 按钮诊断报告`r`n`r`n"
    for pair in [["已确认", analysis.confirmed], ["本次未观察到", analysis.notObserved], ["仍需验证", analysis.needsVerification]] {
        result .= pair[1] "`r`n"
        if !pair[2].Length
            result .= "- 暂无。`r`n"
        for line in pair[2]
            result .= "- " line "`r`n"
        result .= "`r`n"
    }
    result .= "环境状态（只读）`r`n"
    result .= "Windows 版本：" DRVersion(DRGet(environment, "osVersion")) "；构建：" DRVersion(DRGet(environment, "osBuild")) "`r`n"
    result .= "AutoHotkey 版本：" DRVersion(DRGet(environment, "ahkVersion")) "`r`n"
    result .= "管理员标志：" DRBoolLabel(DRGet(environment, "admin")) "；进程已提升权限：" DRBoolLabel(DRGet(environment, "elevated")) "`r`n"
    result .= "人机接口服务：" DRServiceLabel(DRGet(environment, "hidService")) "`r`n"
    keyboardCount := DRGet(environment, "keyboardCount")
    result .= "当前可枚举键盘数量：" (DRIsCount(keyboardCount, 100) ? keyboardCount : "未知") "`r`n"
    driver := DRGet(environment, "driver", 0)
    result .= "Interception 状态可确认：" DRBoolLabel(DRGet(driver, "known")) "`r`n"
    if DRBool(DRGet(driver, "known")) = 1 {
        result .= "驱动完整配置：" DRBoolLabel(DRGet(driver, "installed")) "；驱动运行：" DRBoolLabel(DRGet(driver, "running")) "`r`n"
        result .= "键盘驱动运行：" DRBoolLabel(DRGet(driver, "keyboardRunning")) "；鼠标驱动运行：" DRBoolLabel(DRGet(driver, "mouseRunning")) "`r`n"
        result .= "键盘过滤项已配置：" DRBoolLabel(DRGet(driver, "keyboardFilter")) "；鼠标过滤项已配置：" DRBoolLabel(DRGet(driver, "mouseFilter")) "`r`n"
        result .= "配置不完整：" DRBoolLabel(DRGet(driver, "partial")) "；同名服务冲突：" DRBoolLabel(DRGet(driver, "serviceConflict")) "`r`n"
    }
    profile := DRGet(environment, "profile", 0)
    result .= "已有配置文件：" DRBoolLabel(DRGet(profile, "present")) "；按钮配置版本：" DRVersion(DRGet(profile, "version")) "`r`n"
    result .= "保存的按钮来源：" DRSourceLabel(DRGet(profile, "source")) "`r`n"
    result .= "配置中的启动确认：" DRBoolLabel(DRGet(profile, "verified")) "；音量不变确认：" DRBoolLabel(DRGet(profile, "volumeVerified")) "`r`n"
    result .= "保存的输出与当前枚举匹配：" DRMatchLabel(DRGet(profile, "outputMatch")) "`r`n"
    result .= "以上确认标志来自已有配置，不代表本次已验证成功；硬件标识匹配也不代表整个设置仍有效。`r`n`r`n技术计数`r`n"
    for phase in DRPhases(phases) {
        result .= "[" phase.phaseId "] 完成=" DRBoolLabel(phase.completed) "；用户确认已按=" DRBoolLabel(phase.userConfirmedPresses)
            . "；目标次数=" phase.targetPresses "；时长=" phase.durationMs "ms；结束=" phase.workerEndReason
            . "；子进程退出=" DRBoolLabel(phase.workerExited) "；清理成功=" DRBoolLabel(phase.cleanupOk) "`r`n"
        result .= "注册 attempted=" DRBoolLabel(phase.registration.attempted) " ok=" DRBoolLabel(phase.registration.ok) " code=" phase.registration.errorCode "`r`n"
        result .= "counts: " DRNumberFields(phase.counts, DRCountNames()) "`r`ngates: " DRNumberFields(phase.gates, DRGateNames()) "`r`n"
        result .= "音量事件修饰键位掩码=" phase.modifierMask "；旧版注册类型=" phase.legacyRegisteredType "`r`n"
        for err in phase.errors
            result .= "error: " err.stage "/" err.code " win32=" err.win32 "`r`n"
    }
    for trial in DRTrials(trials)
        result .= "[output/" trial.kind "] candidate=" trial.candidateIndex " delivered=" DRBoolLabel(trial.sent)
            . " user=" trial.confirmed " error=" trial.errorCode "`r`n"
    result .= "`r`n说明：事件计数可能来自同一次物理按键，不能相加当作按键次数。sendAttempt 为进入模拟发送门禁次数，eligible 为通过模拟门禁次数；两者都没有发送按键。`r`n"
    result .= "本工具不会自动检测豆包是否在录音，启动结果以用户确认记录。没有响应不能单独证明驱动或硬件故障。`r`n"
    result .= "旧版候选是按当前电脑推测的选择；当前槽位 1 不一定是历史日志中的同一设备。`r`n"
    result .= "隐私：此报告不包含用户名、电脑名、网络地址、设备硬件标识、序列号、文件路径、输入内容或完整进程列表。`r`n"
    return result
}

DRPhases(phases) {
    result := []
    if !(phases is Array)
        return result
    for raw in phases {
        if result.Length >= 8
            break
        counts := {}, gates := {}
        for name in DRCountNames()
            counts.%name% := DRCount(DRGet(DRGet(raw, "counts", 0), name))
        for name in DRGateNames()
            gates.%name% := DRCount(DRGet(DRGet(raw, "gates", 0), name))
        registration := DRGet(raw, "registration", 0)
        safe := {phaseId: DREnum(DRGet(raw, "phaseId"), "legacy|registered|hook|baseline"), counts: counts, gates: gates,
            completed: DRBool(DRGet(raw, "completed")), userConfirmedPresses: DRBool(DRGet(raw, "userConfirmedPresses")),
            targetPresses: DRCount(DRGet(raw, "targetPresses", 2), 20), durationMs: DRCount(DRGet(raw, "durationMs")),
            cleanupOk: DRBool(DRGet(raw, "cleanupOk")), workerExited: DRBool(DRGet(raw, "workerExited")),
            workerEndReason: DREnum(DRGet(raw, "workerEndReason"), "confirmed|timeout|cancelled|parent_lost|start_failed"),
            modifierMask: DRCount(DRGet(raw, "modifierMask"), 255),
            legacyRegisteredType: DREnum(DRGet(raw, "legacyRegisteredType"), "reg-observed"),
            registration: {attempted: DRBool(DRGet(registration, "attempted")), ok: DRBool(DRGet(registration, "ok")),
                errorCode: DRCount(DRGet(registration, "errorCode"), 0xFFFFFFFF)}, errors: []}
        errors := DRGet(raw, "errors", 0)
        if errors is Array {
            for err in errors {
                if safe.errors.Length >= 16
                    break
                safe.errors.Push({stage: DREnum(DRGet(err, "stage"), "start|register|raw|hook|cleanup"),
                    code: DREnum(DRGet(err, "code"), DRErrorCodes(), "OTHER"), win32: DRCount(DRGet(err, "win32"), 0xFFFFFFFF)})
            }
        }
        result.Push(safe)
    }
    return result
}

DRTrials(trials) {
    result := []
    if !(trials is Array)
        return result
    for raw in trials {
        if result.Length >= 12
            break
        result.Push({kind: DREnum(DRGet(raw, "kind"), "legacy_first|legacy_slot1|matched|manual|alternate"),
            sent: DRBool(DRGet(raw, "sent")), candidateIndex: DRCount(DRGet(raw, "candidateIndex"), 100),
            confirmed: DREnum(DRGet(raw, "confirmed", DRGet(raw, "confirmation")), "success|failure|untested", "untested"),
            errorCode: DREnum(DRGet(raw, "errorCode", "NONE"), "NONE|SEND_FAILED|NO_OUTPUT|NOT_MATCHED|FOCUS_LOST|KEY_HELD|CANCELLED|NOT_TESTED|OUTPUT_UNAVAILABLE", "OTHER")})
    }
    return result
}

DRCountNames() => ["legacyHotkey", "wmHotkey", "registeredHotkey", "hookDown", "hookUp", "llDown", "llUp", "rawKeyboardDown", "rawKeyboardUp", "hidDown", "hidUp", "eligible", "sendAttempt", "rearmed"]
DRGateNames() => ["disabled", "unarmed", "busy", "noOutput", "maintenance", "editing", "heldShortcut"]
DRErrorCodes() => "START_FAILED|CLEANUP_FAILED|LL_CALLBACK_FAILED|DEVICE_INFO_FAILED|REGISTER_FAILED|UNREGISTER_FAILED|HOOK_STOP_FAILED|HOOK_SETUP_FAILED|LL_INSTALL_FAILED|LL_UNHOOK_FAILED|RAW_REGISTER_FAILED|RAW_UNREGISTER_FAILED|RAW_READ_FAILED|HID_PARSE_FAILED"
DRGet(value, name, fallback := "unknown") {
    try {
        if value is Map
            return value.Has(name) ? value[name] : fallback
        if IsObject(value) && value.HasOwnProp(name)
            return value.%name%
    }
    return fallback
}
DRBool(value) => (Type(value) = "Integer" || Type(value) = "String") && (value == "0" || value == "1") ? Integer(value) : "unknown"
DRBoolLabel(value) => DRBool(value) = 1 ? "是" : DRBool(value) = 0 ? "否" : "未知"
DRIsCount(value, maximum := 10000000) => (Type(value) = "Integer" || Type(value) = "String") && IsInteger(value) && value >= 0 && value <= maximum
DRCount(value, maximum := 10000000) => DRIsCount(value, maximum) ? Integer(value) : 0
DRVersion(value) => (Type(value) = "String" || Type(value) = "Integer") && RegExMatch(value "", "\A[0-9]{1,10}(\.[0-9]{1,10}){0,3}\z") ? value "" : "未知"
DREnum(value, allowed, fallback := "unknown") {
    if Type(value) != "String"
        return fallback
    for item in StrSplit(allowed, "|")
        if value == item
            return item
    return fallback
}
DRHasFilter(value, expected) {
    if Type(value) != "String"
        return "unknown"
    for line in StrSplit(value, "`n", "`r")
        if Trim(line) = expected
            return true
    return false
}
DRNumberFields(value, names) {
    result := ""
    for name in names
        result .= (result = "" ? "" : " ") name "=" DRCount(DRGet(value, name))
    return result
}
DRPhaseLabel(value) {
    switch value {
        case "legacy": return "旧版热键方式"
        case "registered": return "显式注册热键方式"
        case "hook": return "键盘 Hook 方式"
        case "baseline": return "仅观察按钮方式"
        default: return "未知采样方式"
    }
}
DRTrialLabel(value) {
    switch value {
        case "manual": return "手动右 Alt＋空格"
        case "legacy_first": return "按旧版首次运行规则推测的当前连接"
        case "legacy_slot1": return "当前槽位 1 的连接"
        case "matched": return "当前保存的匹配连接"
        case "alternate": return "另一种本机连接"
        default: return "未知输出方式"
    }
}
DRSourceLabel(value) {
    switch value {
        case "registered": return "注册热键"
        case "key": return "键盘事件"
        case "hid": return "媒体按钮事件"
        default: return "未知"
    }
}
DRMatchLabel(value) {
    switch value {
        case "matched": return "找到唯一匹配"
        case "missing": return "本次没有匹配"
        case "ambiguous": return "有多个同标识候选，仍需确认"
        case "not_configured": return "没有保存的输出"
        default: return "未知"
    }
}
DRServiceLabel(value) {
    switch value {
        case "running": return "运行中"
        case "stopped": return "已停止"
        case "start_pending": return "正在启动"
        case "stop_pending": return "正在停止"
        case "continue_pending": return "正在继续"
        case "pause_pending": return "正在暂停"
        case "paused": return "已暂停"
        case "missing": return "未找到"
        default: return "未知"
    }
}

DiagnosticProcessElevated() {
    token := 0
    try {
        if !DllCall("Advapi32\OpenProcessToken", "Ptr", DllCall("Kernel32\GetCurrentProcess", "Ptr"), "UInt", 8, "Ptr*", &token, "Int")
            return "unknown"
        value := Buffer(4, 0), required := 0
        if !DllCall("Advapi32\GetTokenInformation", "Ptr", token, "Int", 20, "Ptr", value, "UInt", 4, "UInt*", &required, "Int")
            return "unknown"
        return !!NumGet(value, 0, "UInt")
    } catch {
        return "unknown"
    } finally {
        if token
            DllCall("Kernel32\CloseHandle", "Ptr", token)
    }
}

DiagnosticHidServiceState() {
    manager := 0, service := 0
    try {
        manager := DllCall("Advapi32\OpenSCManagerW", "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr")
        if !manager
            return "unknown"
        service := DllCall("Advapi32\OpenServiceW", "Ptr", manager, "Str", "hidserv", "UInt", 4, "Ptr")
        if !service
            return A_LastError = 1060 ? "missing" : "unknown"
        status := Buffer(36, 0), needed := 0
        if !DllCall("Advapi32\QueryServiceStatusEx", "Ptr", service, "Int", 0, "Ptr", status, "UInt", status.Size, "UInt*", &needed, "Int")
            return "unknown"
        states := ["stopped", "start_pending", "stop_pending", "running", "continue_pending", "pause_pending", "paused"]
        state := NumGet(status, 4, "UInt")
        return state >= 1 && state <= states.Length ? states[state] : "unknown"
    } catch {
        return "unknown"
    } finally {
        if service
            DllCall("Advapi32\CloseServiceHandle", "Ptr", service)
        if manager
            DllCall("Advapi32\CloseServiceHandle", "Ptr", manager)
    }
}
