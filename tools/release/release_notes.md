{{CHANGES}}

| 平台 / 文件 | 下载与使用 |
| --- | --- |
| Windows x64 单文件 EXE | [CarRacing-Windows-x64.exe](https://github.com/AmoseCP/car-racing/releases/download/{{TAG}}/CarRacing-Windows-x64.exe)：下载后直接运行，游戏资源已内嵌。 |
| Windows 完整包 | [CarRacing-Windows-x64.zip](https://github.com/AmoseCP/car-racing/releases/download/{{TAG}}/CarRacing-Windows-x64.zip)：解压后运行 `CarRacing.exe`，包含说明和第三方许可。 |
| Mac（M 系列芯片） | [CarRacing-macOS-AppleSilicon.zip](https://github.com/AmoseCP/car-racing/releases/download/{{TAG}}/CarRacing-macOS-AppleSilicon.zip)：解压后打开 `CarRacing-macOS-AppleSilicon/CarRacing.app`。 |
| Mac（Intel 芯片） | [CarRacing-macOS-Intel.zip](https://github.com/AmoseCP/car-racing/releases/download/{{TAG}}/CarRacing-macOS-Intel.zip)：解压后打开 `CarRacing-macOS-Intel/CarRacing.app`。 |
| 版权、署名与第三方许可 | [THIRD_PARTY_LICENSES.zip](https://github.com/AmoseCP/car-racing/releases/download/{{TAG}}/THIRD_PARTY_LICENSES.zip)：单独下载 EXE 时请一并保留。 |
| 构建信息与校验 | [BUILD_INFO.json](https://github.com/AmoseCP/car-racing/releases/download/{{TAG}}/BUILD_INFO.json) · [SHA256SUMS.txt](https://github.com/AmoseCP/car-racing/releases/download/{{TAG}}/SHA256SUMS.txt) |

不确定自己的 Mac 用哪种芯片：打开「苹果菜单 → 关于本机」，显示 Apple M1/M2/M3/M4 等的请下载 Apple Silicon 版，显示 Intel 的请下载 Intel 版。首次打开若被拦截，请右键选择「打开」。

验证情况：
- 本版本由 GitHub Actions 自动构建：{{RUN_URL}}
- 发布前，各安装包已在云端 Windows、Apple Silicon Mac 和 Intel Mac 上以无界面模式启动游戏并正常退出，运行日志中没有脚本错误。
- 云端机器没有显卡、手柄和掌机，画面渲染、手柄和 Windows 掌机尚未实机测试。Mac 应用使用 ad-hoc 签名，未通过 Apple 公证。
