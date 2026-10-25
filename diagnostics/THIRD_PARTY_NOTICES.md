# AirKey Diagnostics — licenses and third-party notices

本项目原创的脚本、测试、构建脚本、文档与应用图标按 [LICENSE](LICENSE) 中的 MIT 许可提供。编译后的 EXE 包含采用其他许可的组件，不能将整个 EXE 视为仅受 MIT 许可约束。以下许可与版权声明继续有效。

Original project scripts, tests, build scripts, documentation, and the application icon are provided under the [MIT license](LICENSE). The compiled EXE includes components with other licenses; it is not an MIT-only executable. Their copyright notices and license terms continue to apply.

本工具是独立的兼容诊断工具，不是 Insta360、豆包、AutoHotkey 或 Interception 的官方产品，不表示这些权利人对本项目的赞助或背书，也不授予商标权。

This independent compatibility diagnostic tool is not an official product of Insta360, Doubao, AutoHotkey, or Interception. No sponsorship, endorsement, or trademark rights are implied.

## AutoHotkey

The release EXE embeds the **AutoHotkey 2.0.30** interpreter. Its source identifies the license as **GPL-2.0-or-later**. AutoHotkey and its contributors retain their respective copyrights. The MIT license on this project's original scripts does not replace the interpreter's GPL terms.

- Upstream: [AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey)
- Corresponding source: [v2.0.30](https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.30)
- Complete supplied license: [assets/AutoHotkey-license.txt](assets/AutoHotkey-license.txt)

该许可文件也包含 PCRE 的 BSD 许可与通知，其中包括 University of Cambridge（1997–2006）和 Google Inc.（2006）的版权声明。再分发时请保留全文，而不是仅保留开头的 GPL 正文。

The license file also includes PCRE BSD terms and notices, including copyrights of the University of Cambridge (1997–2006) and Google Inc. (2006). Preserve the full file, including these notices and its non-endorsement conditions, rather than only its opening GPL text.

## Interception API library

`assets/interception.dll` is the x64 **Interception v1.0.1 API/library**, licensed under **LGPLv3**. Upstream identifies © 2008 Francisco Lopes; additional notices in individual source files remain applicable. The library is extracted locally for optional shortcut-output trials using an already installed compatible driver.

- Upstream: [oblitum/Interception](https://github.com/oblitum/Interception)
- Corresponding source: [v1.0.1](https://github.com/oblitum/Interception/tree/v1.0.1)
- Upstream licensing information: [v1.0.1 README](https://github.com/oblitum/Interception/blob/v1.0.1/README.md#license)
- Complete supplied terms: [LGPLv3](assets/LGPL-3.0.txt) and its incorporated [GPLv3](assets/GPL-3.0.txt)

**本检测工具不分发 Interception 安装器或驱动，也不安装或卸载驱动。** 这里分发的是 LGPL API 库。上游针对其他二进制组件提供的独立授权条件，不会在此被套用为对 MIT、GPL 或 LGPL 的“非商业”附加限制。

**This diagnostic tool distributes no Interception installer or drivers and does not install or remove drivers.** The distributed component is the LGPL API library. Separate upstream conditions for other binary components are not imposed here as an additional non-commercial restriction on MIT, GPL, or LGPL rights.

用户可以修改该库，并为调试这些修改进行反向工程。使用修改版兼容库重新构建本工具的步骤见 [中文构建说明](README.md) 或 [English build instructions](README.en.md)。重新分发修改版本仍须满足各自许可的适用要求。

Users may modify the library and reverse engineer for debugging those modifications. The [build instructions](README.en.md) explain replacing the compatible library and rebuilding this tool. Applicable license requirements continue to apply when redistributing modified versions.

## Corresponding source and redistribution

与 EXE 同一发布包提供本工具源码、构建说明、完整许可文本及 **ThirdParty-Sources.zip**。该归档包含与随包组件对应的 AutoHotkey 2.0.30 和 Interception v1.0.1 源码。再分发者应保留许可、版权与免责声明，并按适用许可继续提供对应源码及必要构建材料。

The release supplies this tool's source, build instructions, complete license texts, and **ThirdParty-Sources.zip** alongside the EXE. This archive contains the AutoHotkey 2.0.30 and Interception v1.0.1 sources corresponding to the supplied components. Redistributors must retain the applicable licenses, copyright notices, and disclaimers and continue to provide corresponding source and required build materials as the relevant licenses require.

本说明不替代完整许可。各组件均适用其各自许可中的免责声明。

These notices do not replace the full licenses. Each component retains the disclaimers in its respective license.
