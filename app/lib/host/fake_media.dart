/// The sample media of the fake build: pictures, a video and a file under
/// `assets/fake/`, copied to the support directory so the core can serve them as files.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Where the fake's media lives under the app's support directory.
String fakeMediaDirectory(String support) => '$support/fake';

const _files = [
  'avatar1.png',
  'avatar2.png',
  'avatar3.png',
  'photo1.png',
  'photo2.png',
  'photo3.png',
  'photo4.png',
  'thumb.png',
  'video.mp4',
  'notes.txt',
];

/// Copies the bundled sample media into place. A file already there with the bundled
/// size is left alone, so a restart costs nothing.
Future<void> installFakeMedia() async {
  final support = (await getApplicationSupportDirectory()).path;
  final dir = Directory(fakeMediaDirectory(support));
  await dir.create(recursive: true);
  for (final name in _files) {
    final data = await rootBundle.load('assets/fake/$name');
    final file = File('${dir.path}/$name');
    if (await file.exists() && await file.length() == data.lengthInBytes) {
      continue;
    }
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }
}
