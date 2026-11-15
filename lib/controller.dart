import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'audio.dart';
import 'models.dart';
import 'recognition.dart';
import 'storage.dart';
import 'effects.dart';

class AppController extends ChangeNotifier {
  AppController(this.store, this.recognizer) {
    engine = store.setting('engine', 'parallel');
    if (engine == 'auto' ||
        !['parallel', 'netease', 'kugou'].contains(engine)) {
      engine = 'parallel';
    }
    interval = int.tryParse(store.setting('interval', '20')) ?? 20;
    if (![12, 20, 30, 60].contains(interval)) interval = 20;
    notifications = store.setting('notifications', 'true') == 'true';
    acrylic = store.setting('acrylic', 'true') == 'true';
    deviceId = store.setting('device', '');
    history = store.history();
    NativeAudio.channel.setMethodCallHandler((call) async {
      if (call.method == 'trayToggle') {
        if (listening) {
          await stop();
        } else {
          await start();
        }
      }
    });
  }
  final LocalStore store;
  final RecognitionService recognizer;
  final NativeAudio audio = NativeAudio();
  List<Map<String, String>> devices = [];
  List<HeardSong> history = [];
  List<Song> candidates = [];
  final List<String> logs = [];
  String engine = 'auto',
      deviceId = '',
      status = '准备就绪',
      detail = '开启后，识别这台电脑正在播放的音乐。',
      deviceName = '系统默认输出设备';
  String? lastError;
  int interval = 20;
  bool notifications = true, listening = false, busy = false, automatic = true;
  bool acrylic = true;
  double level = 0, bufferSeconds = 0;
  DateTime? lastRecognized;
  Timer? _timer;
  bool _polling = false;
  int _session = 0, _lastSequence = 0, _failures = 0;
  DateTime _next = DateTime.now(), _started = DateTime.now();
  String _lastNotified = '';
  DateTime? _notificationTime;
  bool get hasLatest => candidates.isNotEmpty;
  int get countdown => _next.difference(DateTime.now()).inSeconds.clamp(0, 120);
  void log(String text) {
    logs.insert(
      0,
      '${DateTime.now().toIso8601String().substring(11, 19)}  $text',
    );
    if (logs.length > 80) logs.removeLast();
  }

  Future<void> refreshDevices() async {
    try {
      devices = await audio.devices();
      if (deviceId.isNotEmpty && !devices.any((e) => e['id'] == deviceId)) {
        deviceId = '';
      }
      notifyListeners();
    } catch (e) {
      lastError = '无法读取输出设备：${friendlyError(e)}';
      notifyListeners();
    }
  }

  Future<void> start({bool auto = true}) async {
    if (listening) return;
    final token = ++_session;
    automatic = auto;
    listening = true;
    busy = false;
    lastError = null;
    _failures = 0;
    _lastSequence = 0;
    level = 0;
    bufferSeconds = 0;
    _started = DateTime.now();
    _next = _started;
    status = '正在连接系统声音';
    detail = '请在浏览器、播放器或其他应用中播放音乐。';
    notifyListeners();
    try {
      await audio.start(deviceId);
      if (token != _session) return;
      await NativeAudio.channel.invokeMethod('setListening', true);
      _timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _poll(),
      );
      log(auto ? '已开启自动识曲' : '开始采集，准备识别一次');
    } catch (e) {
      await stop();
      lastError = friendlyError(e);
      status = '无法开始采集';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    ++_session;
    _timer?.cancel();
    _timer = null;
    recognizer.cancel();
    listening = false;
    busy = false;
    level = 0;
    bufferSeconds = 0;
    await audio.stop();
    await NativeAudio.channel.invokeMethod('setListening', false);
    status = '已暂停';
    detail = '再次开启即可继续识别系统音乐。';
    log('已停止采集和识曲');
    notifyListeners();
  }

  Future<void> _poll() async {
    if (_polling || !listening) return;
    _polling = true;
    final token = _session;
    try {
      final info = await audio.status();
      if (token != _session) return;
      if (info.error.isNotEmpty) {
        await stop();
        lastError = '音频设备不可用，请检查输出设备后重新开始。\n${info.error}';
        status = '采集已停止';
        log(info.error);
        notifyListeners();
        return;
      }
      if (!info.running && DateTime.now().difference(_started).inSeconds > 8) {
        throw StateError('连接输出设备超时');
      }
      level = info.level;
      bufferSeconds = info.samples / 8000;
      if (info.device.isNotEmpty) deviceName = info.device;
      if (!busy) {
        if (bufferSeconds < 6) {
          status = '正在等待声音';
          detail = bufferSeconds > 0
              ? '已采集 ${bufferSeconds.toStringAsFixed(1)} / 6 秒'
              : '请播放音乐；耳机和扬声器均可。';
        } else if (level < 0.0015) {
          status = '正在等待音乐';
          detail = '当前声音很轻或处于静音，暂不提交识别。';
        } else if (DateTime.now().isBefore(_next)) {
          status = '自动识曲中';
          detail = '$countdown 秒后再次检查 · 同一首歌自动合并';
        }
        if (info.samples >= 48000 &&
            info.sequence - _lastSequence >= 16000 &&
            !DateTime.now().isBefore(_next) &&
            level >= 0.0015) {
          final pcm = await audio.snapshot();
          if (token != _session) return;
          if (pcm.length >= 96000 && pcmRms(pcm) >= 0.0015) {
            _lastSequence = info.sequence;
            unawaited(_recognize(pcm, token));
          }
        }
      }
      notifyListeners();
    } catch (e) {
      if (token == _session) {
        await stop();
        lastError = friendlyError(e);
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> recognizeNow() async {
    if (busy) return;
    if (!listening) {
      await start(auto: false);
      return;
    }
    _next = DateTime.now();
    _lastSequence = 0;
    status = '准备立即识别';
    notifyListeners();
  }

  Future<void> recognizeFile([String? path]) async {
    if (busy) return;
    path ??= await NativeAudio.channel.invokeMethod<String>('chooseAudio');
    if (path == null) return;
    final token = _session;
    busy = true;
    status = '正在读取音频';
    lastError = null;
    notifyListeners();
    try {
      final file = File(path);
      if (await file.length() > 100 * 1024 * 1024) {
        throw const FormatException('请选择小于 100 MB 的音频文件');
      }
      final pcm = await audio.decodeFile(path);
      if (token != _session) return;
      busy = false;
      if (pcmRms(pcm) < 0.0015) {
        status = '音频接近静音';
        detail = '请选择包含清晰音乐的音频文件。';
        return;
      }
      await _recognize(pcm, token, fromFile: true);
    } catch (e) {
      if (token == _session) {
        lastError = friendlyError(e);
        status = '音频识别失败';
      }
    } finally {
      if (token == _session) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _recognize(
    Uint8List pcm,
    int token, {
    bool fromFile = false,
  }) async {
    if (busy) return;
    busy = true;
    lastError = null;
    status = '正在识别';
    detail = '正在准备音频片段…';
    notifyListeners();
    try {
      final result = await recognizer.recognize(pcm, engine, (message) {
        if (token == _session) {
          detail = message;
          notifyListeners();
        }
      });
      if (token != _session) return;
      for (final note in result.notes) {
        log(note);
      }
      if (result.songs.isNotEmpty) {
        candidates = result.songs;
        final song = candidates.first;
        final now = DateTime.now();
        store.remember(song, now);
        history = store.history();
        lastRecognized = now;
        _failures = 0;
        status = '识别成功';
        detail = '${song.title} · ${song.artist}';
        if (notifications &&
            (_lastNotified != song.identity ||
                _notificationTime == null ||
                now.difference(_notificationTime!).inMinutes >= 3)) {
          _lastNotified = song.identity;
          _notificationTime = now;
          unawaited(
            NativeAudio.channel
                .invokeMethod('notify', '${song.title}\n${song.artist}')
                .catchError((_) {}),
          );
        }
      } else {
        final failed = result.notes.any((n) => !n.contains('无匹配'));
        _failures = failed ? (_failures + 1).clamp(0, 3) : 0;
        status = failed ? '本次请求未成功' : '暂未识别到歌曲';
        detail = failed ? '网络或识曲服务暂时不可用，将延长间隔后重试。' : '将继续检查后续片段，也可以切换识曲引擎。';
        if (failed) lastError = result.notes.join('\n');
      }
      _next = DateTime.now().add(
        Duration(seconds: (interval * (1 << _failures)).clamp(interval, 120)),
      );
    } catch (e) {
      if (token == _session) {
        lastError = friendlyError(e);
        status = '识曲暂时失败';
        detail = '请稍后重试。';
        _next = DateTime.now().add(const Duration(seconds: 40));
        log(lastError!);
      }
    } finally {
      if (token == _session) {
        busy = false;
        if (listening && !automatic && !fromFile) {
          final savedStatus = status, savedDetail = detail;
          await stop();
          status = savedStatus;
          detail = savedDetail;
        }
        notifyListeners();
      }
    }
  }

  void setEngine(String value) {
    engine = value;
    store.saveSetting('engine', value);
    notifyListeners();
  }

  void setInterval(int value) {
    interval = value;
    store.saveSetting('interval', '$value');
    notifyListeners();
  }

  void setNotifications(bool value) {
    notifications = value;
    store.saveSetting('notifications', '$value');
    notifyListeners();
  }

  Future<void> setAcrylic(bool value) async {
    try {
      await WindowEffects.setAcrylic(value);
      acrylic = value;
      store.saveSetting('acrylic', '$value');
    } catch (e) {
      lastError = '当前环境无法切换模糊效果：${friendlyError(e)}';
    }
    notifyListeners();
  }

  void setDevice(String value) {
    deviceId = value;
    store.saveSetting('device', value);
    notifyListeners();
  }

  void clearHistory() {
    store.clearHistory();
    history = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    recognizer.cancel();
    NativeAudio.channel.setMethodCallHandler(null);
    super.dispose();
  }
}
