; DriverManager.ahk — AHK v2 x64. No action is performed merely by including this file.
; GetDriverStatus() returns {installed, running, pending, description, bootId,
;   partial, known, hasComponents, serviceConflict,
;   keyboardRunning, mouseRunning, keyboardFilters, mouseFilters, detail}.
; installed means both expected services and both Class UpperFilters are configured.
; running means WMI positively reports BOTH kernel drivers Running + Started.
; pending is only inferred for removed configuration with a driver still running.
; Installed-but-not-running is ambiguous (new install OR failed load), so pending=false.
; The UI should persist a successful operation and bootId to require its next reboot.
; RunDriverOperation("install"|"uninstall", absoluteInstallerPath) returns
;   {ok, cancelled, exitCode, message, needsReboot}. exitCode=-1 means not run.
; description and message are bilingual N values; render them with Text().
; Only the pinned official installer is elevated; no registry writes, file deletions,
; input filters, key sends, automatic restart, or autostart are performed here.
; SHA256File(path) returns uppercase SHA-256, or throws on failure.

; Localization.ahk is included explicitly by the diagnostic entry point.

GetDriverStatus() {
    result := {installed: false, running: false, pending: false, description: "",
        bootId: "", partial: false, known: false,
        hasComponents: false, serviceConflict: false, keyboardRunning: false,
        mouseRunning: false, keyboardFilters: "", mouseFilters: "", detail: ""}
    try {
        keyRoot := "HKLM\SYSTEM\CurrentControlSet\Control\Class\"
        result.keyboardFilters := RegRead(keyRoot "{4d36e96b-e325-11ce-bfc1-08002be10318}", "UpperFilters", "")
        result.mouseFilters := RegRead(keyRoot "{4d36e96f-e325-11ce-bfc1-08002be10318}", "UpperFilters", "")
        keyboard := DriverReadService("keyboard")
        mouse := DriverReadService("mouse")
        keyFilter := DriverHasFilter(result.keyboardFilters, "keyboard")
        mouseFilter := DriverHasFilter(result.mouseFilters, "mouse")
        result.serviceConflict := keyboard.conflict || mouse.conflict
        result.hasComponents := keyboard.present || mouse.present || keyFilter || mouseFilter
        result.installed := keyboard.expected && mouse.expected && keyFilter && mouseFilter
        result.partial := result.hasComponents && !result.installed
        wmi := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
        for driver in wmi.ExecQuery("SELECT Name, State, Started FROM Win32_SystemDriver WHERE Name='keyboard' OR Name='mouse'") {
            isRunning := driver.State = "Running" && driver.Started
            if driver.Name = "keyboard"
                result.keyboardRunning := !!isRunning
            else if driver.Name = "mouse"
                result.mouseRunning := !!isRunning
        }
        result.running := result.keyboardRunning && result.mouseRunning && !result.serviceConflict
        result.pending := !result.hasComponents && (result.keyboardRunning || result.mouseRunning)
        result.known := true
        try {
            for os in wmi.ExecQuery("SELECT LastBootUpTime FROM Win32_OperatingSystem") {
                result.bootId := os.LastBootUpTime ""
                break
            }
        } catch as err {
            result.detail := L("无法读取启动时间：{1}", "Unable to read the boot time: {1}", err.Message)
        }
        if result.serviceConflict {
            result.description := N("检测到同名的其他驱动，请勿覆盖。", "Another driver uses the same service name. Do not overwrite it.")
        } else if result.pending {
            result.description := N("驱动已移除配置，重启电脑后完成恢复。", "The driver configuration has been removed. Restart your computer to finish restoring normal operation.")
        } else if result.partial {
            result.description := N("驱动配置不完整，可重新安装或移除。", "The driver configuration is incomplete. Reinstall or remove the driver.")
        } else if result.installed && result.running {
            result.description := N("驱动已安装并正在运行。", "The driver is installed and running.")
        } else if result.installed {
            result.description := N("驱动已安装但尚未加载；若刚安装，请重启电脑。", "The driver is installed but has not loaded. If you just installed it, restart your computer.")
        } else {
            result.description := N("驱动尚未安装。", "The driver is not installed.")
        }
    } catch as err {
        result.description := N("暂时无法确认驱动状态。", "Unable to confirm the driver status right now.")
        result.detail := err.Message
    }
    return result
}

DriverReadService(name) {
    root := "HKLM\SYSTEM\CurrentControlSet\Services\" name
    serviceType := RegRead(root, "Type", -1)
    imagePath := RegRead(root, "ImagePath", "")
    present := serviceType != -1 || imagePath != ""
    ; The official installer leaves ImagePath absent; Windows uses the default
    ; System32\drivers\<service>.sys. Explicit paths must match that location.
    normalized := StrLower(Trim(imagePath, '" '))
    expectedPath := "\systemroot\system32\drivers\" name ".sys"
    fullPath := StrLower(A_WinDir) "\system32\drivers\" name ".sys"
    pathOK := normalized = "" || normalized = expectedPath || normalized = fullPath
        || normalized = "\??\" fullPath || normalized = "system32\drivers\" name ".sys"
    expected := present && serviceType = 1 && pathOK
    return {present: present, expected: expected, conflict: present && !expected}
}

DriverHasFilter(filterList, name) {
    for entry in StrSplit(filterList, "`n", "`r")
        if Trim(entry) = name
            return true
    return false
}

RunDriverOperation(action, installerPath) {
    static busy := false
    result := {ok: false, cancelled: false, exitCode: -1, message: "",
        needsReboot: false}
    if action != "install" && action != "uninstall" {
        result.message := N("不支持的驱动操作。", "Unsupported driver operation.")
        return result
    }
    if busy {
        result.message := N("另一个驱动操作仍在进行，请稍候。", "Another driver operation is still in progress. Please wait.")
        return result
    }
    if !RegExMatch(installerPath, "i)^[a-z]:\\") || InStr(installerPath, '"')
        || InStr(installerPath, "`n") || InStr(installerPath, "`r") {
        result.message := N("安装器路径无效。", "The installer path is invalid.")
        return result
    }
    busy := true
    handle := 0
    try {
        before := GetDriverStatus()
        if !before.known
            throw DriverOperationError("无法确认当前驱动配置，操作未启动。{1}",
                "Unable to confirm the current driver configuration. The operation was not started. {1}", before.detail)
        if before.serviceConflict
            throw DriverOperationError("keyboard 或 mouse 服务属于其他驱动，操作未启动。",
                "The keyboard or mouse service belongs to another driver. The operation was not started.")
        ; Hold a read-only handle denying write/delete until elevation finishes.
        ; This prevents replacement of the checked installer between hash and launch.
        handle := DriverOpenReadLocked(installerPath)
        digest := DriverHashHandle(handle)
        if digest != "E137863A79DA797F08E7A137280FF2A123809044A888FD75CE9C973198915ABE"
            throw DriverOperationError("安装器校验失败，未运行。请重新获取完整工具包。",
                "The installer failed verification and was not run. Download the complete package again.")
        SplitPath(installerPath, , &installerDir)
        try {
            result.exitCode := RunWait('*RunAs "' installerPath '" /' action, installerDir, "Hide")
        } catch as err {
            nativeErrorCode := err is OSError ? err.Number : A_LastError
            result.cancelled := nativeErrorCode = 1223
            result.message := result.cancelled
                ? N("已取消管理员授权，未执行驱动操作。", "Administrator authorization was cancelled. No driver operation was performed.")
                : N("安装器未能启动：{1}", "The installer could not start: {1}", err.Message)
            return result
        }
        after := GetDriverStatus()
        ; The official utility requests a restart. Do not promise immediate unload.
        result.needsReboot := result.exitCode = 0
        if result.exitCode != 0 {
            result.message := N("驱动操作未成功（返回码 {1}）。请查看驱动状态。",
                "The driver operation failed (exit code {1}). Check the driver status.", result.exitCode)
            return result
        }
        if !after.known {
            result.message := N("安装器已退出，但无法核实结果。请重启后重新查看状态。",
                "The installer has exited, but the result could not be verified. Restart your computer and check the status again.")
            return result
        }
        missing := DriverMissingOtherFilters(before.keyboardFilters, after.keyboardFilters, "keyboard")
            . DriverMissingOtherFilters(before.mouseFilters, after.mouseFilters, "mouse")
        if missing != "" {
            result.message := N("原有键鼠驱动配置发生变化：{1}。请保留日志并检查。",
                "Existing input filters changed: {1}. Keep the log and check the configuration.", missing)
            return result
        }
        expectedState := action = "install" ? after.installed : !after.hasComponents
        if !expectedState {
            result.message := N("安装器已退出，但驱动配置未达到预期。请重启后检查状态。",
                "The installer has exited, but the driver configuration is not as expected. Restart your computer and check the status.")
            return result
        }
        result.ok := true
        result.message := action = "install"
            ? N("驱动安装完成，请重启电脑后启用映射。", "The driver is installed. Restart your computer before enabling the mapping.")
            : N("驱动移除完成，请重启电脑完成恢复。", "The driver has been removed. Restart your computer to finish restoring normal operation.")
    } catch as err {
        result.message := err.HasOwnProp("localizedMessage") ? err.localizedMessage : N("{1}", "{1}", err.Message)
    } finally {
        if handle
            DllCall("Kernel32\CloseHandle", "Ptr", handle)
        busy := false
    }
    return result
}

; Keep locally generated errors translatable after the operation has finished.
; Raw Windows diagnostics remain in the language supplied by Windows.
DriverOperationError(zh, en, args*) {
    err := Error(L(zh, en, args*))
    err.localizedMessage := N(zh, en, args*)
    return err
}

DriverMissingOtherFilters(before, after, ownFilter) {
    missing := ""
    for entry in StrSplit(before, "`n", "`r") {
        entry := Trim(entry)
        if entry != "" && entry != ownFilter && !DriverHasFilter(after, entry)
            missing .= (missing = "" ? "" : "、") entry
    }
    return missing
}

SHA256File(path) {
    handle := DriverOpenReadLocked(path)
    try return DriverHashHandle(handle)
    finally DllCall("Kernel32\CloseHandle", "Ptr", handle)
}

DriverOpenReadLocked(path) {
    handle := DllCall("Kernel32\CreateFileW", "Str", path, "UInt", 0x80000000,
        "UInt", 1, "Ptr", 0, "UInt", 3, "UInt", 0x08000000, "Ptr", 0, "Ptr")
    if handle = -1
        throw OSError()
    return handle
}

DriverHashHandle(handle) {
    provider := 0
    hash := 0
    try {
        if !DllCall("Advapi32\CryptAcquireContextW", "Ptr*", &provider, "Ptr", 0,
            "Str", "Microsoft Enhanced RSA and AES Cryptographic Provider", "UInt", 24,
            "UInt", 0xF0000000, "Int")
            throw OSError()
        if !DllCall("Advapi32\CryptCreateHash", "Ptr", provider, "UInt", 0x800C,
            "Ptr", 0, "UInt", 0, "Ptr*", &hash, "Int")
            throw OSError()
        chunk := Buffer(65536)
        loop {
            readBytes := 0
            if !DllCall("Kernel32\ReadFile", "Ptr", handle, "Ptr", chunk,
                "UInt", chunk.Size, "UInt*", &readBytes, "Ptr", 0, "Int")
                throw OSError()
            if !readBytes
                break
            if !DllCall("Advapi32\CryptHashData", "Ptr", hash, "Ptr", chunk,
                "UInt", readBytes, "UInt", 0, "Int")
                throw OSError()
        }
        digest := Buffer(32)
        length := digest.Size
        if !DllCall("Advapi32\CryptGetHashParam", "Ptr", hash, "UInt", 2,
            "Ptr", digest, "UInt*", &length, "UInt", 0, "Int")
            throw OSError()
        hex := ""
        loop length
            hex .= Format("{:02X}", NumGet(digest, A_Index - 1, "UChar"))
        return hex
    } finally {
        if hash
            DllCall("Advapi32\CryptDestroyHash", "Ptr", hash)
        if provider
            DllCall("Advapi32\CryptReleaseContext", "Ptr", provider, "UInt", 0)
    }
}
