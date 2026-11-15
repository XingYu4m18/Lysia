import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class Fingerprinter {
  Fingerprinter(this.dataDirectory);
  final String dataDirectory;
  HeadlessInAppWebView? _view;
  Future<void>? _initializing;
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final wasm = await rootBundle.loadString('assets/afp/afp.wasm.js');
    final glue = await rootBundle.loadString('assets/afp/afp.js');
    final ready = Completer<void>();
    await Directory('$dataDirectory/cache/webview').create(recursive: true);
    final environment = await WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: '$dataDirectory/cache/webview',
      ),
    );
    _view = HeadlessInAppWebView(
      webViewEnvironment: environment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        isInspectable: false,
      ),
      initialData: InAppWebViewInitialData(
        data:
            '<!doctype html><html><head><meta charset="utf-8"></head><body><script>$wasm</script><script>$glue</script></body></html>',
      ),
      onLoadStop: (controller, url) async {
        if (ready.isCompleted) return;
        try {
          final exists = await controller.evaluateJavascript(
            source: 'typeof GenerateFP === "function"',
          );
          if (exists == true) {
            ready.complete();
          } else {
            ready.completeError(StateError('音频指纹模块未能加载'));
          }
        } catch (e) {
          ready.completeError(e);
        }
      },
      onReceivedError: (controller, request, error) {
        if (!ready.isCompleted) {
          ready.completeError(StateError('指纹运行环境启动失败：${error.description}'));
        }
      },
    );
    await _view!.run();
    await ready.future.timeout(const Duration(seconds: 20));
  }

  Future<String> generate(Uint8List pcm) async {
    try {
      await initialize();
    } catch (e) {
      _initializing = null;
      await _view?.dispose();
      _view = null;
      rethrow;
    }
    final result = await _view!.webViewController!
        .callAsyncJavaScript(
          functionBody: '''
      const bytes = Uint8Array.from(atob(pcm), c=>c.charCodeAt(0));
      const view = new DataView(bytes.buffer);
      const samples = new Float32Array(bytes.length/2);
      for(let i=0;i<samples.length;i++) samples[i]=view.getInt16(i*2,true)/32768;
      return await GenerateFP(samples);
    ''',
          arguments: {'pcm': base64Encode(pcm)},
        )
        .timeout(const Duration(seconds: 12));
    if (result?.error != null ||
        result?.value is! String ||
        (result!.value as String).isEmpty) {
      throw StateError(
        '无法生成音频指纹${result?.error == null ? '' : '：${result!.error}'}',
      );
    }
    return result.value as String;
  }

  Future<void> dispose() async {
    await _view?.dispose();
    _view = null;
  }
}
