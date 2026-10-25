# AirKey 第三方组件与素材说明

**中文** | [English](THIRD_PARTY_NOTICES.en.md)

本项目原创的应用脚本、测试、构建脚本和文档按根目录 [LICENSE](LICENSE) 中的 MIT 许可提供。MIT 不会将第三方解释器、库、驱动、安装器、许可文本或商标重新授权。编译后的 EXE 包含不同许可的组件，不能将整个文件视为仅受 MIT 许可约束。

本项目是独立的兼容工具，不是 Insta360、豆包、AutoHotkey 或 Interception 的官方产品，不表示这些权利人对本项目的赞助、授权或背书。产品名称用于说明兼容关系；本项目不授予任何商标权。

## 项目音量拦截器

`native/volume-guard.c`、`NativeVolumeGuard.ahk` 和由其构建的 `assets/volume-guard.dll` 是本项目的原创代码，按根目录 MIT 许可提供。DLL 使用 TinyCC 0.9.27 x64 构建，仅依赖 Windows 系统 API，不链接 TinyCC 运行库。编译器不随应用分发；源码和重新构建方法随项目提供。

## AutoHotkey

Windows EXE 包含 AutoHotkey **2.0.30** 解释器。其官方源文件声明采用 **GNU GPL 第 2 版或由接收者选择的更新版本（GPL-2.0-or-later）**。AutoHotkey 及其贡献者保留各自版权；本项目原创脚本的 MIT 许可不替代解释器的 GPL 条款。

- 上游项目：[AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey)
- 对应源码：[v2.0.30](https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.30)
- 完整许可：[assets/AutoHotkey-license.txt](assets/AutoHotkey-license.txt)

与 EXE 同一 Release 提供对应解释器源码、本项目源码和构建说明。构建工具及版本以该版本的 README、构建脚本和 Release 说明为准。再分发者须保留上游许可、版权及免责声明，并继续满足适用的源码提供义务。

AutoHotkey 许可文件还包含 PCRE 的 BSD 许可及通知，包括 University of Cambridge（1997–2006）和 Google Inc.（2006）的版权声明。请保留该文件全文及其中的不背书条款；不要仅保留开头的 GPL 正文。

## Interception

应用通过 **Interception v1.0.1** 的库/API 发送按键。上游项目标注 **© 2008 Francisco Lopes**；各源文件中的其他版权声明继续有效。

- 上游项目：[oblitum/Interception](https://github.com/oblitum/Interception)
- 对应源码：[v1.0.1](https://github.com/oblitum/Interception/tree/v1.0.1)
- 上游授权说明：[v1.0.1 README 的 License 部分](https://github.com/oblitum/Interception/blob/v1.0.1/README.md#license)
- 许可全文：[LGPLv3](assets/LGPL-3.0.txt) 和其包含的 [GPLv3](assets/GPL-3.0.txt)

API/library 采用 LGPLv3。与 EXE 同一 Release 提供对应 API 源码和本项目源码；构建说明提供使用接口兼容的修改版库重新构建应用的方法。本项目不会限制修改该库，或为调试这些修改而进行的反向工程。重新分发修改版本时仍须遵守上游许可的适用要求。

**驱动和命令行安装器是上游单独提供的二进制资源，不受本项目 MIT 许可重新授权。** 上游 v1.0.1 README 描述了非商业用途的分发授权，且要求与驱动的通信只能通过 Interception 库及其 API。本程序的按键发送使用该 API。具体授权范围以上游原文为准。

上游为商业用途另行提供付费许可。本项目没有向接收者授予 Interception 商业许可；免费下载不自动证明某项使用属于上游所称的非商业用途。需要商业授权时，请通过上游 README 中公布的联系方式联系作者。随包提供的商业许可 PDF 仅供查阅，并不证明发布者或接收者已购买或获得商业许可。

上述说明转述的是上游单独的授权条件，不向 MIT、GPL 或 LGPL 许可本身添加“非商业”限制，也不减少这些许可已授予的权利。

## 图像、图标与商标

### 公开版麦克风插图

公开版的麦克风插图 assets/mic-air-original.png 最初由文字描述独立生成，随后在项目已有插图上添加普通“Insta360”文字，用于识别兼容设备。未使用官方产品图片或官方 logo 素材作为输入；它是项目示意插图，不是官方产品照片，也不表示厂商授权或背书。在本项目有权许可的范围内，该插图按 MIT 提供；此声明不承诺 AI 输出具有可独占的著作权，也不授予 Insta360 或其他第三方商标权。生成来源见 [assets/ARTWORK.md](assets/ARTWORK.md)。

### 项目图标与通用语音插图

assets/app-icon.svg 和 assets/app-icon.ico 是本项目通过 scripts/New-AppIcon.ps1 绘制的原创应用图标，按本项目 MIT 许可提供。它们不使用厂商原图标，不表示厂商授权或背书。

无可用本机豆包图标时使用的通用语音插图独立生成，不是豆包原图、官方标识或吉祥物；在本项目有权许可的范围内按 MIT 提供，同样不承诺 AI 输出具有可独占的著作权。

### 豆包输入法图标

公开版不随程序分发豆包输入法原图标。若用户已安装豆包输入法，程序可以从该电脑上的安装目录读取其图标并在本机显示。读取和显示不会转移图标的所有权，也不授予复制、再分发或其他品牌授权；本项目不将该图标加入 MIT 授权范围。

豆包输入法的图像、标识和商标属于相应权利人。其[官方网站](https://shurufa.doubao.com/pc)标注运营者为北京春田知韵科技有限公司。Insta360、Mic Air 及其标识、官方产品图片同样属于相应权利人。本项目不声称拥有这些第三方内容，也不代替权利人授予许可。

## 源码和许可的供应

发布 EXE 的同时，该 GitHub Release 提供对应的源码归档、构建说明及第三方许可文本。再分发时应保留这些材料，或通过适用许可允许的其他方式履行义务。仅有本说明不能替代完整许可。

本项目和各第三方组件均适用各自许可中的免责声明。本说明不代表任何第三方作出额外的保证或支持承诺。
