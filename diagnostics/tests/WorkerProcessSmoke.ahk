#Requires AutoHotkey v2.0 64-bit
#Warn All, StdOut
#SingleInstance Off
#NoTrayIcon
#Include ..\DiagnosticWire.ahk
; Opt-in native integration: baseline Raw Input only, no physical/synthetic key
; action, no driver access/changes, and no normal settings reads or writes.
global Smoke := 0
try {
    if A_Args.Length != 2
        throw Error("Specify the compiled EXE and an isolated report directory")
    Smoke := WorkerSmoke(A_Args[1], A_Args[2])
    Persistent()
} catch as err {
    FileAppend("FAIL " err.Message, "*", "UTF-8")
    ExitApp(1)
}
class WorkerSmoke {
    __New(exe, directory) {
        this.exe := exe, this.directory := directory, this.handle := 0
        this.window := Gui("+ToolWindow", "AirKey worker test")
        this.caseIndex := 0, this.done := false, this.report := "Compiled baseline worker lifecycle; no key sends or driver/config changes.`r`n"
        this.pid := DllCall("Kernel32\GetCurrentProcessId", "UInt")
        this.workDir := A_Temp "\AirKey-Diagnostic-Smoke-" this.pid
        DirCreate(this.workDir), DirCreate(directory)
        this.timer := ObjBindMethod(this, "Poll")
        OnExit(ObjBindMethod(this, "Cleanup"))
        this.Next()
        SetTimer(this.timer, 50)
    }
    Lease() {
        DllCall("User32\SetPropW", "Ptr", this.window.Hwnd, "Str", "AirKey.Diagnostic.OwnerPID", "Ptr", this.pid)
        DllCall("User32\SetPropW", "Ptr", this.window.Hwnd, "Str", "AirKey.Diagnostic.Deadline", "Ptr", (DllCall("Kernel32\GetTickCount", "UInt") + 2500) & 0xFFFFFFFF)
    }
    Next() {
        this.caseIndex++, this.action := false, this.snapshot := 0, this.born := DiagNow()
        this.path := this.workDir "\case" this.caseIndex ".txt"
        this.Lease()
        command := '"' this.exe '" --worker baseline "' this.path '" ' this.window.Hwnd " " this.pid " Space"
        this.handle := DiagLaunchChild(this.exe, command, A_ScriptDir)
    }
    Poll(*) {
        try {
            if !(this.caseIndex = 2 && this.action)
                this.Lease()
            result := DiagReadSnapshot(this.path, "baseline")
            if IsObject(result)
                this.snapshot := result
            if IsObject(result) && result.started && !this.action && DiagNow() - this.born > 500 {
                this.action := true
                if this.caseIndex = 1
                    FileAppend("stop", this.path ".stop", "UTF-8")
                else
                    DllCall("User32\RemovePropW", "Ptr", this.window.Hwnd, "Str", "AirKey.Diagnostic.Deadline")
            }
            if DllCall("Kernel32\WaitForSingleObject", "Ptr", this.handle, "UInt", 0, "UInt") = 0 {
                final := DiagReadSnapshot(this.path, "baseline")
                expected := this.caseIndex = 1 ? "confirmed" : "parent_lost"
                if !IsObject(final) || final.workerEndReason != expected || !final.cleanupOk
                    throw Error("Worker did not exit with clean expected result: " expected)
                DllCall("Kernel32\CloseHandle", "Ptr", this.handle), this.handle := 0
                this.report .= "PASS " expected ": child exited, Raw Input removed, final snapshot written.`r`n"
                if this.caseIndex = 1
                    this.Next()
                else {
                    FileOpen(this.directory "\report.txt", "w", "UTF-8").Write(this.report)
                    ExitApp(0)
                }
            } else if DiagNow() - this.born > 8000
                throw Error("Worker timeout")
        } catch as err {
            FileOpen(this.directory "\report.txt", "w", "UTF-8").Write(this.report "FAIL " err.Message)
            ExitApp(1)
        }
    }
    Cleanup(*) {
        SetTimer(this.timer, 0)
        if this.handle {
            DllCall("Kernel32\TerminateProcess", "Ptr", this.handle, "UInt", 3)
            DllCall("Kernel32\WaitForSingleObject", "Ptr", this.handle, "UInt", 1500)
            DllCall("Kernel32\CloseHandle", "Ptr", this.handle)
        }
        this.window.Destroy()
    }
}
