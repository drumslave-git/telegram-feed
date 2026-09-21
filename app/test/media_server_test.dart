import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telegram_feed/media/media_server.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

import 'fixtures.dart';

/// A TDLib stand-in: the "download" writes the real bytes into a sparse partial file, one
/// block per [step], starting at the offset it was last aimed at.
class PartialFileGateway extends ChannelsGateway {
  PartialFileGateway(this.path, this.content) : super(const []) {
    File(path).writeAsBytesSync(Uint8List(content.length));
  }
  final String path;
  final Uint8List content;
  static const block = 1000;

  /// Downloaded blocks by index.
  final have = <int>{};
  final aims = <int>[];
  int _cursor = 0;
  final _progress = StreamController<FileProgress>.broadcast();

  @override
  Stream<FileProgress> fileProgress(int fileId) => _progress.stream;

  FileProgress get _state => FileProgress(
    fileId: 1,
    downloaded: have.length * block,
    total: content.length,
    partialPath: path,
  );

  @override
  Future<FileProgress> downloadFrom(
    int fileId, {
    int offset = 0,
    int priority = 32,
    int limit = 0,
  }) async {
    aims.add(offset);
    _cursor = offset ~/ block;
    return _state;
  }

  @override
  Future<int> downloadedPrefix(int fileId, int offset) async {
    var n = 0;
    for (var b = offset ~/ block; have.contains(b); b++) {
      n += block;
    }
    if (n == 0) return 0;
    return (n - offset % block).clamp(0, content.length - offset);
  }

  /// Downloads the next missing block at or after the cursor.
  void step() {
    final blocks = (content.length / block).ceil();
    while (_cursor < blocks && have.contains(_cursor)) {
      _cursor++;
    }
    if (_cursor >= blocks) return;
    final from = _cursor * block;
    final to = (from + block).clamp(0, content.length);
    final raf = File(path).openSync(mode: FileMode.append)
      ..setPositionSync(from);
    raf.writeFromSync(content, from, to);
    raf.closeSync();
    have.add(_cursor);
    _progress.add(_state);
  }
}

void main() {
  late Directory tmp;
  late PartialFileGateway gw;
  late MediaServer server;
  late Uint8List content;
  const file = FileRef(id: 1, remoteId: 'r', size: 4500);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tf_server');
    content = Uint8List.fromList(List.generate(4500, (i) => i % 251));
    gw = PartialFileGateway('${tmp.path}/video.part', content);
    server = MediaServer(gw);
  });
  tearDown(() async {
    await server.close();
    tmp.deleteSync(recursive: true);
  });

  Future<(HttpClientResponse, Future<List<int>>)> get(
    Uri url, {
    String? range,
  }) async {
    final req = await HttpClient().getUrl(url);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    return (res, res.fold(<int>[], (a, b) => a..addAll(b)));
  }

  test('serves the file while it downloads, in order', () async {
    final url = await server.urlFor(file);
    // The download only starts moving after the request is in: headers must not wait for it.
    final (res, body) = await get(url);
    expect(res.statusCode, 200);
    expect(res.contentLength, 4500);
    final pump = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => gw.step(),
    );
    expect(await body, content);
    pump.cancel();
    expect(gw.aims.first, 0);
  });

  test('a range request aims the download at its offset', () async {
    final url = await server.urlFor(file);
    final (res, body) = await get(url, range: 'bytes=3200-');
    expect(res.statusCode, 206);
    expect(
      res.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 3200-4499/4500',
    );
    final pump = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => gw.step(),
    );
    expect(await body, content.sublist(3200));
    pump.cancel();
    expect(gw.aims.first, 3200);
    expect(
      gw.have.contains(0),
      isFalse,
    ); // nothing before the seek target was fetched first
  });

  test('bytes already on disk are served at once', () async {
    for (var i = 0; i < 5; i++) {
      gw.step();
    }
    final url = await server.urlFor(file);
    final (res, body) = await get(url, range: 'bytes=100-299');
    expect(res.statusCode, 206);
    expect(await body, content.sublist(100, 300));
    expect(gw.have.length, 5); // no block had to be downloaded for it
  });

  test('unknown paths and tokens are refused', () async {
    final url = await server.urlFor(file);
    final (res, body) = await get(url.replace(path: '/wrong/1'));
    await body;
    expect(res.statusCode, 404);
  });
}
