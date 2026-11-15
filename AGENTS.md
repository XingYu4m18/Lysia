# 聆汐 · Lysia 开发交接

本文件供后续开发者和编码代理接手。先读 README.md、THIRD_PARTY.md、assets/afp/README.md，再修改相关模块。用户的新指令优先于这里记录的默认约定。

## 已确认的方向

- 产品名称固定为“聆汐 · Lysia”，应用版本目前为 0.2.0+2。品牌常量在 lib/brand.dart；窗口、托盘、Windows 版本资源也需同步。
- 保持 Flutter + Dart 界面与业务逻辑，Windows 原生部分用 C++。曾讨论 Rust，最终决定继续 Flutter，不要自行重写框架。
- 先完成 Windows。Android 是后续方向；洛雪播放器集成已暂缓，尚无相关实现。
- 默认同时向网易云和酷狗发起识别。两家结果都保留，一家失败不能抹掉另一家的成功结果。保留单平台设置。
- 界面以橙白、暖黄为主，首页紧凑，支持关闭亚克力。不恢复蓝白大卡片风格。
- 历史、设置位于 EXE 同级，保持便携使用。不得擅自改回用户目录或云存储。

## 结构与数据流

- lib/main.dart：初始化、便携存储、桌面窗口、测试入口。
- lib/controller.dart：采集状态、定时识别、静音过滤、结果与历史；通过会话编号丢弃暂停后的过期结果。
- lib/recognition.dart：HTTP 请求、并行调度、取消、两家响应解析。并行启动后再等待，不能改回顺序回退。
- lib/fingerprint.dart：WebView2 中运行 AFP JS/WASM，将 PCM 转换为网易云指纹。缓存写到程序目录 cache/webview。
- lib/audio.dart：原生音频桥接及 WAV 工具。
- lib/storage.dart：SQLite 设置与历史，连续命中合并，最多 500 条。首次创建便携库时只读复制旧版默认位置，不修改原库。
- lib/home_page.dart、palette.dart、effects.dart：界面、配色、亚克力。
- windows/runner/audio_capture.*：WASAPI loopback，采集系统输出，内存环形缓冲，不保存录音。
- windows/runner/audio_decode.*、vorbis_decode.cpp：Media Foundation 解码与 OGG Vorbis 补充解码。耗时文件解码在工作线程进行，通过窗口消息回主线程提交结果，退出时回收线程。
- windows/runner/flutter_window.*：平台通道、托盘、文件选择。
- windows/runner/vendor/stb_vorbis.c：第三方源码，保留许可，不随意改动。

识别输入为 8 kHz、单声道、16-bit little-endian PCM，通常截取约 6 秒；文件至少 3 秒。支持 WAV、MP3、FLAC、OGG Vorbis、AAC、M4A、WMA。OGG Opus 尚不支持；其他编码受系统媒体组件影响。

## 开发与构建

已验证工具链为 Flutter 3.50 / Dart 3.14、Visual Studio 2026 桌面 C++、Windows SDK、NuGet CLI。运行程序只需相应 Windows 组件与 WebView2，不需要 Flutter/Python。

1. 按 assets/afp/README.md 准备有权使用的本地 AFP 文件；公开仓库刻意不包含它们。
2. `flutter pub get`
3. `flutter analyze`
4. `flutter test`
5. `powershell -File tool/build_windows.ps1`

构建脚本将源码复制到 C:/tj-build/app（ASCII 路径），规避本机中文路径/长路径构建问题，再输出到仓库同级 outputs/聆汐-Lysia-v0.2.0-Windows-x64。复制过程中不要使用会删除用户数据的镜像同步。直接从中文路径执行 flutter build 在本机曾出问题。

内部 Dart 包名仍为 tingjian；这是历史实现细节，界面品牌是 Lysia。改包名需要同步所有 package 导入。VS 工具链的 WebView 插件弃用宏和 /utf-8 已在 CMake 中处理。升级工具链时核对这些兼容设置。

## 验证方法与已验证范围

- test/core_test.dart 当前 8 项测试，覆盖 WAV、空响应、并行屏障、单侧失败、取消、迁移、历史持久化及最小窗口布局。不要为了维持数量写镜像实现的测试。
- 当前静态检查与 8 项测试通过，但不能将本记录当作未来修改后的测试结果；按改动重新执行相关检查。
- 原生文件解码与真实接口已在 WAV、MP3、FLAC、OGG Vorbis、AAC、M4A、WMA 公共样本上通过；真实 WASAPI 内录也通过。这不是对任意编码/所有 Windows 版本的保证。
- tool/verify_windows.py 接受 EXE、明确提供的公共 WAV、报告目录，验证文件识别和系统播放。它会播放并向服务提交该公共测试音频，勿改成扫描或上传用户音乐。
- 开发测试参数 --verify-file、--verify-output、--verify-dir 见 main.dart；所有验证使用独立 --verify-dir，防止污染真实历史。
- Windows 上人工检查正常与最小尺寸 900x640、历史、设置、托盘、退出及模糊效果。亚克力受环境影响，保留纯色回退。

## 发布与隐私边界

- 项目原创代码采用 PolyForm Noncommercial 1.0.0，允许许可规定的非商业使用、修改、再分发。禁止商用；准确表述为源码可用，不称作 OSI 开源。
- README 中的 Required Notice 与 LICENSE 随再分发保留。第三方依赖各按原许可，本项目许可不能覆盖其权利。
- AFP 文件授权尚未核实：保留忽略规则，不提交这两个文件、不公开包含它们的可执行包；先取得并记录许可依据再改变该决定。本地可用不代表可以公开分发。
- 公开仓库提交源码、锁文件、图标和必要声明，不提交 build、.dart_tool、cache、数据库、测试音频、环境密钥、私有日志或本机绝对路径报告。
- 打包用运行文件白名单，包含 DLL、Flutter data、说明和必要许可；排除 lysia.sqlite、-wal、-shm、cache 和测试音频。不得删除用户现有数据库来做“干净打包”。
- 用户数据库可能存在于旧版 %LOCALAPPDATA%/Tingjian 或新版 EXE 同级。备份/移动前应完整退出；不要单独搬动正在使用的 WAL 数据库。
- 采集启动由用户明确操作；不改为启动即采集。网易云接收指纹，酷狗接收短 PCM 片段；保持说明真实。
- 当前接口属于客户端接口，可能改变，不保证平台长期可用。协议签名常量不等于用户密钥，仍不得提交真实用户凭证。

## 后续候选工作

在用户确定优先级后，再处理无 AFP 的酷狗独立构建、取得可分发的指纹实现、Android 采集适配、安装包或洛雪集成。不要将这些写成已经完成的能力。
