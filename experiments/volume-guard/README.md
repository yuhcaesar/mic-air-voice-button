# AirKey 音量拦截验证 / Volume Check

这是独立、限时的兼容性验证工具，不是 AirKey 正式版更新。用于确认某台电脑能否在继续使用 AirKey 触发豆包时，拦住系统音量＋动作。结果尚需实物验证。

## 使用

1. 保持 AirKey v1.2.0 已开启，不要退出它。
2. 打开 `AirKey-Volume-Check.exe`，点击“开始验证 · 60 秒”。
3. 点击验证窗口的输入框，按一次 Mic Air。观察豆包是否启动、音量是否保持不变、音量条是否弹出。
4. 切换到平常使用的软件文本框里再试一次。记下“已拦截”次数与实际表现。

点击停止、关闭窗口或 60 秒到时都会停用拦截。若程序失去响应，心跳超过约 1.5 秒后拦截条件失效。暂停或退出后，原有 AirKey 行为继续有效。

验证期间会临时拦截**所有来源、到达该系统通道的音量＋媒体命令**，不能只识别 Mic Air。系统音量滑块仍可用。它不会写回音量、发送快捷键、安装驱动、修改 AirKey 配置或保存输入框内容。GUI 显示的音量只读。DLL 临时解包到系统临时目录；启动过拦截的 DLL 保留至进程退出，避免卸载仍在执行的回调。

仅适用于 Intel/AMD x64 Windows。原生 `WH_SHELL` 钩子在 `HSHELL_APPCOMMAND` 收到音量＋时返回非零，属于实际命令消费，不是事后调回音量。前台软件自行处理、系统安全边界、部分应用/架构及不经过该通道的硬件路径可能绕过它。注册成功或计数增加均不能代替实际效果验证。

## English

This is a standalone, time-limited compatibility probe, not a stable AirKey update. Keep AirKey v1.2.0 enabled, launch the probe, start the 60-second check, focus its input box and press Mic Air. Confirm that Doubao starts, volume stays unchanged and no volume overlay appears. Repeat in your everyday application's text field.

While active, the probe consumes **all volume-up media commands that reach its shell hook**, not just Mic Air. The volume slider remains usable. Stop, close or wait 60 seconds to disarm it. A missing host heartbeat also disables consumption after about 1.5 seconds. It never writes audio levels, sends keys, installs drivers, changes AirKey settings or saves typed text.

Windows x64 only. This uses a native `WH_SHELL` / `HSHELL_APPCOMMAND` callback, not volume rollback. Application-handled commands, security boundaries and other input paths may bypass it. Physical verification on the target computer is required.

## Build / 构建

Install AutoHotkey **2.0.30 x64**, Ahk2Exe **1.1.37.02a2**, and TinyCC **0.9.27 x64**. Run:

```powershell
.\build.ps1 -NativeCompiler 'C:\path\to\tcc.exe'
```

Use `-Runtime` / `-Compiler` to select other compatible AutoHotkey/Ahk2Exe paths. The script builds the native DLL without a C runtime, validates the AHK source, and compiles the EXE. Building does not launch the EXE or install a hook.

`AirKey-Volume-Check.exe --self-test` checks DLL loading and inactive cleanup without installing a hook. `tests/volume-guard-test.c` replaces every Windows operation with a mock; `tests/registration-smoke.ahk` registers and removes a real hook **without ever arming it**, so every command passes through. None sends keys or writes audio levels.

## Licenses / 许可

Original scripts, native code, tests and app icon: [MIT](LICENSE). The EXE contains the unmodified AutoHotkey 2.0.30 runtime, licensed **GPL-2.0-or-later**, with additional upstream PCRE notices; retain the complete [AutoHotkey license](AutoHotkey-license.txt). The same prerelease provides `AutoHotkey-v2.0.30-source.zip`, and this probe's complete source and build instructions. No Interception components, product photos or IME icons are included in this probe. TinyCC is a build tool and is not redistributed; the native DLL links only Windows system APIs and uses the project's own entry point.

Sources: [AutoHotkey v2.0.30](https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.30), [TinyCC](https://bellard.org/tcc/), [ShellProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/shellproc), [SetWindowsHookEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexw).
