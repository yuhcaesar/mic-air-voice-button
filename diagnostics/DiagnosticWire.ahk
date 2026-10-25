; Fixed, privacy-filtered IPC between this app and its own short-lived workers.
; No general object serializer: arbitrary strings, device paths and text are discarded.
DiagCountNames() => ["legacyHotkey", "wmHotkey", "registeredHotkey", "hookDown", "hookUp", "llDown", "llUp", "rawKeyboardDown", "rawKeyboardUp", "hidDown", "hidUp", "eligible", "rearmed", "sendAttempt"]
DiagGateNames() => ["disabled", "unarmed", "busy", "noOutput", "maintenance", "editing", "heldShortcut"]
DiagGet(object, name, fallback := 0) => IsObject(object) && object.HasOwnProp(name) ? object.%name% : fallback
DiagNumber(value, maximum := 1000000) {
    try return Max(0, Min(maximum, Integer(value)))
    return 0
}
DiagWord(value, fallback := "unknown") => Type(value) = "String" && RegExMatch(value, "^[A-Za-z0-9_-]{1,40}$") ? value : fallback
DiagNow() => DllCall("Kernel32\GetTickCount64", "UInt64")
DiagDeadlineFresh(deadline, now) {
    distance := (deadline - now) & 0xFFFFFFFF
    return deadline != 0 && distance > 0 && distance <= 3000
}

DiagWriteSnapshot(path, snapshot, reason := "running", cleanupOk := false) {
    wireText := "format=1`nphase=" DiagWord(snapshot.phaseId) "`nreason=" DiagWord(reason)
    for field in ["started", "active", "completed", "durationMs", "modifierMask"]
        wireText .= "`n" field "=" DiagNumber(DiagGet(snapshot, field))
    wireText .= "`ncleanupOk=" (cleanupOk ? 1 : 0)
    wireText .= "`nlegacyRegisteredType=" DiagWord(DiagGet(snapshot, "legacyRegisteredType", "unknown"))
    wireText .= "`neventDrops=" DiagNumber(DiagGet(snapshot, "eventDrops"))
    registration := DiagGet(snapshot, "registration", {})
    for field in ["attempted", "ok", "errorCode"]
        wireText .= "`nreg_" field "=" DiagNumber(DiagGet(registration, field))
    for field in DiagCountNames()
        wireText .= "`ncount_" field "=" DiagNumber(DiagGet(DiagGet(snapshot, "counts", {}), field))
    for field in DiagGateNames()
        wireText .= "`ngate_" field "=" DiagNumber(DiagGet(DiagGet(snapshot, "gates", {}), field))
    devices := DiagGet(snapshot, "devices", [])
    wireText .= "`ndeviceCount=" Min(devices.Length, 8)
    errors := DiagGet(snapshot, "errors", [])
    wireText .= "`nerrorCount=" Min(errors.Length, 16)
    loop Min(errors.Length, 16) {
        errorRecord := errors[A_Index]
        wireText .= "`nerror" A_Index "_stage=" DiagWord(DiagGet(errorRecord, "stage", "unknown"))
        wireText .= "`nerror" A_Index "_code=" DiagWord(DiagGet(errorRecord, "code", "unknown"))
        wireText .= "`nerror" A_Index "_win32=" DiagNumber(DiagGet(errorRecord, "win32"))
    }
    events := DiagGet(snapshot, "events", [])
    wireText .= "`neventCount=" Min(events.Length, 64)
    loop Min(events.Length, 64) {
        event := events[A_Index]
        wireText .= "`nevent" A_Index "_source=" DiagWord(DiagGet(event, "source", "unknown"))
        for field in ["down", "ms", "flags"]
            wireText .= "`nevent" A_Index "_" field "=" DiagNumber(DiagGet(event, field))
    }
    wireText .= "`nend=1`n"
    snapshotFile := FileOpen(path ".tmp", "w", "UTF-8")
    snapshotFile.Write(wireText)
    snapshotFile.Close()
    if !DllCall("Kernel32\MoveFileExW", "Str", path ".tmp", "Str", path, "UInt", 1, "Int")
        throw Error("SNAPSHOT_WRITE")
}

DiagReadSnapshot(path, expectedPhase) {
    if !FileExist(path) || FileGetSize(path) > 32768
        return 0
    values := Map()
    for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        if RegExMatch(line, "^([A-Za-z0-9_]+)=([A-Za-z0-9_-]*)$", &part)
            values[part[1]] := part[2]
    }
    read := (key, fallback := "0") => values.Has(key) ? values[key] : fallback
    if read("format") != "1" || read("end") != "1" || read("phase") != expectedPhase
        return 0
    result := {phaseId: expectedPhase, workerEndReason: read("reason", "unknown"),
        cleanupOk: read("cleanupOk") = "1", workerExited: false, userConfirmedPresses: false,
        targetPresses: 2, registration: {}, counts: {}, gates: {}, devices: [], errors: [], events: []}
    for field in ["started", "active", "completed", "durationMs", "modifierMask"]
        result.%field% := DiagNumber(read(field))
    result.legacyRegisteredType := DiagWord(read("legacyRegisteredType", "unknown"))
    result.eventDrops := DiagNumber(read("eventDrops"))
    for field in ["attempted", "ok", "errorCode"]
        result.registration.%field% := DiagNumber(read("reg_" field))
    for field in DiagCountNames()
        result.counts.%field% := DiagNumber(read("count_" field))
    for field in DiagGateNames()
        result.gates.%field% := DiagNumber(read("gate_" field))
    loop DiagNumber(read("deviceCount"), 8)
        result.devices.Push({id: "device" A_Index})
    loop DiagNumber(read("errorCount"), 16) {
        prefix := "error" A_Index "_"
        result.errors.Push({stage: DiagWord(read(prefix "stage", "unknown")),
            code: DiagWord(read(prefix "code", "unknown")), win32: DiagNumber(read(prefix "win32"))})
    }
    loop DiagNumber(read("eventCount"), 64) {
        prefix := "event" A_Index "_"
        result.events.Push({source: DiagWord(read(prefix "source", "unknown")), down: DiagNumber(read(prefix "down"), 1),
            ms: DiagNumber(read(prefix "ms")), flags: DiagNumber(read(prefix "flags"), 255)})
    }
    return result
}

class DiagnosticGuardedOutput {
    __New(native, canSend) {
        this.native := native
        this.canSend := canSend
    }
    Send(device, code, state) {
        if !(state & 1) && !this.canSend.Call()
            throw Error("FOCUS_LOST")
        this.native.Send(device, code, state)
    }
}

; CreateProcess returns the process handle atomically with launch. This avoids
; a Run/OpenProcess gap where a child could survive without an owned handle.
DiagLaunchChild(application, command, workingDirectory) {
    startup := Buffer(104, 0), processInfo := Buffer(24, 0)
    NumPut("UInt", 104, startup, 0)
    NumPut("UInt", 1, startup, 60) ; STARTF_USESHOWWINDOW, SW_HIDE (zero at 64).
    commandBuffer := Buffer(StrPut(command, "UTF-16") * 2, 0)
    StrPut(command, commandBuffer, "UTF-16")
    if !DllCall("Kernel32\CreateProcessW", "Str", application, "Ptr", commandBuffer,
        "Ptr", 0, "Ptr", 0, "Int", false, "UInt", 0, "Ptr", 0,
        "Str", workingDirectory, "Ptr", startup, "Ptr", processInfo, "Int")
        throw Error("WORKER_CREATE")
    process := NumGet(processInfo, 0, "Ptr"), threadHandle := NumGet(processInfo, 8, "Ptr")
    DllCall("Kernel32\CloseHandle", "Ptr", threadHandle)
    return process
}
