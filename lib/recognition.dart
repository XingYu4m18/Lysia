import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'fingerprint.dart';
import 'models.dart';

class RecognitionService {
  RecognitionService(this.fingerprinter);
  final Fingerprinter fingerprinter;
  final Set<HttpClient> _clients = {};
  int _generation = 0;
  void cancel() {
    _generation++;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
  }

  Future<Map<String, dynamic>> _request(
    Uri uri, {
    Uint8List? body,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    _clients.add(client);
    try {
      return await (() async {
        final request = await client.openUrl(
          body == null ? 'GET' : 'POST',
          uri,
        );
        headers.forEach(request.headers.set);
        if (body != null) request.add(body);
        final response = await request.close();
        final content = await utf8.decoder.bind(response).join();
        if (response.statusCode != 200) {
          throw HttpException('服务返回 HTTP ${response.statusCode}');
        }
        final result = jsonDecode(content);
        if (result is! Map<String, dynamic>) {
          throw const FormatException('服务返回格式异常');
        }
        return result;
      })().timeout(const Duration(seconds: 15));
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<List<Song>> netease(Uint8List pcm) async {
    final generation = _generation;
    final fp = await fingerprinter.generate(pcm);
    if (generation != _generation) throw StateError('已取消');
    final data = await _request(
      Uri.https('interface.music.163.com', '/api/music/audio/match', {
        'sessionId': '0123456789abcdef',
        'algorithmCode': 'shazam_v2',
        'duration': (pcm.length ~/ 16000).toString(),
        'rawdata': fp,
        'times': '1',
        'decrypt': '1',
      }),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://music.163.com/',
      },
    );
    if (data['code'] != 200) {
      throw StateError('网易云返回 ${data['code']}：${data['message'] ?? '请求未完成'}');
    }
    return parseNetease(data);
  }

  Future<List<Song>> kugou(Uint8List pcm) async {
    const key = 'OIlwieks28dk2k092lksi2UIkp';
    const dfid = '-';
    final mid = BigInt.parse(
      md5.convert(utf8.encode(dfid)).toString(),
      radix: 16,
    ).toString();
    final uuid = md5.convert(utf8.encode('$dfid$mid')).toString();
    final now = DateTime.now().millisecondsSinceEpoch;
    final params = <String, String>{
      'dfid': dfid,
      'mid': mid,
      'uuid': uuid,
      'appid': '1005',
      'clientver': '20489',
      'clienttime': '${now ~/ 1000}',
      'fpid': '$now',
      'area_code': '1',
      'include_unpublish': '1',
      'useid': '0',
      'multi_result': '1',
    };
    final keys = params.keys.toList()..sort();
    final joined = keys.map((k) => '$k=${params[k]}').join();
    params['signature'] = md5.convert([
      ...utf8.encode('$key$joined'),
      ...pcm,
      ...utf8.encode(key),
    ]).toString();
    final data = await _request(
      Uri.https(
        'gateway.kugou.com',
        '/fingerprint.service/v1/music_trackid_mulit',
        params,
      ),
      body: pcm,
      headers: {
        'Content-Type': 'application/octet-stream',
        'User-Agent': 'KuGou/11490 (Android)',
        'dfid': dfid,
        'mid': mid,
        'clienttime': '${now ~/ 1000}',
        'kg-rc': '1',
        'kg-thash': '5d816a0',
        'kg-rec': '1',
        'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
      },
    );
    if (data['status'] != 1 ||
        (data['error_code'] != null && data['error_code'] != 0)) {
      throw StateError(
        '酷狗返回 ${data['error_code']}：${data['error_msg'] ?? '请求未完成'}',
      );
    }
    return parseKugou(data);
  }

  Future<RecognitionBatch> recognize(
    Uint8List pcm,
    String engine,
    void Function(String) progress,
  ) async {
    final generation = _generation;
    final order = ['auto', 'parallel'].contains(engine)
        ? ['netease', 'kugou']
        : [engine];
    progress(order.length == 2 ? '网易云与酷狗正在同时识别…' : '正在识别…');
    final outcomes = await Future.wait(
      order.map((provider) async {
        if (generation != _generation) throw StateError('已取消');
        final name = provider == 'netease' ? '网易云音乐' : '酷狗音乐';
        final clock = Stopwatch()..start();
        try {
          final songs = await (provider == 'netease'
              ? netease(pcm)
              : kugou(pcm));
          if (generation != _generation) throw StateError('已取消');
          return (
            songs,
            '$name：${songs.isEmpty ? '无匹配' : '${songs.length} 个候选'} · ${clock.elapsedMilliseconds} ms',
          );
        } catch (e) {
          if (generation != _generation) rethrow;
          return (<Song>[], '$name：${friendlyError(e)}');
        }
      }),
    );
    if (generation != _generation) throw StateError('已取消');
    return RecognitionBatch(
      outcomes.expand((outcome) => outcome.$1).toList(),
      outcomes.map((outcome) => outcome.$2).toList(),
    );
  }
}

String friendlyError(Object error) {
  if (error is TimeoutException) return '请求超时，请稍后重试';
  if (error is SocketException) return '网络连接失败，请检查网络或代理';
  if (error is HandshakeException) return '安全连接失败，请检查系统时间或网络';
  return error.toString().replaceFirst(
    RegExp(r'^(Bad state: |FormatException: |HttpException: )'),
    '',
  );
}

List<Song> parseNetease(Map<String, dynamic> json) {
  final payload = json['data'];
  final items = payload is Map ? payload['result'] : null;
  if (items is! List) return [];
  final songs = <Song>[];
  final ids = <String>{};
  for (final item in items) {
    if (item is! Map || item['song'] is! Map) continue;
    final song = item['song'] as Map;
    final id = song['id']?.toString() ?? '';
    final title = song['name']?.toString() ?? '';
    if (id.isEmpty || title.isEmpty || !ids.add(id)) continue;
    final artists = song['artists'] ?? song['ar'];
    final artist = artists is List
        ? artists
              .whereType<Map>()
              .map((a) => a['name']?.toString() ?? '')
              .where((a) => a.isNotEmpty)
              .join(' / ')
        : '';
    final album = song['album'] ?? song['al'];
    songs.add(
      Song(
        title: title,
        artist: artist,
        engine: 'netease',
        trackId: id,
        album: album is Map ? album['name']?.toString() ?? '' : '',
        url: 'https://music.163.com/song?id=$id',
      ),
    );
  }
  return songs.take(5).toList();
}

List<Song> parseKugou(Map<String, dynamic> json) {
  final payload = json['data'];
  final items = payload is List
      ? payload
      : payload is Map
      ? (payload['list'] ?? payload['songs'])
      : null;
  if (items is! List) return [];
  final songs = <Song>[];
  final ids = <String>{};
  for (final item in items.whereType<Map>()) {
    final title = (item['songname'] ?? item['song_name'] ?? '').toString();
    final id = (item['mixsongid'] ?? item['songid'] ?? item['hash_128'] ?? '')
        .toString();
    if (title.isEmpty || id.isEmpty || !ids.add(id)) continue;
    final authors = item['authors'];
    final artist =
        (item['singername'] ??
                item['singer_name'] ??
                (authors is List
                    ? authors
                          .whereType<Map>()
                          .map((a) => a['author_name'] ?? a['name'] ?? '')
                          .join(' / ')
                    : ''))
            .toString();
    final albums = item['album'];
    final album = albums is List && albums.isNotEmpty ? albums.first : albums;
    songs.add(
      Song(
        title: title,
        artist: artist,
        engine: 'kugou',
        trackId: id,
        album: album is Map
            ? (album['albumname'] ?? album['album_name'] ?? '').toString()
            : '',
        url: Uri.https('www.kugou.com', '/yy/html/search.html', {
          'searchType': 'song',
          'searchKeyWord': '$title $artist',
        }).toString(),
      ),
    );
  }
  return songs.take(5).toList();
}
