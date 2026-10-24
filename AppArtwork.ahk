; Only discovers an icon from the user's installed Doubao IME. Nothing is copied,
; extracted, downloaded or written. The public app bundles its own fallback art.
FindDoubaoIcon() {
    roots := []
    for variable in ["ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"] {
        base := EnvGet(variable)
        if base != ""
            roots.Push(base "\DoubaoIME")
    }
    localAppData := EnvGet("LOCALAPPDATA")
    if localAppData != ""
        roots.Push(localAppData "\Programs\DoubaoIME", localAppData "\DoubaoIME")
    for root in roots {
        icon := FindDoubaoIconInFolder(root)
        if icon != ""
            return icon
    }

    ; Custom installation paths: read only the standard uninstall metadata.
    ; Do not execute or interpret UninstallString/DisplayIcon command lines.
    for uninstallRoot in [
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"] {
        try {
            Loop Reg, uninstallRoot, "K" {
                entry := uninstallRoot "\" A_LoopRegName
                displayName := RegRead(entry, "DisplayName", "")
                if !(InStr(displayName, "豆包输入法") || RegExMatch(displayName, "i)doubao[ _-]*ime"))
                    continue
                icon := FindDoubaoIconInFolder(RegRead(entry, "InstallLocation", ""))
                if icon != ""
                    return icon
            }
        }
    }
    return ""
}

FindDoubaoIconInFolder(folder) {
    if Type(folder) != "String" || folder = ""
        return ""
    ; REG_EXPAND_SZ is allowed, but only a local drive path is searched.
    required := DllCall("Kernel32\ExpandEnvironmentStringsW", "Str", folder, "Ptr", 0, "UInt", 0, "UInt")
    if !required || required > 32768
        return ""
    expanded := Buffer(required * 2)
    if !DllCall("Kernel32\ExpandEnvironmentStringsW", "Str", folder, "Ptr", expanded, "UInt", required, "UInt")
        return ""
    folder := RTrim(Trim(StrGet(expanded), ' "'), "\/")
    if !RegExMatch(folder, "i)^[a-z]:\\")
        return ""
    icon := folder "\doubao_logo.ico"
    try {
        attributes := FileExist(icon)
        if attributes != "" && !InStr(attributes, "D")
            return icon
    }
    return ""
}
