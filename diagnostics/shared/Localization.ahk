; AHK v2. Including this module performs no file I/O or application startup.
; N stores bilingual templates; Text renders them using the current language.
; Nested N arguments remain dynamic when the user changes the language.
class AppLanguage {
    static Current := "zh"
}

LoadAppLanguage(configPath) {
    code := "zh"
    try code := IniRead(configPath, "UI", "Language", "zh")
    AppLanguage.Current := (code == "zh" || code == "en") ? code : "zh"
    return AppLanguage.Current
}

SaveAppLanguage(code, configPath) {
    if Type(code) != "String" || !(code == "zh" || code == "en")
        throw LocalTypedError(ValueError, "不支持的界面语言。", "Unsupported interface language.")
    ; Update the in-memory selection only after the write succeeds. IniWrite
    ; changes this single key and preserves the rest of the configuration.
    IniWrite(code, configPath, "UI", "Language")
    AppLanguage.Current := code
    return code
}

L(zh, en, args*) {
    values := []
    for value in args
        values.Push(Text(value))
    return Format(AppLanguage.Current == "en" ? en : zh, values*)
}

N(zh, en, args*) {
    return AppLocalizedMessage(zh, en, args)
}

Text(value) {
    if value is AppLocalizedMessage
        return value.Render()
    return value
}

; Keep Message usable in logs while preserving both templates for later UI
; rendering. Typed errors retain their class so existing catch clauses work.
LocalError(zh, en, args*) {
    return LocalTypedError(Error, zh, en, args*)
}

LocalTypedError(errorClass, zh, en, args*) {
    err := errorClass(L(zh, en, args*))
    err.localizedMessage := N(zh, en, args*)
    return err
}

ErrorText(err) {
    return err.HasOwnProp("localizedMessage") ? err.localizedMessage : err.Message
}

class AppLocalizedMessage {
    __New(zh, en, args) {
        this.zh := zh
        this.en := en
        this.args := args
    }
    Render() {
        return L(this.zh, this.en, this.args*)
    }
}
