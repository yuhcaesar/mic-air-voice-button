#Requires AutoHotkey v2.0 64-bit
#SingleInstance Off
#NoTrayIcon
; Run only the real mode-selection entry point and its two pure helpers.
; Main startup, native modules, windows, hooks and key output are never loaded.
testDir := A_Args.Length ? A_Args[1] : A_ScriptDir "\.results\main-mode"
DirCreate(testDir)
try {
    mainSource := FileRead(A_ScriptDir "\..\Main.ahk", "UTF-8")
    profileSource := FileRead(A_ScriptDir "\..\MachineProfile.ahk", "UTF-8")
    functions := ExtractMainModeFunction(mainSource, "SelectMicMode") "`r`n"
        . ExtractMainModeFunction(profileSource, "MicProfileMode") "`r`n"
    if !RegExMatch(profileSource, "m)^ValidMicMode\([^\r\n]*\) => [^\r\n]+", &validMode)
        throw Error("Pure mode validator changed; review the extraction boundary")
    functions .= validMode[0] "`r`n"
    harness := '
    (
    #Requires AutoHotkey v2.0 64-bit
    #SingleInstance Off
    #NoTrayIcon
    global S := 0, ConfigPath := A_ScriptDir "\fixture.ini"
    global Requests := [], Ready := true, SetupActive := false, BeforeConfig := ""
    report := "Main mode tests - extracted production functions and mocks only.``r``n"
    try {
        FileOpen(ConfigPath, "w", "UTF-8").Write("[UI]``r``nLanguage=en``r``n[Mapping]``r``nShortcut=RAlt+Space``r``nEnableOnLaunch=1``r``n[Button]``r``nVerified=1``r``nVolumeVerified=1``r``nSource=key``r``nMode=standard``r``n")
        BeforeConfig := FileRead(ConfigPath)
        for mode in ["standard", "compatibility"] {
            ResetModeFixture()
            SelectMicMode(mode)
            Check(Requests.Length = 1 && Requests[1] = mode, "First-use selection requests the chosen setup")
            Check(S.profile = 0 && S.selected = 0 && !S.enabled, "First-use request does not install an active profile or enable mapping")
            CheckUnchangedConfig()
        }
        report .= "PASS first-use Standard and Compatibility request their own setup without activating or saving a profile.``r``n"

        for source in ["key", "registered", "hid"] {
            for enabled in [false, true] {
                ResetModeFixture(source, enabled)
                oldProfile := S.profile, oldBinding := S.binding
                targetMode := source = "hid" ? "standard" : "compatibility"
                SelectMicMode(targetMode)
                Check(Requests.Length = 1 && Requests[1] = targetMode, "Opposite mode requests a setup")
                Check(S.profile = oldProfile && S.profile.source = source && S.profile.volumeVerified,
                    "Requested mode does not replace or mutate the old verified profile")
                Check(S.enabled = enabled && S.selected = 1 && S.binding = oldBinding && S.binding.canonical = "RAlt+Space",
                    "Entry point leaves current enable state, selected connection and shortcut unchanged")
                CheckUnchangedConfig()
            }
        }
        report .= "PASS switching from every persisted source requests verification without changing current profile, enabled state, connection, shortcut or INI bytes.``r``n"

        for source in ["key", "registered", "hid"] {
            ResetModeFixture(source, true)
            oldProfile := S.profile
            currentMode := source = "hid" ? "compatibility" : "standard"
            SelectMicMode(currentMode)
            Check(!Requests.Length && S.profile = oldProfile && S.enabled, "Clicking a verified connected current mode is a no-op")
            S.selected := 0
            SelectMicMode(currentMode)
            Check(Requests.Length = 1 && Requests[1] = currentMode, "Missing connection allows current mode to be identified again")
            Check(S.profile = oldProfile && S.selected = 0 && S.enabled, "Re-identification request keeps the old state until controller handles it")
            CheckUnchangedConfig()
        }
        report .= "PASS repeated current-mode selection does nothing; losing its connection permits re-identification for key, registered and HID profiles.``r``n"

        for gate in ["busy", "maintenance", "pendingReboot", "editing", "held", "setup", "driver"] {
            ResetModeFixture("key", true)
            if gate = "held"
                S.held.keys.Push({code: 0x38, e0: true})
            else if gate = "setup"
                SetupActive := true
            else if gate = "driver"
                Ready := false
            else
                S.%gate% := true
            oldProfile := S.profile
            SelectMicMode("compatibility")
            Check(!Requests.Length && S.profile = oldProfile && S.profile.source = "key" && S.enabled,
                "A guarded state cannot start setup or change the current profile: " gate)
            CheckUnchangedConfig()
        }
        for invalid in ["", "automatic", "STANDARD", "Compatibility", "standard ", "hid", 0, 1, {}, []] {
            ResetModeFixture()
            SelectMicMode(invalid)
            Check(!Requests.Length && S.profile = 0 && !S.enabled, "Invalid mode cannot request setup")
            CheckUnchangedConfig()
        }
        report .= "PASS busy, maintenance, pending restart, editing, held keys, active setup, unavailable driver and invalid modes block switching.``r``n"
        FileOpen(A_ScriptDir "\report.txt", "w", "UTF-8").Write(report)
        ExitApp(0)
    } catch as err {
        FileOpen(A_ScriptDir "\report.txt", "w", "UTF-8").Write(report "FAIL: " err.Message "``r``n" err.Stack)
        ExitApp(1)
    }

    ResetModeFixture(source := "", enabled := false) {
        global S, Requests, Ready, SetupActive
        S := {profile: source = "" ? 0 : {source: source, volumeVerified: true, shortcut: "RAlt+Space"},
            selected: source = "" ? 0 : 1, enabled: enabled, busy: false, maintenance: false,
            pendingReboot: false, editing: false, held: {keys: []}, binding: {canonical: "RAlt+Space"}}
        Requests := [], Ready := true, SetupActive := false
    }
    BeginMicSetupMode(mode) {
        global Requests
        Requests.Push(mode)
    }
    DriverReady() {
        global Ready
        return Ready
    }
    MicSetupActive() {
        global SetupActive
        return SetupActive
    }
    CheckUnchangedConfig() {
        global ConfigPath, BeforeConfig
        Check(FileRead(ConfigPath) = BeforeConfig, "Mode selection never writes configuration before verification")
    }
    Check(condition, message) {
        if !condition
            throw Error(message)
    }
    )'
    workerPath := testDir "\worker.ahk"
    FileOpen(workerPath, "w", "UTF-8").Write(harness "`r`n" functions)
    ExitApp(RunWait('"' A_AhkPath '" /ErrorStdOut=UTF-8 "' workerPath '"', testDir, "Hide"))
} catch as err {
    FileOpen(testDir "\report.txt", "w", "UTF-8").Write("FAIL launcher: " err.Message "`r`n" err.Stack)
    ExitApp(2)
}

ExtractMainModeFunction(source, name) {
    ; Top-level closing braces are unindented. Extract one definition only;
    ; never include adjacent startup statements, includes or unrelated helpers.
    if !RegExMatch(source, "ms)^" name "\([^\r\n]*\) \{\r?\n.*?^\}\r?$", &definition)
        throw Error("Function boundary changed: " name)
    return definition[0]
}
