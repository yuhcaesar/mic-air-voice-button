# AirKey 按钮检测

**中文** | [English](README.en.md)

一个独立的 Windows x64 检测工具，用来检查 Mic Air 按钮的接收方式，以及已有的按键输出通道能否启动豆包语音。它记录当前电脑的实际观察结果，帮助区分按钮接收、旧版程序门禁和快捷键输出问题；不能保证还原过去某一次故障的根因。

## 使用

1. 连接 Mic Air 接收器，从托盘退出 AirKey，并关闭独立的音量实验工具。把 `AirKey-Diagnostics.exe` 放在可写入的本地文件夹，双击打开，点击「开始检测」。
2. 工具会依次进行四轮按钮检测。每轮按 Mic Air 按钮 **两次，间隔约 3 秒**，再点击「已按两次，继续」。按提示完成全部四轮；部分步骤可能改变 Windows 音量。
3. 在工具的输入框内，手动按屏幕显示的快捷键，确认豆包语音本身能否启动。若启动了，先结束录音，再选择结果。默认组合为右 Alt＋空格；已有 AirKey 设置会被只读使用。
4. 若手动组合可用且电脑已有可用的 Interception 驱动，工具会逐个选择候选输出通道。每次点击「试发一次」，松开键盘，保持光标在工具输入框中，再按实际情况选择豆包是否启动。候选由工具安排，无需认识设备编号；可以随时跳过剩余试发。
5. 完成后点击「打开检测报告」或「复制报告内容」。TXT 默认保存在 EXE 旁的 `AirKey-Reports` 文件夹；该位置不可写时，保存到 `%LOCALAPPDATA%\AirKeyDiagnostics\Reports`。窗口显示实际报告路径。关闭工具后可以重新打开 AirKey。

没有收到事件、超时或未完成某一步，不等于已证明硬件或驱动损坏。报告中的「模拟发送」「门禁通过」也不代表真的发键或启动了豆包；实际试发会另外记录用户确认结果。

## 检测范围与隐私

四个输入阶段各使用一个新的子进程，避免上一轮的键盘钩子状态影响下一轮：原始输入观察、旧版输入回调与门禁重现（不发键）、系统热键、键盘钩子。旧版重现不是运行完整旧版应用。

工具只关注音量＋相关输入。报告包含系统和组件版本、驱动状态、匿名数量、事件计数与相对时间、固定错误码以及人工确认结果，不包含普通按键或输入框文字、账号、电脑名、完整硬件编号、设备路径或序列号。已有设置中的设备标识仅在本机内存中用于匹配候选，报告只保留匹配结果与匿名序号。

工具不联网、不安装或卸载驱动、不修改 AirKey 的日常设置，也不会自动修复配置。检测期间会使用临时输入监听；点击试发后才会向本工具输入框发送已配置的快捷键。没有可用驱动时仍可收集输入阶段的结果，输出试发会跳过。退出时结束临时监听和子进程。

## 从源码构建

需要 Windows x64、AutoHotkey v2 x64（发布构建使用 2.0.30）和官方 Ahk2Exe。脚本只使用已安装的工具，不下载或安装依赖。

```powershell
.\build.ps1
```

默认生成 `dist\AirKey-Diagnostics.exe`。构建先执行 `/Validate`，然后使用 Ahk2Exe、不压缩编译；不会启动生成的程序。日志保存在 `.build`。

```powershell
.\build.ps1 -Runtime 'C:\Tools\AutoHotkey\v2\AutoHotkey64.exe' -Compiler 'C:\Tools\AutoHotkey\Compiler\Ahk2Exe.exe'
.\build.ps1 -OutputPath '.\dist\AirKey-Diagnostics.exe'
```

也可设置 `AHK_RUNTIME`、`AHK_COMPILER` 或 `AUTOHOTKEY_HOME`；未指定时检查常见安装位置和 PATH。

## 安全测试

```powershell
.\tests\run.ps1
```

先检查主程序和测试的语法，再运行输入模块、报告和进程通信的隔离测试；存在控制流程测试时一并运行。测试用模拟数据，不注册真实输入、不发送快捷键、不改变驱动或日常配置。结果保存在 `tests\.results`；可用 `-Runtime`、`-ResultsDirectory` 指定运行器和输出目录。

`tests\LiveRegistrationSmoke.ahk` **不在默认测试中运行**。它是单独的人工检查，只短暂注册并解除 Raw Input，消息回调不读取事件，不发送按键。模拟测试或这个注册检查通过，都不能代替目标电脑上的实际 Mic Air 验证。

`tests\WorkerProcessSmoke.ahk` 同样不在默认测试中运行。它使用已编译程序，检查原始输入子进程能否正常结束、主窗口失联后能否自行退出；不发送按键、不修改驱动或日常设置。`AirKey-Diagnostics.exe --self-test <输出目录>` 仅检查内嵌组件的解压与校验。

## 许可与对应源码

本项目原创脚本、测试、构建脚本、文档与应用图标采用 [MIT](LICENSE)。编译 EXE 内含 AutoHotkey GPL 解释器及 Interception LGPL API 库，各自许可继续适用；本工具不分发 Interception 安装器或驱动。详情与完整许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 和 `assets` 下的许可文件。

发布时与 EXE 一同提供本工具源码及 `ThirdParty-Sources.zip`，其中包含对应 AutoHotkey 2.0.30 和 Interception v1.0.1 源码。要使用修改后的兼容 Interception API 库，可按上游源码说明构建 x64 DLL，替换 `assets\interception.dll`，将 `Main.ahk` 中该 DLL 的 SHA-256 校验值改为新文件值，再执行本项目构建脚本。本项目不限制为调试该库修改而进行的反向工程。
