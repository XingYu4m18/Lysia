import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'models.dart';

class NativeAudio {
  Future<Uint8List> decodeFile(String path) async =>
      await channel.invokeMethod<Uint8List>('decodeAudio', path) ??
      Uint8List(0);
  static const channel = MethodChannel('tingjian/native');
  Future<List<Map<String, String>>> devices() async {
    final list = await channel.invokeListMethod<dynamic>('devices') ?? [];
    return list.map((e) => Map<String, String>.from(e as Map)).toList();
  }

  Future<void> start(String id) => channel.invokeMethod('captureStart', id);
  Future<void> stop() => channel.invokeMethod('captureStop');
  Future<CaptureInfo> status() async => CaptureInfo(
    await channel.invokeMapMethod<dynamic, dynamic>('captureStatus') ?? {},
  );
  Future<Uint8List> snapshot() async =>
      await channel.invokeMethod<Uint8List>('snapshot') ?? Uint8List(0);
}

double pcmRms(Uint8List pcm) {
  if (pcm.length < 2) return 0;
  final data = ByteData.sublistView(pcm);
  double total = 0;
  for (int i = 0; i + 1 < pcm.length; i += 2) {
    final x = data.getInt16(i, Endian.little) / 32768;
    total += x * x;
  }
  return math.sqrt(total / (pcm.length ~/ 2));
}

/// Decode uncompressed RIFF/WAVE; take a six-second window from the middle.
Uint8List wavToPcm(Uint8List bytes) {
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('请选择标准 WAV 音频文件');
  }
  final data = ByteData.sublistView(bytes);
  int format = 0,
      channels = 0,
      rate = 0,
      bits = 0,
      align = 0,
      start = 0,
      length = 0;
  for (int pos = 12; pos + 8 <= bytes.length;) {
    final name = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = data.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (body + size > bytes.length) throw const FormatException('WAV 文件不完整');
    if (name == 'fmt ' && size >= 16) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      rate = data.getUint32(body + 4, Endian.little);
      align = data.getUint16(body + 12, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
      if (format == 65534 && size >= 40) {
        format = data.getUint16(body + 24, Endian.little);
      }
    }
    if (name == 'data') {
      start = body;
      length = size;
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  if (channels < 1 ||
      channels > 32 ||
      rate < 8000 ||
      rate > 384000 ||
      align != channels * (bits ~/ 8) ||
      !((format == 1 && [16, 24, 32].contains(bits)) ||
          (format == 3 && bits == 32)) ||
      length == 0) {
    throw const FormatException('支持 16/24/32 位 PCM 或 32 位浮点 WAV，采样率至少 8 kHz');
  }
  final frames = length ~/ align;
  if (frames < rate * 6) throw const FormatException('音频需要至少 6 秒');
  final offset = (frames - rate * 6) ~/ 2;
  double sample(int frame) {
    double sum = 0;
    for (int ch = 0; ch < channels; ch++) {
      final p = start + frame * align + ch * (bits ~/ 8);
      double value;
      if (format == 3) {
        value = data.getFloat32(p, Endian.little);
      } else if (bits == 16) {
        value = data.getInt16(p, Endian.little) / 32768;
      } else if (bits == 32) {
        value = data.getInt32(p, Endian.little) / 2147483648;
      } else {
        int v = bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16);
        if (v & 0x800000 != 0) v -= 0x1000000;
        value = v / 8388608;
      }
      sum += value.isFinite ? value : 0;
    }
    return sum / channels;
  }

  final out = Uint8List(96000);
  final view = ByteData.sublistView(out);
  for (int i = 0; i < 48000; i++) {
    final position = offset + i * rate / 8000;
    final low = position.floor();
    final frac = position - low;
    final value =
        sample(low) * (1 - frac) + sample(math.min(low + 1, frames - 1)) * frac;
    view.setInt16(
      i * 2,
      (value.clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return out;
}
