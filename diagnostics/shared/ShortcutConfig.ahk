; AHK v2 x64. Declarative shortcut parsing and output sequencing only.
; No hooks are installed, no drivers are loaded and no keys are sent on include.
;
; ParseShortcut(text := "RAlt+Space") -> {canonical, label, keys}.
; keys are ordered modifiers then main key, each {code,stateDown,stateUp,name,ahkName}.
; Generic Ctrl/Alt/Shift/Win normalize to the corresponding left-side key.
; Whitelisted names only: no AHK expressions, braces, vk/sc literals or Send syntax.
;
; SendConfiguredShortcut(output, device, binding, heldState) -> true, or throws.
; output.Send(device,code,state) must throw if a stroke was not delivered.
; heldState may initially be {}; its keys[] records every attempted key-down.
; ReleaseConfiguredKeys(output,heldState) -> bool; failed releases remain in keys[]
; and lastError for exit/recovery retries. Both functions preserve device IDs.
; Caller should reject sending while any physical modifier/main key is held.
; Localization.ahk is included explicitly by the diagnostic entry point.

ParseShortcut(canonical := "RAlt+Space") {
    if Type(canonical) != "String" || StrLen(canonical) > 96 || RegExMatch(canonical, "[`r`n{}]")
        throw LocalTypedError(ValueError, "快捷键格式不正确，请使用 Ctrl+Shift+Space 这样的按键组合。",
            "Invalid shortcut format. Use a combination such as Ctrl+Shift+Space.")
    parts := StrSplit(Trim(canonical), "+")
    if parts.Length < 1 || parts.Length > 5
        throw LocalTypedError(ValueError, "请选择一个普通按键，最多搭配四种修饰键。",
            "Choose one regular key with up to four modifier keys.")
    found := Map()
    familySeen := Map()
    main := ""
    for index, part in parts {
        name := ShortcutNormalizeName(Trim(part))
        if ShortcutIsModifier(name) {
            if index = parts.Length
                throw LocalTypedError(ValueError, "快捷键还需要一个普通按键，例如空格或 F8。",
                    "Add a regular key, such as Space or F8, to the shortcut.")
            family := SubStr(name, 2)
            if familySeen.Has(family)
                throw LocalTypedError(ValueError, "同一种修饰键只能选择一次。", "Use each modifier type only once.")
            familySeen[family] := true
            found[name] := true
        } else {
            if index != parts.Length
                throw LocalTypedError(ValueError, "请把普通按键放在组合的最后，例如 RAlt+Space。",
                    "Put the regular key last, for example RAlt+Space.")
            main := name
        }
    }
    if main = ""
        throw LocalTypedError(ValueError, "请指定一个普通按键。", "Choose a regular key.")
    keys := []
    canonical := ""
    label := ""
    for name in ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin"] {
        if found.Has(name) {
            keys.Push(ShortcutKeyRecord(name))
            canonical .= name "+"
            label .= ShortcutKeyLabel(name) "＋"
        }
    }
    keys.Push(ShortcutKeyRecord(main))
    return {canonical: canonical main, label: label ShortcutKeyLabel(main),
        keys: keys}
}

ShortcutNormalizeName(name) {
    static aliases := ShortcutNameAliases()
    if aliases.Has(name)
        return aliases[name]
    if RegExMatch(name, "i)^[a-z0-9]$")
        return StrUpper(name)
    if RegExMatch(name, "i)^f(?:[1-9]|1[0-9]|2[0-4])$")
        return StrUpper(name)
    if RegExMatch(name, "i)^numpad[0-9]$")
        return "Numpad" SubStr(name, -1)
    throw LocalTypedError(ValueError, "不支持这个按键：{1}", "Unsupported key: {1}",
        name = "" ? N("（空）", "(empty)") : name)
}

ShortcutNameAliases() {
    names := Map()
    names.CaseSense := false
    for key in ["LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift", "LWin", "RWin",
        "Space", "Enter", "Tab", "Esc", "Backspace", "Insert", "Delete", "Home", "End",
        "PgUp", "PgDn", "Up", "Down", "Left", "Right", "NumpadDot", "NumpadAdd",
        "NumpadSub", "NumpadMult", "NumpadDiv", "NumpadEnter", "Minus", "Equals",
        "Comma", "Period", "Slash", "Backslash", "Semicolon", "Quote", "Backtick",
        "LeftBracket", "RightBracket"]
        names[key] := key
    for alias, name in Map("Ctrl", "LCtrl", "Control", "LCtrl", "LControl", "LCtrl",
        "RControl", "RCtrl", "Alt", "LAlt", "Shift", "LShift", "Win", "LWin",
        "Escape", "Esc", "Return", "Enter", "BS", "Backspace", "Del", "Delete",
        "Ins", "Insert", "PageUp", "PgUp", "PageDown", "PgDn", "-", "Minus", "=", "Equals",
        ",", "Comma", ".", "Period", "/", "Slash", "\", "Backslash", ";", "Semicolon",
        "'", "Quote", "``", "Backtick", "[", "LeftBracket", "]", "RightBracket")
        names[alias] := name
    return names
}

ShortcutIsModifier(name) {
    return RegExMatch(name, "^(?:L|R)(?:Ctrl|Alt|Shift|Win)$") != 0
}

ShortcutKeyRecord(name) {
    static punctuation := Map("Minus", "-", "Equals", "=", "Comma", ",", "Period", ".",
        "Slash", "/", "Backslash", "\", "Semicolon", ";", "Quote", "'",
        "Backtick", "``", "LeftBracket", "[", "RightBracket", "]")
    ahkName := punctuation.Has(name) ? punctuation[name] : name
    scanCode := GetKeySC(ahkName)
    if scanCode < 1 || scanCode > 0x1FF || (scanCode & 0xFF) = 0
        throw LocalTypedError(ValueError, "当前键盘布局无法发送这个按键：{1}",
            "The current keyboard layout cannot send this key: {1}", N(ShortcutKeyLabel(name), name))
    ; AHK tags RShift as 0x136 for its own keyboard handling, but the physical
    ; make code is 0x36 without E0 (also confirmed by MAPVK_VK_TO_VSC_EX).
    ; Preserve AHK's E0 flag for real extended keys such as RAlt/NumpadEnter.
    extended := name != "RShift" && (scanCode & 0x100) ? 2 : 0
    return {code: scanCode & 0xFF, stateDown: extended, stateUp: extended | 1,
        name: name, ahkName: ahkName}
}

ShortcutKeyLabel(name) {
    static labels := Map("LCtrl", "左 Ctrl", "RCtrl", "右 Ctrl", "LAlt", "左 Alt",
        "RAlt", "右 Alt", "LShift", "左 Shift", "RShift", "右 Shift", "LWin", "左 Win",
        "RWin", "右 Win", "Space", "空格", "Enter", "Enter", "Backspace", "退格",
        "Up", "↑", "Down", "↓", "Left", "←", "Right", "→", "Minus", "−",
        "Equals", "=", "Comma", ",", "Period", ".", "Slash", "/", "Backslash", "\",
        "Semicolon", ";", "Quote", "'", "Backtick", "``", "LeftBracket", "[", "RightBracket", "]")
    return labels.Has(name) ? labels[name] : name
}

; Keep binding.label/ShortcutKeyLabel stable for stored data and existing callers.
; UI callers use these display helpers to reflect the selected language.
ShortcutDisplayLabel(binding) {
    label := ""
    for key in binding.keys
        label .= (label = "" ? "" : L("＋", " + ")) ShortcutDisplayKeyLabel(key.name)
    return label
}

ShortcutDisplayKeyLabel(name) {
    static english := Map("LCtrl", "Left Ctrl", "RCtrl", "Right Ctrl", "LAlt", "Left Alt",
        "RAlt", "Right Alt", "LShift", "Left Shift", "RShift", "Right Shift",
        "LWin", "Left Win", "RWin", "Right Win", "Space", "Space", "Backspace", "Backspace",
        "PgUp", "Page Up", "PgDn", "Page Down", "Up", "Up", "Down", "Down",
        "Left", "Left", "Right", "Right", "NumpadDot", "Numpad .", "NumpadAdd", "Numpad +",
        "NumpadSub", "Numpad -", "NumpadMult", "Numpad *", "NumpadDiv", "Numpad /",
        "NumpadEnter", "Numpad Enter")
    englishLabel := english.Has(name) ? english[name] : ShortcutKeyLabel(name)
    if RegExMatch(name, "^Numpad[0-9]$")
        englishLabel := "Numpad " SubStr(name, -1)
    return L(ShortcutKeyLabel(name), englishLabel)
}

ShortcutEnsureHeldState(heldState) {
    if !IsObject(heldState)
        throw LocalTypedError(TypeError, "按键释放状态必须是对象。", "Held-key state must be an object.")
    if !heldState.HasOwnProp("keys")
        heldState.keys := []
    if !heldState.HasOwnProp("busy")
        heldState.busy := false
    if !heldState.HasOwnProp("lastError")
        heldState.lastError := ""
}

SendConfiguredShortcut(output, device, binding, heldState) {
    ShortcutEnsureHeldState(heldState)
    if heldState.busy
        throw LocalError("上一次快捷键仍在发送中。", "The previous shortcut is still being sent.")
    if heldState.keys.Length
        throw LocalError("仍有按键等待释放，请先停止映射。", "Some keys still need to be released. Stop the mapping first.")
    if Type(device) != "Integer" || device < 1 || device > 10
        throw LocalTypedError(ValueError, "发送设备无效。", "Invalid output device.")
    ; Reparse the canonical data instead of trusting mutable key/stroke records.
    binding := ParseShortcut(binding.canonical)
    heldState.busy := true
    heldState.lastError := ""
    try {
        modifierCount := binding.keys.Length - 1
        loop modifierCount
            ShortcutPressKey(output, device, binding.keys[A_Index], heldState)
        if modifierCount
            Sleep(100)
        ShortcutPressKey(output, device, binding.keys[binding.keys.Length], heldState)
        Sleep(100)
        ShortcutReleaseLast(output, heldState) ; Main key releases before modifiers.
        if modifierCount
            Sleep(50)
        loop modifierCount
            ShortcutReleaseLast(output, heldState)
    } catch as err {
        heldState.lastError := err.Message
        throw err
    } finally {
        ; OnExit can call the same recovery routine if execution stops during Sleep.
        ReleaseConfiguredKeys(output, heldState)
        heldState.busy := false
    }
    if heldState.keys.Length
        throw LocalError("部分按键尚未释放，请停止映射并重试。",
            "Some keys have not been released. Stop the mapping and try again.")
    return true
}

ShortcutPressKey(output, device, key, heldState) {
    ; Record BEFORE attempting down: the native call may deliver then report failure.
    heldState.keys.Push({device: device, code: key.code, stateUp: key.stateUp, name: key.name})
    output.Send(device, key.code, key.stateDown)
}

ShortcutReleaseLast(output, heldState) {
    key := heldState.keys[heldState.keys.Length]
    output.Send(key.device, key.code, key.stateUp)
    heldState.keys.Pop() ; Keep it recoverable until the release succeeds.
}

ReleaseConfiguredKeys(output, heldState) {
    ShortcutEnsureHeldState(heldState)
    failures := []
    index := heldState.keys.Length
    while index >= 1 {
        key := heldState.keys[index]
        try {
            output.Send(key.device, key.code, key.stateUp)
            heldState.keys.RemoveAt(index)
        } catch as err {
            failures.Push(L("{1}：{2}", "{1}: {2}", ShortcutDisplayKeyLabel(key.name), err.Message))
        }
        index--
    }
    if failures.Length {
        heldState.lastError := ""
        for message in failures
            heldState.lastError .= (heldState.lastError = "" ? "" : L("；", "; ")) message
        return false
    }
    return true
}
