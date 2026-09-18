import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:telegram_gateway/telegram_gateway.dart';

/// Loopback HTTP server that lets the video player read a Telegram file while TDLib is still
/// downloading it, the way the official app starts a video after the first seconds arrived.
///
/// The player asks for byte ranges. Bytes TDLib already has are served from its partial file;
/// for the rest the download is aimed at the requested offset ([TelegramGateway.downloadFrom])
/// and the response waits for them. Seeking simply becomes a request for another range.
final class MediaServer {
  MediaServer(this.gateway);
  final TelegramGateway gateway;

  HttpServer? _server;
  Future<HttpServer>? _starting;
  final _files = <int, _Served>{};

  /// Other apps on the device can reach the port but cannot guess the path.
  final String _token = _randomToken();

  static String _randomToken() {
    final r = Random.secure();
    return List.generate(
      24,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static const _chunk = 256 * 1024;

  /// URL under which [file] can be played. [file] must have a known size.
  Future<Uri> urlFor(FileRef file, {String mimeType = 'video/mp4'}) async {
    final server = await (_starting ??= _start());
    _files.putIfAbsent(file.id, () => _Served(file.id, file.size, mimeType));
    return Uri.parse('http://127.0.0.1:${server.port}/$_token/${file.id}');
  }

  /// Forgets [fileId]; open responses for it end. The port closes with the last file.
  void release(int fileId) {
    _files.remove(fileId)?.dispose();
    if (_files.isEmpty) unawaited(close());
  }

  Future<HttpServer> _start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen((req) => unawaited(_handle(req)));
    return s;
  }

  Future<void> close() async {
    for (final f in _files.values) {
      f.dispose();
    }
    _files.clear();
    await _server?.close(force: true);
    _server = null;
    _starting = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final seg = req.uri.pathSegments;
    final served = seg.length == 2 && seg[0] == _token
        ? _files[int.tryParse(seg[1])]
        : null;
    if (served == null || (req.method != 'GET' && req.method != 'HEAD')) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader));
    final start = range?.$1 ?? 0;
    final end = min(range?.$2 ?? served.size - 1, served.size - 1);
    if (start > end) {
      debugPrint(
        'media: ${served.fileId} range "${req.headers.value(HttpHeaders.rangeHeader)}" '
        'outside size ${served.size}',
      );
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${served.size}');
      await res.close();
      return;
    }
    res.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
    res.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, served.mimeType)
      ..set(HttpHeaders.contentLengthHeader, end - start + 1);
    if (range != null) {
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${served.size}',
      );
    }
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    // dart:io holds the headers back until the first body byte, and the body may have to wait
    // for the download while the player's read timeout runs. Detaching writes them now.
    final socket = await res.detachSocket();
    try {
      await _stream(served, socket, start, end);
      await socket.flush();
      await socket.close();
    } catch (e) {
      // The player closed the connection (seek, dispose); nothing to report.
      debugPrint('media: ${served.fileId} $start-$end ended: $e');
    } finally {
      socket.destroy();
    }
  }

  /// `bytes=a-b` or `bytes=a-`; anything else is served as the whole file.
  static (int, int?)? _parseRange(String? header) {
    final m = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(header?.trim() ?? '');
    if (m == null) return null;
    final to = m.group(2)!;
    return (int.parse(m.group(1)!), to.isEmpty ? null : int.parse(to));
  }

  Future<void> _stream(_Served f, Socket out, int start, int end) async {
    // The player reads one range at a time; the newest request decides where TDLib downloads.
    final turn = ++f.turn;
    _watch(f);
    var pos = start;
    // The first answer also tells where TDLib keeps the file.
    var aimed = f.path.isEmpty;
    if (aimed) {
      f.path = (await gateway.downloadFrom(f.fileId, offset: pos)).partialPath;
    }
    while (pos <= end) {
      if (f.disposed) return;
      final available = await gateway.downloadedPrefix(f.fileId, pos);
      if (available <= 0) {
        // An abandoned request must not pull the download back to its offset.
        if (f.turn != turn) return;
        if (!aimed) {
          f.path = (await gateway.downloadFrom(
            f.fileId,
            offset: pos,
          )).partialPath;
          aimed = true;
        }
        await f.changed.first.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
        continue;
      }
      aimed = false;
      final n = min(min(available, end - pos + 1), _chunk);
      out.add(await _read(f, pos, n));
      await out.flush(); // back-pressure: never buffer more than a chunk
      pos += n;
    }
    // A range that ended before the file does (or started after a seek) leaves holes; the
    // download goes on from the front so the file completes for the next time.
    if (f.turn == turn && !f.complete) {
      unawaited(gateway.downloadFrom(f.fileId));
    }
  }

  void _watch(_Served f) {
    f.sub ??= gateway.fileProgress(f.fileId).listen((p) {
      if (p.partialPath.isNotEmpty) f.path = p.partialPath;
      if (p.isComplete) f.complete = true;
      f.poke();
    });
  }

  Future<Uint8List> _read(_Served f, int pos, int n) async {
    for (var attempt = 0; ; attempt++) {
      try {
        if (f.path.isEmpty) throw const FileSystemException('no path yet');
        final raf = await File(f.path).open();
        try {
          await raf.setPosition(pos);
          return await raf.read(n);
        } finally {
          await raf.close();
        }
      } on FileSystemException {
        // TDLib moves the file when the download completes; ask where it is now.
        if (attempt >= 2) rethrow;
        f.path = (await gateway.downloadFrom(
          f.fileId,
          offset: pos,
        )).partialPath;
      }
    }
  }
}

class _Served {
  _Served(this.fileId, this.size, this.mimeType);
  final int fileId;
  final int size;
  final String mimeType;
  String path = '';
  bool complete = false;
  bool disposed = false;
  int turn = 0;
  StreamSubscription<FileProgress>? sub;
  final _changed = StreamController<void>.broadcast();
  Stream<void> get changed => _changed.stream;
  void poke() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() {
    disposed = true;
    sub?.cancel();
    _changed.close();
  }
}
