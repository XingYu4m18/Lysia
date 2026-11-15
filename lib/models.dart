class Song {
  const Song({
    required this.title,
    required this.artist,
    required this.engine,
    required this.trackId,
    this.album = '',
    this.url = '',
  });
  final String title, artist, engine, trackId, album, url;
  String get engineName => engine == 'netease' ? '网易云音乐' : '酷狗音乐';
  String get identity =>
      '${title.toLowerCase().replaceAll(RegExp(r'\s+'), '')}|${artist.toLowerCase().replaceAll(RegExp(r'\s+'), '')}';
  Map<String, Object?> toJson() => {
    'title': title,
    'artist': artist,
    'engine': engine,
    'trackId': trackId,
    'album': album,
    'url': url,
  };
  factory Song.fromJson(Map<String, dynamic> json) => Song(
    title: json['title'] as String,
    artist: json['artist'] as String,
    engine: json['engine'] as String,
    trackId: json['trackId'] as String,
    album: json['album'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );
}

class HeardSong {
  const HeardSong({
    required this.id,
    required this.song,
    required this.firstHeard,
    required this.lastHeard,
    required this.count,
  });
  final int id, count;
  final Song song;
  final DateTime firstHeard, lastHeard;
}

class RecognitionBatch {
  const RecognitionBatch(this.songs, this.notes);
  final List<Song> songs;
  final List<String> notes;
}

class CaptureInfo {
  CaptureInfo(Map<dynamic, dynamic> map)
    : running = map['running'] == true,
      samples = (map['samples'] as num?)?.toInt() ?? 0,
      level = (map['level'] as num?)?.toDouble() ?? 0,
      error = map['error'] as String? ?? '',
      device = map['device'] as String? ?? '',
      sequence = (map['sequence'] as num?)?.toInt() ?? 0;
  final bool running;
  final int samples, sequence;
  final double level;
  final String error, device;
}
