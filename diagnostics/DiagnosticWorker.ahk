; One fresh process per input phase. Workers never send keys or load output DLLs.
class DiagnosticWorker {
    static OwnerProperty := "AirKey.Diagnostic.OwnerPID"
    static DeadlineProperty := "AirKey.Diagnostic.Deadline"
    __New(phase, path, parentWindow, parentPid, mainKey := "Space") {
        if !RegExMatch(phase, "^(baseline|legacy|registered|hook)$")
            throw Error("INVALID_PHASE")
        if !RegExMatch(path, "i)^[A-Z]:\\") || !InStr(path, "\AirKey-Diagnostic-")
            || InStr(path, "..") || InStr(path, '"')
            throw Error("INVALID_SESSION")
        this.phase := phase, this.path := path, this.parentWindow := parentWindow, this.parentPid := parentPid
        this.input := DiagnosticInput(mainKey)
        this.ending := false, this.born := DiagNow()
        this.timer := ObjBindMethod(this, "Tick")
        this.exitCallback := ObjBindMethod(this, "OnExit")
        OnExit(this.exitCallback)
        if !this.ParentAlive()
            throw Error("PARENT_MISSING")
        try {
            this.input.Start(phase)
            DiagWriteSnapshot(path, this.input.Snapshot())
            SetTimer(this.timer, 200)
        } catch {
            this.Finish("start_failed")
        }
    }
    ParentAlive() {
        actualPid := 0
        if !DllCall("User32\IsWindow", "Ptr", this.parentWindow, "Int")
            return false
        DllCall("User32\GetWindowThreadProcessId", "Ptr", this.parentWindow, "UInt*", &actualPid, "UInt")
        marked := DllCall("User32\GetPropW", "Ptr", this.parentWindow, "Str", DiagnosticWorker.OwnerProperty, "Ptr")
        deadline := DllCall("User32\GetPropW", "Ptr", this.parentWindow, "Str", DiagnosticWorker.DeadlineProperty, "Ptr")
        return actualPid = this.parentPid && marked = actualPid
            && DiagDeadlineFresh(deadline, DllCall("Kernel32\GetTickCount", "UInt"))
    }
    Tick(*) {
        if this.ending
            return
        if !this.ParentAlive()
            return this.Finish("parent_lost")
        if FileExist(this.path ".stop")
            return this.Finish("confirmed")
        if DiagNow() - this.born > 40000
            return this.Finish("timeout")
        try DiagWriteSnapshot(this.path, this.input.Snapshot())
        catch
            this.Finish("report_failed")
    }
    Finish(reason) {
        if this.ending
            return
        this.ending := true
        SetTimer(this.timer, 0)
        cleanupOk := true
        try this.input.Stop()
        catch
            cleanupOk := false
        snapshot := this.input.Snapshot()
        snapshot.active := false
        snapshot.completed := reason = "confirmed" && cleanupOk
        try DiagWriteSnapshot(this.path, snapshot, reason, cleanupOk)
        ExitApp(cleanupOk ? 0 : 2)
    }
    OnExit(*) {
        SetTimer(this.timer, 0)
        try this.input.Stop()
    }
}
