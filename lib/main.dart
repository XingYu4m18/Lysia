import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'audio.dart';
import 'controller.dart';
import 'fingerprint.dart';
import 'recognition.dart';
import 'storage.dart';
import 'brand.dart';
import 'palette.dart';
import 'effects.dart';
import 'home_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  String? arg(String prefix) {
    for (final s in args) {
      if (s.startsWith('$prefix=')) return s.substring(prefix.length + 1);
    }
    return null;
  }

  try {
    final store = arg('--verify-dir') == null
        ? LocalStore.openPortable()
        : LocalStore(arg('--verify-dir')!);
    final service = RecognitionService(Fingerprinter(store.directory));
    final controller = AppController(store, service);
    try {
      await WindowEffects.setAcrylic(controller.acrylic);
    } catch (e) {
      controller.acrylic = false;
      controller.log('已使用纯色窗口背景');
    }
    runApp(TingjianApp(controller: controller));
    unawaited(controller.refreshDevices());
    if (arg('--verify-output') != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final output = File(arg('--verify-output')!);
        final result = <String, Object?>{
          'stage': 'started',
          'portableDirectory': store.directory,
          'acrylic': controller.acrylic,
        };
        await output.writeAsString(jsonEncode(result));
        try {
          final file = arg('--verify-file');
          final pcm = file != null
              ? await controller.audio.decodeFile(file)
              : await (() async {
                  await controller.audio.start('');
                  await Future<void>.delayed(const Duration(seconds: 9));
                  final state = await controller.audio.status();
                  result['capture'] = {
                    'running': state.running,
                    'samples': state.samples,
                    'level': state.level,
                    'error': state.error,
                    'device': state.device,
                  };
                  final bytes = await controller.audio.snapshot();
                  await controller.audio.stop();
                  if (bytes.length < 96000) throw StateError('系统内录不足六秒');
                  return bytes;
                })();
          result['rms'] = pcmRms(pcm);
          final batch = await service.recognize(pcm, 'parallel', (_) {});
          result['netease'] = batch.songs
              .where((s) => s.engine == 'netease')
              .map((s) => s.toJson())
              .toList();
          result['kugou'] = batch.songs
              .where((s) => s.engine == 'kugou')
              .map((s) => s.toJson())
              .toList();
          result['notes'] = batch.notes;
          result['stage'] = 'complete';
        } catch (e, st) {
          result['stage'] = 'failed';
          result['error'] = '$e';
          result['stack'] = '$st';
        }
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert(result),
        );
        await service.fingerprinter.dispose();
        await NativeAudio.channel.invokeMethod('quit');
      });
    }
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SelectableText('$appName 未能启动\n$e')),
        ),
      ),
    );
  }
}

class TingjianApp extends StatelessWidget {
  const TingjianApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Microsoft YaHei UI',
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, fontSize: 14),
        bodyLarge: TextStyle(color: ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          side: const BorderSide(color: Color(0xFFDDE2ED)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: HomePage(controller: controller),
  );
}
