# AirKey Third-Party Notices

[中文](THIRD_PARTY_NOTICES.md) | **English**

This project's original application scripts, tests, build scripts and documentation are provided under the MIT license in [LICENSE](LICENSE). MIT does not relicense third-party interpreters, libraries, drivers, installers, license documents or trademarks. The compiled EXE contains components under different licenses and must not be treated as a file covered only by MIT.

AirKey is an independent compatibility utility. It is not an official product of Insta360, Doubao, AutoHotkey or Interception, and does not imply sponsorship, authorization or endorsement by those rights holders. Product names identify compatibility. This project grants no trademark rights.

## AutoHotkey

The Windows EXE contains the AutoHotkey **2.0.30** interpreter. Its official source notices specify **GNU GPL version 2 or, at the recipient's option, any later version (GPL-2.0-or-later)**. AutoHotkey and its contributors retain their respective copyrights. The MIT license on this project's original scripts does not replace the interpreter's GPL terms.

- Upstream project: [AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey)
- Corresponding source: [v2.0.30](https://github.com/AutoHotkey/AutoHotkey/tree/v2.0.30)
- Complete license: [assets/AutoHotkey-license.txt](assets/AutoHotkey-license.txt)

The same Release as the EXE provides the corresponding interpreter source, project source and build instructions. Consult that version's README, build scripts and Release notes for the tools and versions used. Redistributors must retain upstream licenses, copyright notices and disclaimers, and continue to meet applicable source-distribution requirements.

The AutoHotkey license file also contains PCRE's BSD license and notices, including the copyrights of the University of Cambridge (1997–2006) and Google Inc. (2006). Preserve the entire file and its non-endorsement provisions; do not retain only the GPL text at the beginning.

## Interception

The app sends keys through the **Interception v1.0.1** library/API. The upstream project states **© 2008 Francisco Lopes**; other copyright notices in individual source files remain in effect.

- Upstream project: [oblitum/Interception](https://github.com/oblitum/Interception)
- Corresponding source: [v1.0.1](https://github.com/oblitum/Interception/tree/v1.0.1)
- Upstream licensing statement: [License section of the v1.0.1 README](https://github.com/oblitum/Interception/blob/v1.0.1/README.md#license)
- Full license texts: [LGPLv3](assets/LGPL-3.0.txt) and the [GPLv3](assets/GPL-3.0.txt) it incorporates

The API/library is licensed under LGPLv3. The same Release as the EXE provides the matching API source and this project's source. The build instructions explain how to rebuild the app with an interface-compatible modified library. This project does not prohibit modifying that library or reverse engineering to debug those modifications. Redistribution of modified versions must still meet applicable upstream license requirements.

**The drivers and command-line installer are separate upstream binary assets; this project's MIT license does not relicense them.** The upstream v1.0.1 README describes redistribution permission for non-commercial purposes, with communication with the drivers occurring solely through the Interception library and its API. This app uses that API for key output. The upstream wording governs the scope of the permission.

Upstream offers separate paid licenses for commercial use. This project does not grant recipients a commercial Interception license. A free download does not automatically establish that a proposed use falls within the upstream meaning of non-commercial use. For commercial authorization, contact the author through the address published in the upstream README. Commercial-license PDFs supplied with the app are for reference; they do not establish that the publisher or recipient has purchased or received a commercial license.

The preceding paragraphs describe separate upstream conditions. They do not add a non-commercial restriction to MIT, GPL or LGPL, or reduce rights already granted by those licenses.

## Images, icons and trademarks

### Public microphone illustration

The public microphone illustration, assets/mic-air-original.png, was originally generated independently from a text description. Plain “Insta360” lettering was later added to the project's existing illustration to identify the compatible device. No official product image or official logo asset was supplied as input. This is a project illustration, not an official product photograph, and does not indicate manufacturer authorization or endorsement. To the extent this project has rights to license the illustration, it is provided under MIT. This statement does not promise exclusive copyright in AI output or grant Insta360 or other third-party trademark rights. See [assets/ARTWORK.md](assets/ARTWORK.md) for provenance.

### Project icon and generic voice illustration

assets/app-icon.svg and assets/app-icon.ico are original project icons drawn through scripts/New-AppIcon.ps1 and provided under the project's MIT license. They do not use a manufacturer's original icon or indicate manufacturer authorization or endorsement.

The generic voice illustration used when no local Doubao icon is available was independently generated. It is not Doubao artwork, an official mark or a mascot. It is offered under MIT to the extent this project has rights to license it, without promising exclusive copyright in AI output.

### Doubao IME icon

The public app does not distribute the original Doubao IME icon. If Doubao IME is already installed, the app may read its icon from the installation folder and display it locally. Reading and displaying the icon do not transfer ownership or grant copying, redistribution or other brand permissions. This project does not include that icon within its MIT grant.

Doubao IME images, marks and trademarks belong to their respective rights holders. Its [official website](https://shurufa.doubao.com/pc) identifies its operator as 北京春田知韵科技有限公司. Insta360, Mic Air, their marks and official product images likewise belong to their respective rights holders. This project claims no ownership of those third-party materials and grants no licenses on their owners' behalf.

## Source and license availability

When an EXE is released, the same GitHub Release provides the corresponding source archives, build instructions and third-party license texts. Redistributors should retain these materials or meet their obligations through another method permitted by the applicable licenses. This notice does not replace the full licenses.

The project and each third-party component are subject to their respective license disclaimers. This notice makes no additional warranty or support commitment on behalf of any third party.
