import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

Widget localImage(String path, {BoxFit? fit, bool gaplessPlayback = false}) =>
    throw UnsupportedError('no local media on this platform');

VideoPlayerController localVideoController(String path) =>
    throw UnsupportedError('no local media on this platform');

Future<Duration?> setLocalAudio(AudioPlayer player, String path) =>
    throw UnsupportedError('no local media on this platform');
