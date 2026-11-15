import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'audio.dart';
import 'brand.dart';
import 'controller.dart';
import 'models.dart';
import 'palette.dart';
import 'recognition.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppController get c => widget.controller;
  int page = 0;
  String search = '';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      backgroundColor: c.acrylic ? const Color(0x52FFF9EE) : canvas,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: c.acrylic ? 0.48 : 1.0),
              border: const Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        appName,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        appEnglishName,
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          letterSpacing: .7,
                        ),
                      ),
                    ],
                  ),
                ),
                ...[
                  ('识曲', Icons.radar_rounded),
                  ('历史', Icons.history_rounded),
                  ('设置', Icons.tune_rounded),
                ].indexed.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: TextButton.icon(
                      onPressed: () => setState(() => page = item.$1),
                      style: TextButton.styleFrom(
                        foregroundColor: page == item.$1 ? accent : muted,
                        backgroundColor: page == item.$1
                            ? const Color(0xFFF7E8D7)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(item.$2.$2, size: 17),
                      label: Text(
                        item.$2.$1,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                IconButton(
                  tooltip: '退出$appName',
                  onPressed: () => NativeAudio.channel.invokeMethod('quit'),
                  icon: const Icon(
                    Icons.power_settings_new_rounded,
                    size: 18,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: switch (page) {
                    0 => dashboard(),
                    1 => historyPage(),
                    _ => settingsPage(),
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 12),
            child: Row(
              children: [
                Icon(
                  c.listening ? Icons.hearing_rounded : Icons.shield_outlined,
                  size: 13,
                  color: muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    c.listening
                        ? '正在采集所选设备 · 关闭窗口后托盘继续运行'
                        : '未采集系统声音 · 关闭窗口后留在托盘',
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ),
                const Text(
                  'v$appVersion',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  BoxDecoration surface({bool soft = false}) => BoxDecoration(
    color: soft
        ? const Color(0xFFF8EEDC).withValues(alpha: .75)
        : Colors.white.withValues(alpha: c.acrylic ? 0.78 : 1.0),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: line),
  );
  Widget panel(Widget child, {bool soft = false}) => Container(
    padding: const EdgeInsets.all(19),
    decoration: surface(soft: soft),
    child: child,
  );
  Widget heading(String title, {String? subtitle, Widget? trailing}) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: muted, height: 1.6),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );

  Widget dashboard() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.listening ? const Color(0xFF699477) : honey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.status,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 84,
                  height: 26,
                  child: CustomPaint(
                    painter: WavePainter(c.level, c.listening),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              c.detail,
              style: const TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => c.listening ? c.stop() : c.start(),
                  icon: Icon(
                    c.listening
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: Text(
                    c.listening ? '暂停识曲' : '开启自动识曲',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: c.busy ? null : c.recognizeNow,
                  icon: const Icon(Icons.bolt_rounded, size: 17),
                  label: const Text('识别一次', style: TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  onPressed: c.busy ? null : () => c.recognizeFile(),
                  icon: const Icon(Icons.audio_file_outlined, size: 17),
                  label: const Text('导入音频', style: TextStyle(fontSize: 12)),
                ),
                Text(
                  c.engine == 'parallel'
                      ? '网易云 + 酷狗 · 同时识别'
                      : c.engine == 'netease'
                      ? '仅网易云音乐'
                      : '仅酷狗音乐',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
            if (c.listening) ...[
              const SizedBox(height: 13),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: c.busy ? null : (c.bufferSeconds / 6).clamp(0, 1),
                  minHeight: 2,
                  color: honey,
                  backgroundColor: line,
                ),
              ),
            ],
          ],
        ),
      ),
      if (c.lastError != null) ...[
        const SizedBox(height: 12),
        panel(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 17, color: accent),
              const SizedBox(width: 9),
              Expanded(
                child: SelectableText(
                  c.lastError!,
                  style: const TextStyle(
                    color: accent,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
          soft: true,
        ),
      ],
      const SizedBox(height: 18),
      LayoutBuilder(
        builder: (context, constraints) {
          final main = resultPanel();
          final side = quickPanel();
          return constraints.maxWidth >= 840
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: 16),
                    SizedBox(width: 244, child: side),
                  ],
                )
              : Column(children: [main, const SizedBox(height: 14), side]);
        },
      ),
      const SizedBox(height: 18),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading(
              '最近听到',
              trailing: TextButton(
                onPressed: () => setState(() => page = 1),
                child: const Text('全部记录', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 8),
            if (c.history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '识别成功的歌曲会留在这里。',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              )
            else
              ...c.history
                  .take(2)
                  .map((entry) => historyRow(entry, compact: true)),
          ],
        ),
      ),
    ],
  );

  Widget resultPanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          '这段旋律',
          trailing: c.lastRecognized == null
              ? null
              : Text(
                  clock(c.lastRecognized!),
                  style: const TextStyle(color: muted, fontSize: 10),
                ),
        ),
        const SizedBox(height: 19),
        if (!c.hasLatest)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.album_outlined, color: honey, size: 45),
                SizedBox(width: 17),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '听到喜欢的，就留下来',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 9),
                      Text(
                        '播放一段音乐，或导入一个音频文件。',
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 61,
                height: 61,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1DDBB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.album_rounded, color: accent, size: 37),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      c.candidates.first.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    SelectableText(
                      c.candidates.first.artist,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    if (c.candidates.first.album.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        c.candidates.first.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: '复制歌名和歌手',
                onPressed: () => copySong(c.candidates.first),
                icon: const Icon(Icons.copy_rounded, size: 17, color: muted),
              ),
            ],
          ),
        const SizedBox(height: 19),
        const Divider(height: 1, color: line),
        const SizedBox(height: 13),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['netease', 'kugou'].map((engine) {
            final songs = c.candidates
                .where((s) => s.engine == engine)
                .toList();
            return OutlinedButton.icon(
              onPressed: songs.isEmpty ? null : () => showCandidates(songs),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                side: const BorderSide(color: line),
              ),
              icon: Icon(
                songs.isEmpty
                    ? Icons.music_note_outlined
                    : Icons.check_circle_outline_rounded,
                size: 14,
              ),
              label: Text(
                '${engine == 'netease' ? '网易云' : '酷狗'}${songs.isEmpty ? '' : ' · ${songs.length} 个候选'}',
                style: const TextStyle(fontSize: 11),
              ),
            );
          }).toList(),
        ),
        if (c.hasLatest) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => openSong(c.candidates.first),
            icon: const Icon(Icons.open_in_new_rounded, size: 14),
            label: const Text('在浏览器查看', style: TextStyle(fontSize: 11)),
          ),
        ],
      ],
    ),
  );
  Widget quickPanel() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          '聆听设置',
          trailing: IconButton(
            tooltip: '偏好设置',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => page = 2),
            icon: const Icon(Icons.tune_rounded, size: 17, color: muted),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          c.listening
              ? c.deviceName
              : c.deviceId.isEmpty
              ? '系统默认输出设备'
              : c.devices
                        .where((d) => d['id'] == c.deviceId)
                        .map((d) => d['name'])
                        .firstOrNull ??
                    '所选输出设备',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            const Text('检查间隔', style: TextStyle(color: muted, fontSize: 11)),
            const Spacer(),
            Text('${c.interval} 秒', style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('本地记录', style: TextStyle(color: muted, fontSize: 11)),
            const Spacer(),
            Text('${c.history.length} 条', style: const TextStyle(fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: showLogs,
          child: const Text('查看运行记录', style: TextStyle(fontSize: 11)),
        ),
      ],
    ),
    soft: true,
  );

  Widget historyPage() {
    final rows = c.history
        .where(
          (h) => '${h.song.title} ${h.song.artist}'.toLowerCase().contains(
            search.toLowerCase(),
          ),
        )
        .toList();
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(
            '识曲历史',
            subtitle: '跟随软件文件夹保存，最多保留 500 条。',
            trailing: TextButton.icon(
              onPressed: c.history.isEmpty ? null : confirmClear,
              icon: const Icon(Icons.delete_outline_rounded, size: 17),
              label: const Text('清空', style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 17),
          TextField(
            onChanged: (s) => setState(() => search = s),
            decoration: const InputDecoration(
              hintText: '搜索歌名或歌手',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 38),
              child: Center(
                child: Text(
                  search.isEmpty ? '还没有识曲记录' : '没有找到匹配的记录',
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ),
            )
          else
            ...rows.map((h) => historyRow(h)),
        ],
      ),
    );
  }

  Widget historyRow(HeardSong entry, {bool compact = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        const Icon(Icons.music_note_rounded, color: accent, size: 19),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${entry.song.artist} · ${entry.song.engineName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${entry.lastHeard.month}/${entry.lastHeard.day} ${clock(entry.lastHeard)}${entry.count > 1 ? ' · ${entry.count}次' : ''}',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
        if (!compact) ...[
          IconButton(
            tooltip: '复制',
            onPressed: () => copySong(entry.song),
            icon: const Icon(Icons.copy_rounded, size: 16, color: muted),
          ),
          IconButton(
            tooltip: '打开',
            onPressed: () => openSong(entry.song),
            icon: const Icon(Icons.open_in_new_rounded, size: 16, color: muted),
          ),
        ],
      ],
    ),
  );

  Widget settingsPage() => Column(
    children: [
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('识曲方式'),
            const SizedBox(height: 20),
            settingRow(
              '识曲引擎',
              '默认同时向两家发起识别，保留各自的候选结果。',
              DropdownButton<String>(
                value: c.engine,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'parallel', child: Text('双引擎并行')),
                  DropdownMenuItem(value: 'netease', child: Text('仅网易云音乐')),
                  DropdownMenuItem(value: 'kugou', child: Text('仅酷狗音乐')),
                ],
                onChanged: c.busy
                    ? null
                    : (v) {
                        if (v != null) c.setEngine(v);
                      },
              ),
            ),
            const Divider(height: 30, color: line),
            settingRow(
              '检查间隔',
              '首轮积累 6 秒；请求失败时延长重试间隔。',
              DropdownButton<int>(
                value: c.interval,
                underline: const SizedBox(),
                items: [12, 20, 30, 60]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n 秒')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) c.setInterval(v);
                },
              ),
            ),
            const Divider(height: 30, color: line),
            const Text(
              '输出设备',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '切换耳机或扬声器前，请先暂停识曲。',
              style: TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(c.deviceId),
                    initialValue: c.deviceId,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('系统默认输出设备', style: TextStyle(fontSize: 12)),
                      ),
                      ...c.devices.map(
                        (d) => DropdownMenuItem(
                          value: d['id'],
                          child: Text(
                            d['name']!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                    onChanged: c.listening
                        ? null
                        : (v) {
                            if (v != null) c.setDevice(v);
                          },
                  ),
                ),
                IconButton(
                  tooltip: '刷新设备',
                  onPressed: c.listening ? null : c.refreshDevices,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      panel(
        Column(
          children: [
            heading('外观与通知'),
            const SizedBox(height: 16),
            settingRow(
              '亚克力模糊',
              '暖色半透明背景；关闭后使用纯色背景。',
              Switch(value: c.acrylic, onChanged: c.setAcrylic),
            ),
            const Divider(height: 25, color: line),
            settingRow(
              '识别结果通知',
              '发现新歌曲时显示 Windows 托盘通知。',
              Switch(value: c.notifications, onChanged: c.setNotifications),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading('数据与隐私'),
            const SizedBox(height: 15),
            const Text(
              '记录与设置保存在程序同级的数据库中，移动软件文件夹即可一起带走。音频仅保留最近 12 秒内存缓存，不保存录音文件。',
              style: TextStyle(color: muted, fontSize: 12, height: 1.8),
            ),
            const SizedBox(height: 9),
            const Text(
              '识曲时向网易云发送音频指纹，向酷狗发送音频片段。两家服务的曲库与返回版本可能不同。',
              style: TextStyle(color: muted, fontSize: 12, height: 1.8),
            ),
            const SizedBox(height: 13),
            SelectableText(
              '${c.store.directory}\\lysia.sqlite',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            const Text(
              '导入格式：WAV、MP3、FLAC、OGG Vorbis、AAC、M4A、WMA。',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ],
  );
  Widget settingRow(String title, String subtitle, Widget control) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: const TextStyle(color: muted, fontSize: 11, height: 1.7),
            ),
          ],
        ),
      ),
      const SizedBox(width: 18),
      control,
    ],
  );
  Future<void> copySong(Song song) async {
    await Clipboard.setData(
      ClipboardData(text: '${song.title} - ${song.artist}'),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制歌名和歌手'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> openSong(Song song) async {
    try {
      await NativeAudio.channel.invokeMethod('openUrl', song.url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void showCandidates(List<Song> songs) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${songs.first.engineName} · 候选结果'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: songs
                .map(
                  (s) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.title, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      '${s.artist}\n${s.album}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '复制',
                      onPressed: () => copySong(s),
                      icon: const Icon(Icons.copy_rounded, size: 17),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  void showLogs() => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('运行记录'),
      content: SizedBox(
        width: 640,
        height: 320,
        child: SingleChildScrollView(
          child: SelectableText(
            c.logs.isEmpty ? '暂无记录。' : c.logs.join('\n\n'),
            style: const TextStyle(fontSize: 11, height: 1.8),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
  Future<void> confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空识曲历史？'),
        content: const Text('将删除本软件保存的所有识曲记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) c.clearHistory();
  }

  String clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class WavePainter extends CustomPainter {
  WavePainter(this.level, this.active);
  final double level;
  final bool active;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 18; i++) {
      final shape = .25 + .75 * math.sin(i * 1.7).abs();
      final height =
          4 +
          size.height *
              shape *
              (active ? (.1 + math.min(level * 9, .85)) : .08);
      p.color = active ? accent.withValues(alpha: .3 + shape * .6) : line;
      final x = 3 + i * (size.width - 6) / 17;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(WavePainter old) =>
      old.level != level || old.active != active;
}
