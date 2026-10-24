# AirKey · 语音键

**中文** | [English](README.en.md)

把 **Insta360 Mic Air 接收器的音量＋按键**变成豆包输入法的语音快捷键。

当前版本：**v1.2.0**。适用于 Intel / AMD **Windows x64**。提供独立 EXE，日常使用无需安装 AutoHotkey。

原创代码使用 MIT 许可；成品中的 Interception 驱动和安装器适用上游的非商业使用条件。商业用途需另行取得上游授权，详见[第三方许可](THIRD_PARTY_NOTICES.md)。

[下载 Windows 版](https://github.com/yuhcaesar/mic-air-voice-button/releases/latest) · [使用说明](assets/README.txt) · [反馈问题](https://github.com/yuhcaesar/mic-air-voice-button/issues)

<table>
  <tr>
    <td align="center"><img src="assets/mic-air-original.png" width="128" alt="带有 Insta360 字样的圆形麦克风示意插图，侧边按钮可见"><br>按下 Mic Air 侧边按钮</td>
    <td align="center">→</td>
    <td align="center"><img src="assets/voice-illustration.png" width="112" alt="语音输入示意图"><br>启动豆包输入法语音</td>
  </tr>
</table>

运行时会优先显示用户电脑上已安装的豆包输入法图标；公开仓库和下载包不附带该品牌图标。麦克风图是项目示意插图，新增的 “Insta360” 文字用于识别兼容设备，并非官方产品照片。

## 能做什么

- 一键启用、暂停；绿色状态显示当前是否开启。
- 默认发送 **右 Alt＋空格**，支持录入其他快捷键，区分左右 Alt、Ctrl、Shift。
- 首次使用跟随向导识别按钮并试用；确认豆包语音启动后，才保存设置并启用。
- 无需选择设备编号；试用不成功时，自动换一种本机连接方式。
- 每台电脑独立保存经过确认的配置；连接仍有效时，下次打开恢复之前的启用状态。
- 默认中文，点击主界面右下角的 **English / 中文** 按钮切换语言；记住选择，切换时语音按钮继续工作。
- 最小化后收进系统托盘；单击托盘图标恢复界面，右键打开菜单。
- 提供“重新识别按钮”和“卸载并恢复”。

## 第一次使用

1. 从 [Releases](https://github.com/yuhcaesar/mic-air-voice-button/releases) 下载并打开 `AirKey.exe`，连接 Mic Air 接收器。在豆包输入法中，将语音输入的免按模式快捷键设为 **右 Alt＋空格**。
2. 点击 **安装并启用**，允许 Windows 的管理员提示。
3. 安装成功后，保存工作并**手动重启 Windows**，再打开程序。驱动就绪后，按钮设置向导会自动打开。
4. 按一次 Mic Air 按钮，让程序识别按钮。
5. 点击向导中的输入框，再按一次 Mic Air 按钮，试着启动豆包语音。
6. 如果启动成功，点击 **已启动，完成设置**；否则点击 **没有启动，换一种方式**，再在输入框里按按钮试用。程序会依次尝试本机可用连接，不需要选择设备编号。

只有收到真实按钮事件、完成试用并由你确认成功后，程序才保存本机配置并启用；AirKey 不会自动检测豆包是否开始录音。向导输入框的内容不会被 AirKey 保存。已经安装并加载所需驱动时，无需重装，直接完成按钮设置即可；取消后可点击 **设置语音按钮** 重新开始。

最小化后收进系统托盘并继续运行，单击托盘图标即可恢复界面。图标可能位于 Windows 托盘的“隐藏图标”区域。再次双击 EXE 也会恢复已有窗口，不会多开。

关闭窗口或在托盘菜单选择“退出程序”会停止映射并退出。程序不会自动重启电脑，也不会设置 Windows 开机自启动。

### 语言与升级

AirKey 默认中文。点击主界面右下角的 **English** 按钮即可切换英文；英文界面中点击同一位置的 **中文** 按钮切回。程序会记住选择，无需打开设置、重启程序或暂停已启用的语音按钮。主界面、按钮设置向导、托盘菜单、快捷键录入窗口和应用自带提示均提供两种语言；向导使用打开时的语言，关闭后可切换。“使用说明”会打开当前语言的说明文件。Windows 自带的权限等对话框遵循系统语言。

中文应用标题为 **AirKey · 语音键 — Insta360 Mic Air**，英文为 **AirKey — Insta360 Mic Air**。

从旧版升级时，先退出旧程序，再用 `AirKey.exe` 替换旧 EXE。已安装且正常工作的驱动无需重装；升级到 v1.2.0 后需要完成一次按钮设置，确认成功后才恢复启用。原有快捷键和语言设置继续保存在 `%LOCALAPPDATA%\MicAirDoubao`，目录名保持不变以兼容老用户。仓库地址仍为 `yuhcaesar/mic-air-voice-button`。

每台电脑单独保存自己的验证结果。换电脑、原来的连接消失，或保存的连接不再能被确认时，需要重新跟随向导试用；复制 EXE 或旧配置不能代替新电脑上的验证。

### 修改快捷键

打开 **设置 → 修改 → 开始录入**，按下你在豆包中设置的组合，然后保存。更改快捷键后需要重新完成按钮设置，确认新组合能启动豆包语音。

**本工具与豆包输入法的快捷键必须一致。**这里修改的是本工具发送的按键，不会改动豆包自己的设置。

### 重新识别按钮

按钮没有反应或需要重新适配时，打开 **设置 → 重新识别按钮**。向导会重新识别 Mic Air 按钮，并让你逐一试用可用连接；点击 **已启动，完成设置** 后才保存新的结果。它不会改动你选择的快捷键，也不会自动判断豆包是否启动。

### 恢复音量键 / 卸载

- 临时停用：点击 **暂停语音按钮**，立即停止触发语音；键盘按键模式下，音量＋恢复原来的作用。
- 彻底移除：点击 **卸载并恢复**，完成后手动重启 Windows，再删除 EXE。
- 设置、日志和运行组件保存在 `%LOCALAPPDATA%\MicAirDoubao`。卸载驱动并退出程序后，可以删除这个程序专用目录。

不要手动删除 Windows 系统目录里的驱动文件。卸载 Interception 会同时影响其他使用该驱动的应用。

## 使用前了解

- 按钮识别会选择本机可用的接收方式，无需手动配置。在**键盘按键模式**下，程序接管所有可接收到的 **音量＋**，键盘音量＋也会触发语音。
- 在 **HID 模式**下，只监听设置时识别到的设备媒体事件；同一次按钮操作**也可能改变 Windows 音量**，向导和主界面会明确提示。
- 两次触发至少间隔约 1.5 秒，避免一次按压重复触发。
- 只发送快捷键，不录音、不上传数据、不记录普通打字内容，也不检测豆包是否正在录音。
- 需要管理员权限安装 / 卸载驱动；首次安装及卸载后需要重启。
- 基础触发方式已在一台 Windows 11 x64 电脑配合 Mic Air 接收器实测成功；不能保证所有电脑兼容。只有在该电脑上收到按钮事件并由用户确认豆包语音启动，才算完成该机设置。长期休眠与反复热插拔尚未全面验证。
- Interception v1.0.1 较旧；[Kanata 的 Windows 已知问题](https://github.com/jtroo/kanata/blob/main/docs/platform-known-issues.adoc)记录了相关驱动在部分系统上出现的休眠、设备插拔问题。
- Windows on ARM 不适用。EXE 未做代码签名；设置向导无法自动解决驱动被系统拦截的问题。如果系统阻止驱动加载，请停止安装或卸载，保持系统安全防护开启。

## 为什么需要驱动

在本项目的测试环境中，Mic Air 通过接收器上报音量＋，普通软件模拟快捷键没能启动豆包语音。程序使用强制键盘钩子接收音量＋，或使用 Windows Raw Input 接收所识别设备的 Consumer HID 媒体事件，再通过 Interception 发送键盘扫描码。

默认右 Alt＋空格沿用已经验证成功的发送顺序。程序不使用 Interception 拦截原始键盘输入，也不需要更改豆包程序。

## 从源码构建

安装 [AutoHotkey v2 x64](https://www.autohotkey.com/) 和 [Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe)，然后在仓库目录运行：

```powershell
.\build.ps1
```

产物为 `dist\AirKey.exe`。可用 `-Runtime`、`-Compiler` 指定工具路径，或设置 `AHK_RUNTIME` / `AHK_COMPILER` 环境变量。构建不会安装驱动，也不会运行产物。

本次发布使用 AutoHotkey **2.0.30 x64** 与 Ahk2Exe **1.1.37.02a2**。第三方依赖版本、许可及来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

### 第三方组件源码与重新构建

每个成品 Release 同页提供 `ThirdParty-Sources.zip`，其中包含对应版本的 AutoHotkey 和 Interception 上游源码。它们与本仓库源码一起构成重新构建所需的源码材料；构建工具链按各上游说明安装。

如果修改 Interception API DLL，请先依据其上游源码构建 x64 DLL，再替换本仓库的 `assets/interception.dll`，并将 `Main.ahk` 中该 DLL 的 SHA256 校验值更新为新文件的值，然后运行 `build.ps1`。如果修改 AutoHotkey，请根据随附上游源码说明构建 x64 解释器，再通过 `build.ps1 -Runtime <路径>` 指定它。源码层面的修改和重新构建不需要本项目授予额外许可，第三方组件仍遵守各自许可。

当前 EXE 会解包并校验内置组件，直接替换运行目录的 DLL 会被覆盖；请使用上述重新构建方式。本项目不限制为调试用户修改而进行的合法逆向工程。

### 测试

```powershell
.\tests\run.ps1
```

测试包括语法验证、快捷键解析、发送顺序、失败时释放按键、配置保存和停止逻辑，以及双语和隐藏向导窗口检查。发送由内存模拟替代；不会安装驱动、发送真实快捷键或修改日常设置。

真正的 Mic Air 按钮、豆包语音触发以及安装 / 卸载流程需要在兼容的 Windows 电脑上人工验证。v1.2.0 新增向导和 HID 接收方式已通过自动检查，仍需在目标电脑上完成实物验证；此前的基础触发成功不代表新流程已在其他电脑验证成功。

## 目录

| 文件 | 用途 |
| --- | --- |
| `Main.ahk` | 主界面、配置、音量键映射与生命周期 |
| `SetupWizard.ahk` | 首次按钮设置向导与试用输入框 |
| `MicSetupController.ahk` | 按钮识别、连接试用及用户确认流程 |
| `ButtonInput.ahk` | 键盘钩子与指定设备的 Consumer HID 按钮接收 |
| `MachineProfile.ahk` | 本机验证配置的保存与连接匹配 |
| `Localization.ahk` | 双语文字、提示与错误信息 |
| `NativeOutput.ahk` | Interception 输出与连接选择 |
| `DriverManager.ahk` | 驱动状态、官方安装器调用及完整性校验 |
| `ShortcutConfig.ahk` | 快捷键解析、按键顺序与释放恢复 |
| `ShortcutRecorder.ahk` | 快捷键录入窗口 |
| `ModernControls.ahk` | 原生按钮绘制 |
| `AppArtwork.ahk` | 从本机已安装输入法读取图标及原创图片回退 |
| `TrayWindow.ahk` | 最小化到托盘、单击恢复及已有实例唤回 |
| `assets/` | 界面素材、依赖及其原始许可 |
| `tests/` | 不触发真实按键的本地检查 |

## 许可与归属

本项目原创代码采用 [MIT License](LICENSE)。第三方组件遵守各自许可；本项目的 MIT 许可不授予 Insta360 或其他第三方商标权。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

完整英文版本见 [THIRD_PARTY_NOTICES.en.md](THIRD_PARTY_NOTICES.en.md)；随附的上游许可原文保持不变。

这是一个独立项目，与 Insta360 / 影石及豆包没有官方隶属或背书关系。
