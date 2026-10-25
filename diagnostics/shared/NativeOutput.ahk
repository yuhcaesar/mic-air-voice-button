; Output-only Interception interface. Never subscribes to keyboard or mouse input.
; Localization.ahk is included explicitly by the diagnostic entry point.

class NativeOutput {
    __New(dllPath) {
        this.module := 0
        this.context := 0
        this.api := Map()
        try {
            this.module := DllCall("Kernel32\LoadLibraryExW", "Str", dllPath,
                "Ptr", 0, "UInt", 0x1100, "Ptr")
            if !this.module
                throw LocalError("无法加载按键发送组件。", "Unable to load the key output component.")
            for name in ["interception_create_context", "interception_destroy_context",
                "interception_get_hardware_id", "interception_send"] {
                ptr := DllCall("Kernel32\GetProcAddress", "Ptr", this.module, "AStr", name, "Ptr")
                if !ptr
                    throw LocalError("按键发送组件不完整。", "The key output component is incomplete.")
                this.api[name] := ptr
            }
            this.context := DllCall(this.api["interception_create_context"], "CDecl Ptr")
            if !this.context
                throw LocalError("驱动接口尚未就绪。请检查驱动状态。", "The driver interface is not ready. Check the driver status.")
        } catch as err {
            this.Close()
            throw err
        }
    }

    Enumerate() {
        devices := []
        Loop 10 {
            id := A_Index
            buf := Buffer(4096, 0)
            bytes := DllCall(this.api["interception_get_hardware_id"], "Ptr", this.context,
                "Int", id, "Ptr", buf, "UInt", buf.Size, "CDecl UInt")
            if bytes < 2 || bytes > buf.Size
                continue
            chars := 0
            while chars < Floor(bytes / 2) && NumGet(buf, chars * 2, "UShort") != 0
                chars++
            if !chars
                continue
            hid := StrGet(buf.Ptr, chars, "UTF-16")
            devices.Push({id: id, hid: hid})
        }
        return devices
    }

    Send(id, code, state) {
        stroke := Buffer(8, 0)
        NumPut("UShort", code, "UShort", state, "UInt", 0, stroke)
        sent := DllCall(this.api["interception_send"], "Ptr", this.context,
            "Int", id, "Ptr", stroke, "UInt", 1, "CDecl Int")
        if sent != 1
            throw LocalError("启动语音失败。请打开“设置”，点击“重新识别按钮”。",
                "Unable to start voice input. Open Settings and click Set Up Button Again.")
    }

    Close() {
        if this.context {
            DllCall(this.api["interception_destroy_context"], "Ptr", this.context, "CDecl")
            this.context := 0
        }
        if this.module {
            DllCall("Kernel32\FreeLibrary", "Ptr", this.module)
            this.module := 0
        }
    }
}

; Match an existing selection exactly. A disconnected saved device is not replaced silently.
FindDeviceSelection(devices, savedHid) {
    if savedHid {
        matches := []
        for i, device in devices {
            if device.hid = savedHid
                matches.Push(i)
        }
        return matches.Length = 1 ? matches[1] : 0
    }
    for i, device in devices {
        if SubStr(device.hid, 1, 5) = "ACPI\"
            return i
    }
    for i, device in devices {
        if SubStr(device.hid, 1, 8) = "HID\VID_"
            return i
    }
    for i, device in devices {
        if InStr(device.hid, "Dev_VID")
            return i
    }
    if devices.Length = 1
        return 1
    return 0
}
