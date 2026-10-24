#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
#Include %A_ScriptDir%\..\ShortcutConfig.ahk

; All configuration belongs to this test run. The sender only calls the mock
; below; no Main startup, GUI, hooks, driver DLL or native input is involved.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\localization"
DirCreate(testDir)
configPath := testDir "\settings.ini"
report := "Localization tests — temporary configuration and mock key output only.`r`n"
try {
    Check(AppLanguage.Current = "zh", "Initial language is Chinese")
    AppLanguage.Current := "en"
    missingPath := testDir "\missing-" A_TickCount "\settings.ini"
    Check(LoadAppLanguage(missingPath) = "zh" && AppLanguage.Current = "zh", "Missing configuration defaults to Chinese")
    Check(!FileExist(missingPath), "Reading a missing configuration does not create it")

    IniWrite("RAlt+Space", configPath, "Mapping", "Shortcut")
    IniWrite(1, configPath, "Mapping", "EnableOnLaunch")
    IniWrite("TEST_DEVICE_ONLY", configPath, "Mapping", "HardwareId")
    IniWrite("test-boot-id", configPath, "Driver", "BootId")
    IniWrite("keep-this-value", configPath, "UI", "OtherPreference")
    AppLanguage.Current := "en"
    Check(LoadAppLanguage(configPath) = "zh", "Missing language key defaults to Chinese")
    report .= "PASS initial Chinese and missing-file/key fallback without creating a configuration.`r`n"

    mappingBefore := IniRead(configPath, "Mapping")
    driverBefore := IniRead(configPath, "Driver")
    SaveAppLanguage("en", configPath)
    Check(AppLanguage.Current = "en" && IniRead(configPath, "UI", "Language") = "en", "Save updates language and file")
    AppLanguage.Current := "zh"
    Check(LoadAppLanguage(configPath) = "en" && AppLanguage.Current = "en", "English survives reload from disk")
    Check(IniRead(configPath, "Mapping") = mappingBefore, "Language save preserves all mapping keys")
    Check(IniRead(configPath, "Driver") = driverBefore, "Language save preserves driver state")
    Check(IniRead(configPath, "UI", "OtherPreference") = "keep-this-value", "Language save preserves unrelated UI preference")
    report .= "PASS English persistence/reload, preserving mapping, driver and unrelated UI settings.`r`n"

    for code in ["fr", "EN", "ZH", "en-US", "zh-CN", ""] {
        IniWrite(code, configPath, "UI", "Language")
        AppLanguage.Current := "en"
        Check(LoadAppLanguage(configPath) = "zh" && AppLanguage.Current = "zh", "Invalid stored code falls back: " code)
    }
    SaveAppLanguage("en", configPath)
    for code in ["fr", "EN", "", 1, {}] {
        rejected := false
        try SaveAppLanguage(code, configPath)
        catch ValueError
            rejected := true
        Check(rejected, "Invalid save is rejected")
        Check(AppLanguage.Current = "en" && IniRead(configPath, "UI", "Language") = "en", "Rejected save preserves language and file")
    }
    report .= "PASS unsupported stored codes fall back to Chinese; invalid saves preserve the previous selection.`r`n"

    writeFailed := false
    try SaveAppLanguage("zh", missingPath)
    catch OSError
        writeFailed := true
    Check(writeFailed, "Missing parent causes a real configuration write failure")
    Check(AppLanguage.Current = "en", "Write failure preserves the in-memory language")
    Check(IniRead(configPath, "UI", "Language") = "en", "Write failure preserves the existing saved language")
    Check(IniRead(configPath, "Mapping") = mappingBefore && IniRead(configPath, "Driver") = driverBefore,
        "Failure and invalid saves preserve mapping/driver settings")
    report .= "PASS failed persistence leaves the active language and existing configuration intact.`r`n"

    AppLanguage.Current := "zh"
    immediate := L("第 {1} 次：{2}", "Attempt {1}: {2}", 3, N("已开启", "Enabled"))
    Check(immediate = "第 3 次：已开启", "L immediately formats arguments and nested messages")
    notice := N("状态：{1}；{2}", "Status: {1}; {2}", N("已开启", "Enabled"),
        N("重试 {1} 次：{2}", "Retry {1} times: {2}", 2, N("准备完成", "Ready")))
    Check(Text(notice) = "状态：已开启；重试 2 次：准备完成", "Nested notice initially renders in Chinese")
    AppLanguage.Current := "en"
    Check(Text(notice) = "Status: Enabled; Retry 2 times: Ready", "Existing nested notice rerenders in English")
    Check(immediate = "第 3 次：已开启", "An already rendered L string stays unchanged")
    Check(L("第 {1} 次：{2}", "Attempt {1}: {2}", 3, N("已开启", "Enabled")) = "Attempt 3: Enabled",
        "L formats with current English language")
    AppLanguage.Current := "zh"
    Check(Text(notice) = "状态：已开启；重试 2 次：准备完成", "Same notice can return to Chinese")
    Check(Text("unchanged") = "unchanged" && Text(7) = 7 && Text("") = "", "Text passes ordinary values through")
    report .= "PASS immediate formatting, persistent messages, nested dynamic translation and ordinary values.`r`n"

    localizedFailure := LocalError("错误 {1}：{2}", "Error {1}: {2}", 17, N("未连接", "Disconnected"))
    Check(localizedFailure is Error, "LocalError remains an Error instance")
    Check(Type(localizedFailure.Message) = "String" && localizedFailure.Message = "错误 17：未连接",
        "Error.Message is an immediately usable string")
    delayedFailure := ErrorText(localizedFailure)
    Check(delayedFailure is AppLocalizedMessage, "ErrorText preserves the bilingual message")
    failureNotice := N("已停止：{1}", "Stopped: {1}", delayedFailure)
    Check(Text(failureNotice) = "已停止：错误 17：未连接", "Nested error notice initially renders in Chinese")
    AppLanguage.Current := "en"
    Check(Text(delayedFailure) = "Error 17: Disconnected", "Existing error arguments rerender in English")
    Check(Text(failureNotice) = "Stopped: Error 17: Disconnected", "Outer notice and nested error change together")
    Check(localizedFailure.Message = "错误 17：未连接", "Original Error.Message remains stable for logs")
    AppLanguage.Current := "zh"
    Check(Text(failureNotice) = "已停止：错误 17：未连接", "Existing error notice can return to Chinese")

    valueCaught := false
    try throw LocalTypedError(ValueError, "值不正确：{1}", "Invalid value: {1}", "TEST_ONLY")
    catch ValueError as valueFailure {
        valueCaught := true
        Check(valueFailure is ValueError && valueFailure.Message = "值不正确：TEST_ONLY", "ValueError type and original message are preserved")
        AppLanguage.Current := "en"
        Check(Text(ErrorText(valueFailure)) = "Invalid value: TEST_ONLY", "Typed ValueError remains translatable")
    }
    Check(valueCaught, "LocalTypedError is caught by ValueError")

    typeCaught := false
    try throw LocalTypedError(TypeError, "需要{1}", "Expected {1}", N("对象", "an object"))
    catch TypeError as typeFailure {
        typeCaught := true
        Check(typeFailure is TypeError && typeFailure.Message = "Expected an object", "TypeError preserves type and creation language")
        AppLanguage.Current := "zh"
        Check(Text(ErrorText(typeFailure)) = "需要对象", "Typed TypeError preserves dynamic nested arguments")
    }
    Check(typeCaught, "LocalTypedError is caught by TypeError")

    ordinaryFailure := Error("Original system message: {code}")
    ordinaryMessage := ErrorText(ordinaryFailure)
    for code in ["zh", "en"] {
        AppLanguage.Current := code
        Check(Type(ErrorText(ordinaryFailure)) = "String" && ErrorText(ordinaryFailure) = ordinaryFailure.Message,
            "Ordinary Error passes its original message through")
        Check(Text(N("系统：{1}", "System: {1}", ordinaryMessage))
            = (code = "zh" ? "系统：" : "System: ") "Original system message: {code}",
            "Ordinary error safely nests without interpreting braces in its message")
    }
    report .= "PASS localized Error/ValueError/TypeError keep catch types and stable Message strings while nested UI errors rerender; ordinary errors pass through.`r`n"

    AppLanguage.Current := "zh"
    parserFailure := 0
    try ParseShortcut("RAlt++Space")
    catch ValueError as caughtParserFailure
        parserFailure := caughtParserFailure
    Check(parserFailure is ValueError, "Real shortcut parser retains its ValueError contract")
    Check(Text(ErrorText(parserFailure)) = "不支持这个按键：（空）", "Parser's empty-key detail renders in Chinese")
    AppLanguage.Current := "en"
    Check(Text(ErrorText(parserFailure)) = "Unsupported key: (empty)", "Existing parser error and its nested empty-key detail translate together")
    report .= "PASS actual shortcut parser errors retain type and dynamically translate nested details.`r`n"

    cases := [
        {shortcut: "RAlt+Space", zh: "右 Alt＋空格", en: "Right Alt + Space",
            sequence: "2:38:2,2:39:0,2:39:1,2:38:3"},
        {shortcut: "LCtrl+LShift+Space", zh: "左 Ctrl＋左 Shift＋空格", en: "Left Ctrl + Left Shift + Space",
            sequence: "2:1D:0,2:2A:0,2:39:0,2:39:1,2:2A:1,2:1D:1"},
        {shortcut: "RShift+Space", zh: "右 Shift＋空格", en: "Right Shift + Space",
            sequence: "2:36:0,2:39:0,2:39:1,2:36:1"},
        {shortcut: "RCtrl+Down", zh: "右 Ctrl＋↓", en: "Right Ctrl + Down",
            sequence: "2:1D:2,2:50:2,2:50:3,2:1D:3"}]
    for sample in cases {
        AppLanguage.Current := "zh"
        binding := ParseShortcut(sample.shortcut)
        original := BindingSnapshot(binding)
        for code in ["en", "zh"] {
            AppLanguage.Current := code
            Check(ShortcutDisplayLabel(binding) = sample.%code%, "Dynamic shortcut label: " sample.shortcut " / " code)
            Check(BindingSnapshot(binding) = original, "Display does not mutate canonical, label or stroke records")
            Check(BindingSnapshot(ParseShortcut(sample.shortcut)) = original, "Parsing is language-independent")
            output := LocalizationMockOutput()
            held := {}
            SendConfiguredShortcut(output, 2, binding, held)
            Check(output.Sequence() = sample.sequence, "Exact send sequence: " sample.shortcut " / " code)
            Check(held.keys.Length = 0 && !held.busy, "Mock sends release every held key")
            Check(BindingSnapshot(binding) = original, "Sending preserves original binding")
        }
    }
    report .= "PASS both-language shortcut labels preserve canonical/legacy labels and exact scan-code, E0 and release order.`r`n"
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report)
    ExitApp(0)
} catch as err {
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write(report "FAIL: " err.Message "`r`n" err.Stack)
    ExitApp(1)
}

Check(condition, message) {
    if !condition
        throw Error(message)
}

BindingSnapshot(binding) {
    result := binding.canonical "|" binding.label
    for key in binding.keys
        result .= "|" key.name ":" key.ahkName ":" key.code ":" key.stateDown ":" key.stateUp
    return result
}

class LocalizationMockOutput {
    __New() {
        this.events := []
    }
    Send(device, code, state) {
        this.events.Push({device: device, code: code, state: state})
    }
    Sequence() {
        result := ""
        for stroke in this.events
            result .= (result = "" ? "" : ",") Format("{}:{:X}:{}", stroke.device, stroke.code, stroke.state)
        return result
    }
}
