#Include Localization.ahk

; These identifiers stay in the local settings file. Never put them in logs.
GetMachineProfileKey() {
    try {
        guid := RegRead("HKLM\SOFTWARE\Microsoft\Cryptography", "MachineGuid", "")
        return guid != "" ? ProfileDigest("AirKey/machine/v1/" StrLower(guid)) : ""
    }
    return ""
}

ProfileDigest(value) {
    provider := 0, hash := 0
    try {
        if !DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &provider, "Ptr", 0,
            "Str", "Microsoft Enhanced RSA and AES Cryptographic Provider", "UInt", 24, "UInt", 0xF0000000, "Int")
            throw OSError()
        if !DllCall("Advapi32\CryptCreateHash", "Ptr", provider, "UInt", 0x800C, "Ptr", 0, "UInt", 0, "Ptr*", &hash, "Int")
            throw OSError()
        bytes := Buffer(StrPut(value, "UTF-8"))
        size := StrPut(value, bytes, "UTF-8") - 1
        if !DllCall("Advapi32\CryptHashData", "Ptr", hash, "Ptr", bytes, "UInt", size, "UInt", 0, "Int")
            throw OSError()
        digest := Buffer(32), length := 32
        if !DllCall("Advapi32\CryptGetHashParam", "Ptr", hash, "UInt", 2, "Ptr", digest, "UInt*", &length, "UInt", 0, "Int")
            throw OSError()
        result := ""
        loop length
            result .= Format("{:02X}", NumGet(digest, A_Index - 1, "UChar"))
        return result
    } finally {
        if hash
            DllCall("Advapi32\CryptDestroyHash", "Ptr", hash)
        if provider
            DllCall("Advapi32\CryptReleaseContext", "Ptr", provider, "UInt", 0)
    }
}

LoadMicProfile(path, machineKey) {
    if machineKey = ""
        return 0
    try {
        if IniRead(path, "Button", "Version", "0") != "1"
            || IniRead(path, "Button", "Verified", "0") != "1"
            || IniRead(path, "Button", "Machine", "") != machineKey
            return 0
        profile := {source: IniRead(path, "Button", "Source", ""),
            device: IniRead(path, "Button", "Device", ""), usagePage: 12, usage: 1,
            outputHid: IniRead(path, "Button", "OutputHardwareId", ""),
            outputId: Integer(IniRead(path, "Button", "OutputId", "0")),
            topology: IniRead(path, "Button", "Topology", ""),
            shortcut: IniRead(path, "Button", "Shortcut", "")}
        return ValidMicProfile(profile) ? profile : 0
    }
    return 0
}

ValidMicProfile(profile) {
    try return (profile.source = "key" || (profile.source = "hid" && profile.device != ""))
        && profile.usagePage = 12 && profile.usage = 1 && profile.outputHid != ""
        && profile.outputId >= 1 && profile.outputId <= 10 && profile.shortcut != ""
        && RegExMatch(profile.topology, "^[A-F0-9]{64}$")
    return false
}

SaveMicProfile(path, profile, machineKey) {
    if !ValidMicProfile(profile) || !RegExMatch(machineKey, "^[A-F0-9]{64}$")
        throw LocalError("无法保存此电脑的设置，请重新识别按钮。", "Could not save this computer's setup. Please set up the button again.")
    temporary := path ".setup-" A_TickCount "-" Random(100000, 999999) ".tmp"
    try {
        if FileExist(path)
            FileCopy(path, temporary)
        IniWrite(0, temporary, "Button", "Verified")
        values := Map("Version", 1, "Machine", machineKey, "Source", profile.source,
            "Device", profile.device, "OutputHardwareId", profile.outputHid,
            "OutputId", profile.outputId, "Topology", profile.topology, "Shortcut", profile.shortcut)
        for key, value in values
            IniWrite(value, temporary, "Button", key)
        IniWrite(profile.outputHid, temporary, "Mapping", "HardwareId")
        IniWrite(profile.shortcut, temporary, "Mapping", "Shortcut")
        IniWrite(1, temporary, "Mapping", "EnableOnLaunch")
        IniWrite(1, temporary, "Button", "Verified")
        if !DllCall("Kernel32\MoveFileExW", "Str", temporary, "Str", path, "UInt", 0x9, "Int")
            throw OSError()
    } finally {
        if FileExist(temporary)
            try FileDelete(temporary)
    }
}

InvalidateMicProfile(path) {
    ; A single flag invalidates the old profile without deleting unrelated settings.
    IniWrite(0, path, "Button", "Verified")
}

ProfileTopology(devices) {
    value := ""
    for device in devices
        value .= device.id ":" StrLen(device.hid) ":" device.hid "`n"
    return ProfileDigest(value)
}

FindProfileOutput(devices, profile) {
    if !IsObject(profile)
        return 0
    matches := []
    for index, device in devices
        if device.hid = profile.outputHid
            matches.Push(index)
    if matches.Length = 1
        return matches[1]
    if matches.Length > 1 && ProfileTopology(devices) = profile.topology {
        for index in matches
            if devices[index].id = profile.outputId
                return index
    }
    return 0
}

GetOutputCandidates(devices, savedHid := "") {
    candidates := [], added := Map()
    ; Prefer the previous output, then built-in/USB/Bluetooth, but try every valid
    ; connection once instead of repeatedly selecting the same first candidate.
    loop 5 {
        group := A_Index
        for index, device in devices {
            if added.Has(device.id) || device.id < 1 || device.id > 10 || device.hid = ""
                continue
            if (group = 1 && savedHid != "" && device.hid = savedHid)
                || (group = 2 && SubStr(device.hid, 1, 5) = "ACPI\")
                || (group = 3 && SubStr(device.hid, 1, 8) = "HID\VID_")
                || (group = 4 && InStr(device.hid, "Dev_VID")) || group = 5 {
                candidates.Push(index)
                added[device.id] := true
            }
        }
    }
    return candidates
}
