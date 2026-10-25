# 更新记录

## 1.3.0 — 启动语音，保持音量 / Voice input without changing volume

中文：

- 将已在用户另一台电脑验证有效的音量拦截整合到应用。使用设备媒体信号时必须同时启用拦截；无需单独运行实验工具，也无需新增驱动。
- 补回首次识别遗漏的系统注册热键方式；同时观察键盘钩子和原始媒体信号，按实际收到的事件自动选择。
- 向导只有在用户确认“豆包已启动、音量不变、音量条不弹出”后才保存。新增“音量仍在变化”反馈，失败结果不保存。
- 升级后重新完成一次按钮设置；保留语言、快捷键和已安装的驱动。
- 暂停、退出、设置取消或接收失败时关闭音量拦截；向导过程中使用托盘停止也会取消设置。拦截器失去应用心跳后自动放行。
- 音量拦截对所有到达相同系统通道的音量＋生效，不只限于 Mic Air；使用系统滑块调音量。部分应用可能使用其他通道，仍需目标电脑实测确认。

English:

- Integrated the volume guard confirmed by the user on another computer. Raw device input now requires the guard; no standalone probe or additional driver is needed.
- Restored registered-hotkey detection missing from setup. It observes registered hotkeys, keyboard hooks and raw media input, choosing based on received events.
- Setup saves only after the user confirms voice starts, volume stays unchanged and no volume overlay appears. **Volume still changes** rejects the trial without saving.
- Upgrades require one new button setup while preserving language, shortcut and the installed driver.
- Pausing, exiting, cancelling setup or input failure stops the guard. Tray Stop also cancels an active wizard. The guard passes commands through if the app heartbeat expires.
- The guard affects all Volume Up commands reaching its system channel, not only Mic Air. Use the system volume slider. Other application paths may bypass it, so verification on the target computer remains necessary.

## 1.2.0 — 每台电脑的按钮设置 / Per-computer button setup

中文：

- 驱动安装并重启、重新打开程序后，自动进入首次按钮设置：按 Mic Air 识别按钮，再在向导输入框中按按钮试用。
- 只有收到按钮事件、完成试用并点击“已启动，完成设置”，才保存本机配置并启用；不自动检测豆包是否正在录音。
- 点击“没有启动，换一种方式”后，自动尝试下一个本机连接，不显示设备编号或硬件 ID。
- 每台电脑独立保存验证结果；旧版升级、换电脑、原连接失效或修改快捷键后需重新验证。
- 设置中的“修复按钮响应”改为“重新识别按钮”。向导输入内容不保存，中英文界面继续保留。
- 使用强制键盘钩子或 Raw Input Consumer HID 接收按钮。键盘按键模式仍接管所有音量＋；HID 模式只监听已识别设备的媒体事件，但可能同时改变系统音量，界面会明确提示。
- 不承诺所有电脑兼容。驱动安装仍需管理员权限及重启，向导无法自动解决系统拦截驱动的问题。第三方许可和图片归属保持不变。

English:

- Added a first-use wizard that opens after driver installation, a Windows restart and reopening AirKey. Press Mic Air to identify the button, then press it again with the wizard's input box focused to try voice input.
- Saves and enables the local configuration only after a button event, a trial and **Yes, finish setup**. AirKey does not automatically detect whether Doubao is recording.
- **No, try another way** tries the next local connection without exposing device numbers or hardware IDs.
- Each computer keeps its own verified setup. Upgrading from an older version, moving to another computer, losing the previous connection or changing the shortcut requires verification again.
- Replaced **Repair Button Response** with **Set Up Button Again**. The wizard does not save input-box contents; both interface languages remain available.
- Added forced keyboard-hook and Raw Input Consumer HID reception. Keyboard-key mode still handles all Volume Up keys. HID mode listens to the identified device's media events, but may also change system volume; the UI explicitly explains this.
- Compatibility with every computer is not guaranteed. Driver installation still requires administrator permission and a restart; the wizard cannot automatically resolve a driver blocked by Windows. Third-party licenses and artwork attribution are unchanged.

## 1.1.0 — AirKey

中文：

- 品牌更新为 AirKey · 语音键，下载程序改名为 `AirKey.exe`。
- 默认中文，主界面可直接切换中文 / English，并记住选择；切换时语音按钮继续工作。
- 主界面、托盘菜单、快捷键录入和应用自带提示提供完整双语；使用说明随当前语言打开，系统对话框遵循系统语言。
- 保留原有 `%LOCALAPPDATA%\MicAirDoubao` 设置和驱动，升级只需退出并替换旧 EXE，无需重装驱动。
- 暂停语音按钮后最小化，程序仍会留在托盘中。

English:

- Renamed the app to AirKey; the downloadable executable is now `AirKey.exe`.
- Chinese remains the default. Choose 中文 / English directly in the main window; the choice is saved and switching languages keeps the voice button running.
- Added both languages throughout the main window, tray menu, shortcut recorder and app messages. The user guide follows the selected language; Windows dialogs follow the system language.
- Existing settings in `%LOCALAPPDATA%\MicAirDoubao` and the installed driver are retained. Quit the old app and replace its EXE to upgrade; no driver reinstall is needed.
- The app stays in the tray when minimized while the voice button is paused.

## 1.0.9

- 麦克风示意插图添加“Insta360”字样，让兼容设备更容易辨认。
- 本次仅更新图片和说明，功能保持不变。

## 1.0.8

- 最小化到系统托盘，单击托盘图标恢复界面，右键菜单继续可用。
- 程序隐藏后再次打开 EXE，可恢复已有窗口；修改快捷键时优先恢复编辑窗口。
- 删除旧录入函数、无用状态字段和重复分支，将模拟设备样例移入独立测试。
- 只读自检不再输出完整硬件 ID。

## 1.0.7 — 首次公开发布

- Mic Air 接收器音量＋按键触发豆包输入法语音。
- 默认右 Alt＋空格，支持自定义快捷键与左右修饰键识别。
- 自动连接选择、启用状态保存、暂停、修复响应及驱动卸载。
- 紧凑界面、绿色启用状态、原创麦克风插图；从用户本机读取豆包输入法图标。
- 公开构建脚本、模拟测试与第三方来源说明。
- 随发布提供对应第三方组件源码及重新构建说明。
