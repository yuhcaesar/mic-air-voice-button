# 更新记录

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
