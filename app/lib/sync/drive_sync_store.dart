import 'dart:convert';

import 'package:core/core.dart';
import 'package:http/http.dart' as http;

/// Gives an OAuth access token for the Drive app data scope. With [fresh] the cached token
/// was rejected and a new one is wanted. Null when the user is not signed in.
typedef DriveTokenProvider = Future<String?> Function({bool fresh});

/// The sync file in the hidden per-app folder of the user's Google Drive (`appDataFolder`):
/// invisible in the Drive UI, removed when the user disconnects the app, and the only part
/// of Drive the app's scope (`drive.appdata`) can touch.
final class DriveSyncStore implements SyncStore {
  DriveSyncStore(this._token, {http.Client? client})
    : _http = client ?? http.Client();

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const fileName = 'telegram-feed-sync.json';
  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  final DriveTokenProvider _token;
  final http.Client _http;
  String? _fileId;

  @override
  Future<String?> read() async {
    final id = await _findFile();
    if (id == null) return null;
    final res = await _send('GET', Uri.parse('$_api/$id?alt=media'));
    if (res.statusCode == 404) {
      _fileId = null;
      return null;
    }
    _check(res, 'read the sync file');
    return utf8.decode(res.bodyBytes);
  }

  @override
  Future<void> write(String content) async {
    final id = await _findFile();
    if (id != null) {
      final res = await _send(
        'PATCH',
        Uri.parse('$_upload/$id?uploadType=media'),
        headers: {'content-type': 'application/json; charset=utf-8'},
        body: utf8.encode(content),
      );
      _check(res, 'update the sync file');
      return;
    }
    const boundary = 'telegram-feed-sync-boundary';
    final metadata = jsonEncode({
      'name': fileName,
      'parents': ['appDataFolder'],
    });
    final body =
        '--$boundary\r\ncontent-type: application/json; charset=utf-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\ncontent-type: application/json; charset=utf-8\r\n\r\n'
        '$content\r\n'
        '--$boundary--';
    final res = await _send(
      'POST',
      Uri.parse('$_upload?uploadType=multipart&fields=id'),
      headers: {'content-type': 'multipart/related; boundary=$boundary'},
      body: utf8.encode(body),
    );
    _check(res, 'create the sync file');
    _fileId = (jsonDecode(res.body) as Map<String, Object?>)['id'] as String?;
  }

  Future<String?> _findFile() async {
    if (_fileId != null) return _fileId;
    final res = await _send(
      'GET',
      Uri.parse(_api).replace(
        queryParameters: {
          'spaces': 'appDataFolder',
          'q': "name = '$fileName'",
          'orderBy': 'modifiedTime desc',
          'fields': 'files(id)',
          'pageSize': '1',
        },
      ),
    );
    _check(res, 'look for the sync file');
    final files =
        (jsonDecode(res.body) as Map<String, Object?>)['files'] as List;
    if (files.isEmpty) return null;
    return _fileId = (files.first as Map<String, Object?>)['id'] as String;
  }

  /// Sends with the bearer token; a 401 gets one retry with a fresh token.
  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    Future<http.Response> attempt({required bool fresh}) async {
      final token = await _token(fresh: fresh);
      if (token == null) {
        throw const SyncException('Not signed in to Google Drive.');
      }
      final req = http.Request(method, uri)
        ..headers.addAll(headers)
        ..headers['authorization'] = 'Bearer $token';
      if (body != null) req.bodyBytes = body;
      try {
        return await http.Response.fromStream(
          await _http.send(req).timeout(const Duration(seconds: 30)),
        );
      } on SyncException {
        rethrow;
      } on Exception catch (e) {
        throw SyncException('Google Drive cannot be reached: $e');
      }
    }

    final res = await attempt(fresh: false);
    return res.statusCode == 401 ? attempt(fresh: true) : res;
  }

  static void _check(http.Response res, String what) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    var detail = '';
    try {
      if (jsonDecode(res.body) case {'error': {'message': final String m}}) {
        detail = ': $m';
      }
    } catch (_) {
      // body is not JSON
    }
    throw SyncException(
      'Google Drive refused to $what (${res.statusCode})$detail',
    );
  }
}
