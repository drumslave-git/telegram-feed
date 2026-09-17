// Installs the prebuilt TDLib binaries into app/ (not committed to git).
//
//   dart tool/fetch_tdlib.dart                 download release assets for the pinned commit
//   dart tool/fetch_tdlib.dart --repo o/r      from another GitHub repo (default: origin remote)
//   dart tool/fetch_tdlib.dart --local         use build/tdlib-out, build/tdweb-out and
//                                              build/sqlite3-wasm-out from the Docker builds
//                                              in tool/tdlib, tool/tdweb, tool/sqlite3_wasm
//
// Release layout (produced by .github/workflows/tdlib.yml, tag tdlib-<short sha>):
//   libtdjson-android.tar.gz   libs/<abi>/libtdjson.so
//   tdweb.tar.gz               dist/{tdweb.js, *.worker.js, *.wasm}, package.json
//   sqlite3.wasm               SQLite for drift on the web (tool/sqlite3_wasm)
//   SHA256SUMS, TDLIB_COMMIT
//
// Installs to:
//   app/android/app/src/main/jniLibs/<abi>/libtdjson.so
//   app/web/tdweb/tdweb.js and app/web/{*.worker.js, *.wasm}   (webpack public path is /)
//   app/web/sqlite3.wasm
import 'dart:io';

Future<void> main(List<String> args) async {
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  final commit = File('$root/packages/tdlib_bindings/schema/TDLIB_COMMIT')
      .readAsStringSync()
      .trim();
  final tag = 'tdlib-${commit.substring(0, 7)}';
  final local = args.contains('--local');
  final repoArg = args.indexOf('--repo');
  final repo = repoArg >= 0 ? args[repoArg + 1] : await _originRepo(root);

  final tmp = Directory('$root/build/tdlib-fetch')..createSync(recursive: true);
  final androidTar = File('${tmp.path}/libtdjson-android.tar.gz');
  final webTar = File('${tmp.path}/tdweb.tar.gz');
  final sqliteWasm = File('${tmp.path}/sqlite3.wasm');

  if (local) {
    stdout.writeln('local mode: packing build/tdlib-out and build/tdweb-out');
    // Relative paths only: GNU tar reads "E:\..." as a remote host.
    File('$root/build/tdlib-out/tdlib.zip').copySync('${tmp.path}/tdlib.zip');
    await _run(
      'tar',
      ['-xf', 'tdlib.zip'],
      cwd: tmp.path,
      fallback: ['unzip', '-qo', 'tdlib.zip'],
    );
    await _run('tar', [
      '-czf',
      'libtdjson-android.tar.gz',
      '-C',
      'tdlib',
      'libs',
    ], cwd: tmp.path);
    final webSrc = Directory('${tmp.path}/tdweb-src/dist')
      ..createSync(recursive: true);
    for (final f in Directory(
      '$root/build/tdweb-out/tdweb/dist',
    ).listSync().whereType<File>()) {
      f.copySync('${webSrc.path}/${f.uri.pathSegments.last}');
    }
    File('$root/build/tdweb-out/tdweb/package.json')
        .copySync('${tmp.path}/tdweb-src/package.json');
    await _run('tar', [
      '-czf',
      'tdweb.tar.gz',
      '-C',
      'tdweb-src',
      'dist',
      'package.json',
    ], cwd: tmp.path);
    File('$root/build/sqlite3-wasm-out/sqlite3.wasm').copySync(sqliteWasm.path);
  } else {
    if (repo == null) {
      stderr.writeln(
        'No GitHub repo known: pass --repo owner/name or add an origin remote.',
      );
      exit(2);
    }
    final base = 'https://github.com/$repo/releases/download/$tag';
    stdout.writeln('downloading $base');
    final sums = await _download(
      '$base/SHA256SUMS',
      File('${tmp.path}/SHA256SUMS'),
    );
    await _download('$base/libtdjson-android.tar.gz', androidTar);
    await _download('$base/tdweb.tar.gz', webTar);
    await _download('$base/sqlite3.wasm', sqliteWasm);
    _verify(sums, androidTar);
    _verify(sums, webTar);
    _verify(sums, sqliteWasm);
  }

  // Android
  final jni = Directory('$root/app/android/app/src/main/jniLibs')
    ..createSync(recursive: true);
  final stage = Directory('${tmp.path}/android')..createSync(recursive: true);
  await _run('tar', [
    '-xzf',
    'libtdjson-android.tar.gz',
    '-C',
    'android',
  ], cwd: tmp.path);
  for (final abiDir in Directory(
    '${stage.path}/libs',
  ).listSync().whereType<Directory>()) {
    final abi = abiDir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final so = File('${abiDir.path}/libtdjson.so');
    final dest = File('${jni.path}/$abi/libtdjson.so')
      ..parent.createSync(recursive: true);
    so.copySync(dest.path);
    stdout.writeln(
      '  $abi/libtdjson.so ${(dest.lengthSync() / 1048576).toStringAsFixed(1)} MB',
    );
  }

  // Web
  final webStage = Directory('${tmp.path}/web')..createSync(recursive: true);
  await _run('tar', ['-xzf', 'tdweb.tar.gz', '-C', 'web'], cwd: tmp.path);
  final webDir = Directory('$root/app/web');
  Directory('${webDir.path}/tdweb').createSync(recursive: true);
  for (final f in Directory(
    '${webStage.path}/dist',
  ).listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final dest = name == 'tdweb.js'
        ? '${webDir.path}/tdweb/tdweb.js'
        : '${webDir.path}/$name';
    f.copySync(dest);
    stdout.writeln('  web/${name == 'tdweb.js' ? 'tdweb/' : ''}$name');
  }
  sqliteWasm.copySync('${webDir.path}/sqlite3.wasm');
  stdout.writeln('  web/sqlite3.wasm');
  File('${jni.path}/TDLIB_COMMIT').writeAsStringSync('$commit\n');
  stdout.writeln('installed TDLib $tag');
}

Future<String?> _originRepo(String root) async {
  final r = await Process.run('git', [
    '-C',
    root,
    'remote',
    'get-url',
    'origin',
  ]);
  if (r.exitCode != 0) return null;
  final m = RegExp(r'github\.com[:/]([^/]+/[^/.]+)')
      .firstMatch((r.stdout as String).trim());
  return m?.group(1);
}

Future<void> _run(
  String exe,
  List<String> args, {
  required String cwd,
  List<String>? fallback,
}) async {
  final r = await Process.run(
    exe,
    args,
    runInShell: true,
    workingDirectory: cwd,
  );
  if (r.exitCode == 0) return;
  if (fallback != null) {
    final f = await Process.run(
      fallback.first,
      fallback.sublist(1),
      runInShell: true,
      workingDirectory: cwd,
    );
    if (f.exitCode == 0) return;
    throw ProcessException(
      fallback.first,
      fallback.sublist(1),
      '${f.stderr}',
      f.exitCode,
    );
  }
  throw ProcessException(exe, args, '${r.stderr}', r.exitCode);
}

Future<String> _download(String url, File to) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.followRedirects = true;
    final res = await req.close();
    if (res.statusCode != 200)
      throw HttpException('HTTP ${res.statusCode} for $url');
    final sink = to.openWrite();
    await res.pipe(sink);
    return to.readAsStringSync().length < 4096 && url.endsWith('SHA256SUMS')
        ? to.readAsStringSync()
        : '';
  } finally {
    client.close();
  }
}

void _verify(String sums, File f) {
  final name = f.uri.pathSegments.last;
  final line = sums
      .split('\n')
      .firstWhere((l) => l.trim().endsWith(name), orElse: () => '');
  if (line.isEmpty) throw StateError('no checksum for $name');
  final expected = line.trim().split(RegExp(r'\s+')).first;
  final actual = _sha256Hex(f.readAsBytesSync());
  if (actual != expected)
    throw StateError('checksum mismatch for $name: $actual != $expected');
}

// Minimal SHA-256 (no package dependency for a root-level tool script).
String _sha256Hex(List<int> data) {
  const k = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5, //
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174, //
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da, //
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967, //
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85, //
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070, //
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3, //
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2, //
  ];
  var h = [
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final ml = data.length * 8;
  final padded = [...data, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  for (var i = 7; i >= 0; i--) {
    padded.add((ml >> (i * 8)) & 0xff);
  }
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;
  final w = List<int>.filled(64, 0);
  for (var off = 0; off < padded.length; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] =
          (padded[off + i * 4] << 24) |
          (padded[off + i * 4 + 1] << 16) |
          (padded[off + i * 4 + 2] << 8) |
          padded[off + i * 4 + 3];
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = h[0],
        b = h[1],
        c = h[2],
        d = h[3],
        e = h[4],
        f = h[5],
        g = h[6],
        hh = h[7];
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (~e & g);
      final t1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    h = [
      (h[0] + a) & 0xffffffff,
      (h[1] + b) & 0xffffffff,
      (h[2] + c) & 0xffffffff,
      (h[3] + d) & 0xffffffff, //
      (h[4] + e) & 0xffffffff,
      (h[5] + f) & 0xffffffff,
      (h[6] + g) & 0xffffffff,
      (h[7] + hh) & 0xffffffff, //
    ];
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}
