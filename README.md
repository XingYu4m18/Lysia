# 聆汐 · Lysia

Windows 系统音乐识别，Flutter + Dart 界面和业务逻辑，C++ WASAPI 系统内录。

> 公开源码与下载包不包含分发许可尚未确认的网易云 AFP 第三方组件。公开包可使用酷狗；网易云需自行准备有权使用的本地组件，见 [组件说明](assets/afp/README.md)。完整双平台识别验证是在本机已准备组件的环境中完成的。

## v0.2.0

- 新名称：聆汐 / Lysia；橙白与暖黄配色，紧凑首页。
- 默认并行请求网易云和酷狗；保留两家的候选结果，任一路失败不丢弃另一路成功结果。
- 系统内录、识别一次与音频文件导入。
- 文件支持 WAV、MP3、FLAC、OGG Vorbis、AAC、M4A、WMA；Windows Media Foundation 解码大多数格式，内置 stb_vorbis 补充 OGG Vorbis。
- 亚克力背景效果，可在设置中关闭。系统限制可能导致个别电脑显示纯色。
- 历史和设置保存在 lysia.exe 同级的 lysia.sqlite；首次启动会复制旧版 %LOCALAPPDATA%/Tingjian/tingjian.sqlite 的数据，不修改原始数据库。
- 识曲历史连续命中合并，最多 500 条，支持搜索和清空。
- 托盘常驻、结果通知、输出设备和检查间隔设置。

## 使用

从 [Releases](https://github.com/XingYu4m18/Lysia/releases) 下载并完整解压 Windows 程序包后运行 lysia.exe，点击“开启自动识曲”，在对应输出设备上播放音乐。首次系统识曲需要积累约 6 秒音频。文件导入要求至少 3 秒，较长文件会取前部的 6 秒片段用于识别。公开包未补齐组件时建议在设置中选择酷狗；默认并行模式也能返回酷狗结果，并在运行记录中报告网易云缺少组件。

关闭窗口后留在托盘，右击可暂停或退出，窗口右上角电源按钮也可退出。启动时不会自动采集。输出设备断开后重新选择并开启。

请把程序解压到有写入权限的目录；移动整个程序文件夹时请先退出软件。保留 DLL 和 data 资源文件夹。不要只拷贝 EXE。应用无需安装 Flutter 或 Python，网易云指纹计算需要系统 WebView2 Runtime。

## 数据

- lysia.sqlite：记录和设置，与 EXE 同级。
- lysia.sqlite-wal / lysia.sqlite-shm：SQLite 运行期间可能产生的文件。
- cache/webview：指纹计算使用的 WebView 缓存。
- 音频仅缓存最近 12 秒内存数据，不保存录音。
- 识曲时向网易云发送音频指纹，向酷狗发送短音频片段。

便携压缩包不包含本机历史、设置、缓存或音乐测试样本。

## 开发

Flutter 3.50 / Dart 3.14，Visual Studio 2026 桌面 C++ 工具，Windows SDK，NuGet CLI。

完整本机构建需先准备 `assets/afp/afp.js` 与 `assets/afp/afp.wasm.js`，见 [组件说明](assets/afp/README.md)。不含组件的公开包可直接使用 `powershell -File tool/build_windows.ps1 -PublicRelease` 构建。

- flutter pub get
- flutter analyze
- flutter test
- powershell -File tool/build_windows.ps1

构建脚本在 C:/tj-build/app 中构建，规避中文路径和 Windows 长路径限制，然后复制到 outputs。第三方指纹和解码器来源见 THIRD_PARTY.md。

## 验证与边界

已在本机 Windows 11 x64 测试系统内录及 WAV、MP3、FLAC、OGG Vorbis、AAC、M4A、WMA 解码识曲，两家接口均命中公开测试歌曲。8 项测试覆盖解析、并行调用、取消、历史持久化、迁移和小窗口布局。

尚未在所有 Windows 版本及第三方音频文件上验证。部分特殊编码、受保护文件或缺少系统媒体组件的 Windows 版本可能无法解码。OGG 支持 Vorbis，不代表包含 Opus 编码的 OGG 文件也可读取。第一版仍使用静音过滤和定时查询，不含音乐/人声分类模型。

## 许可

项目原创代码采用 [PolyForm Noncommercial License 1.0.0](LICENSE)。允许在许可规定的非商业用途下使用、修改和再分发；商业用途不在本许可授权范围内。再分发时须保留许可条款和必要声明。以英文许可原文为准。

Required Notice: Copyright (c) 2026 XingYu4m18. Lysia / 聆汐.

禁止商用意味着本项目是“源码可用”，并非符合 OSI 定义的开源软件。第三方依赖保留各自许可，本项目许可不替代或扩大第三方权利，详见 [THIRD_PARTY.md](THIRD_PARTY.md)。

开发交接见 [AGENTS.md](AGENTS.md)。目前仅完成 Windows 版本，Android 与洛雪插件集成尚未实现。
