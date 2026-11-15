import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/open.dart';
import 'package:tingjian/audio.dart';
import 'package:tingjian/controller.dart';
import 'package:tingjian/fingerprint.dart';
import 'package:tingjian/main.dart';
import 'package:tingjian/models.dart';
import 'package:tingjian/recognition.dart';
import 'package:tingjian/storage.dart';

const sampleSong = Song(
  title: '测试歌曲',
  artist: '测试歌手',
  engine: 'netease',
  trackId: '123',
);

class FakeRecognizer extends RecognitionService {
  FakeRecognizer() : super(Fingerprinter('unused'));
  int fallbackCalls = 0;
  Future<List<Song>> Function()? first;
  Future<List<Song>> Function()? second;
  @override
  Future<List<Song>> netease(Uint8List pcm) =>
      first?.call() ?? Future.value([]);
  @override
  Future<List<Song>> kugou(Uint8List pcm) async {
    fallbackCalls++;
    return await (second?.call() ?? Future.value([sampleSong]));
  }
}

Uint8List wave({int rate = 16000, int seconds = 6}) {
  final bytes = Uint8List(44 + rate * seconds * 2);
  final data = ByteData.sublistView(bytes);
  void label(int start, String value) {
    bytes.setRange(start, start + value.length, value.codeUnits);
  }

  label(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  label(8, 'WAVE');
  label(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  label(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  for (int i = 0; i < rate * seconds; i++) {
    data.setInt16(
      44 + i * 2,
      (sin(i * 2 * pi * 440 / rate) * 16000).round(),
      Endian.little,
    );
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
  test(
    'WAV resampling preserves a six-second signal and rejects short/truncated files',
    () {
      final pcm = wavToPcm(wave());
      expect(pcm.length, 96000);
      expect(pcmRms(pcm), closeTo(0.345, 0.02));
      expect(() => wavToPcm(wave(seconds: 2)), throwsFormatException);
      expect(() => wavToPcm(wave().sublist(0, 60)), throwsFormatException);
      expect(pcmRms(Uint8List(96000)), 0);
    },
  );
  test('provider no-match payloads are empty, not successful song results', () {
    expect(
      parseNetease({
        'code': 200,
        'data': {'result': null},
      }),
      isEmpty,
    );
    expect(parseKugou({'status': 1, 'data': {}}), isEmpty);
    final songs = parseNetease({
      'data': {
        'result': [
          {
            'song': {
              'id': 12,
              'name': 'Song',
              'artists': [
                {'name': 'Artist'},
              ],
              'album': {'name': 'Album'},
            },
          },
          {
            'song': {'id': 12, 'name': 'Song'},
          },
        ],
      },
    });
    expect(songs.length, 1);
    expect(songs.first.artist, 'Artist');
    expect(songs.first.url, 'https://music.163.com/song?id=12');
  });
  test(
    'parallel mode retains a successful provider when the other has no match or a network failure',
    () async {
      final fake = FakeRecognizer();
      expect(
        (await fake.recognize(Uint8List(10), 'auto', (_) {})).songs.length,
        1,
      );
      fake.first = () => Future.error(const SocketException('offline'));
      final batch = await fake.recognize(Uint8List(10), 'auto', (_) {});
      expect(batch.songs.length, 1);
      expect(batch.notes.first, contains('网络连接失败'));
      expect(fake.fallbackCalls, 2);
    },
  );
  test(
    'single engine selection and cancelled parallel results are respected',
    () async {
      final fake = FakeRecognizer();
      expect(
        (await fake.recognize(Uint8List(10), 'netease', (_) {})).songs,
        isEmpty,
      );
      expect(fake.fallbackCalls, 0);
      final pending = Completer<List<Song>>();
      fake.first = () => pending.future;
      final request = fake.recognize(Uint8List(10), 'auto', (_) {});
      fake.cancel();
      pending.complete([]);
      await expectLater(request, throwsStateError);
      expect(fake.fallbackCalls, 1);
    },
  );
  test(
    'parallel providers both start before either result completes',
    () async {
      final fake = FakeRecognizer();
      final a = Completer<List<Song>>(), b = Completer<List<Song>>();
      bool firstStarted = false, secondStarted = false, finished = false;
      fake.first = () {
        firstStarted = true;
        return a.future;
      };
      fake.second = () {
        secondStarted = true;
        return b.future;
      };
      final request = fake.recognize(Uint8List(10), 'parallel', (_) {}).then((
        result,
      ) {
        finished = true;
        return result;
      });
      expect(firstStarted, true);
      expect(secondStarted, true);
      b.complete([
        const Song(
          title: '来自酷狗',
          artist: '歌手',
          engine: 'kugou',
          trackId: '456',
        ),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      a.complete([sampleSong]);
      final result = await request;
      expect(result.songs.map((s) => s.engine), ['netease', 'kugou']);
      expect(result.notes.length, 2);
    },
  );
  test(
    'portable migration preserves settings and history without changing the original',
    () {
      final root = Directory.systemTemp.createTempSync('shiyin-migrate-');
      final old = LocalStore('${root.path}/old');
      old.saveSetting('interval', '30');
      old.remember(sampleSong, DateTime(2026, 11, 15));
      old.close();
      final store = LocalStore('${root.path}/portable');
      store.importLegacy('${root.path}/old/lysia.sqlite');
      expect(store.setting('interval', '20'), '30');
      expect(store.history().single.song.title, sampleSong.title);
      store.clearHistory();
      store.close();
      final reopened = LocalStore('${root.path}/old');
      expect(reopened.history().length, 1);
      reopened.close();
      expect(File('${root.path}/portable/lysia.sqlite').existsSync(), true);
      root.deleteSync(recursive: true);
    },
  );
  test(
    'history merges consecutive matches, persists, and keeps later sessions separate',
    () {
      final temp = Directory.systemTemp.createTempSync('tingjian-test-');
      var store = LocalStore(temp.path);
      final now = DateTime(2026, 11, 15, 12);
      store.remember(sampleSong, now);
      store.remember(sampleSong, now.add(const Duration(seconds: 20)));
      expect(store.history().length, 1);
      expect(store.history().first.count, 2);
      store.saveSetting('engine', 'kugou');
      store.close();
      store = LocalStore(temp.path);
      expect(store.setting('engine', 'auto'), 'kugou');
      expect(store.history().first.count, 2);
      store.remember(sampleSong, now.add(const Duration(minutes: 8)));
      expect(store.history().length, 2);
      store.clearHistory();
      expect(store.history(), isEmpty);
      store.close();
      temp.deleteSync(recursive: true);
    },
  );
  testWidgets('dashboard, history and settings fit the minimum window size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('tingjian-ui-test-');
    final store = LocalStore(temp.path);
    final controller = AppController(store, FakeRecognizer());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      NativeAudio.channel,
      (call) async => null,
    );
    await tester.pumpWidget(TingjianApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('开启自动识曲'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.text('还没有识曲记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('双引擎并行'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    store.close();
    temp.deleteSync(recursive: true);
  });
}
