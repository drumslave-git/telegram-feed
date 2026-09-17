import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

Widget localImage(String path, {BoxFit? fit, bool gaplessPlayback = false}) =>
    Image.file(File(path), fit: fit, gaplessPlayback: gaplessPlayback);

VideoPlayerController localVideoController(String path) =>
    VideoPlayerController.file(File(path));

Future<Duration?> setLocalAudio(AudioPlayer player, String path) =>
    player.setFilePath(path);
