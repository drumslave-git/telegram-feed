import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

Widget localImage(String path, {BoxFit? fit, bool gaplessPlayback = false}) =>
    Image.network(path, fit: fit, gaplessPlayback: gaplessPlayback);

VideoPlayerController localVideoController(String path) =>
    VideoPlayerController.networkUrl(Uri.parse(path));

Future<Duration?> setLocalAudio(AudioPlayer player, String path) =>
    player.setUrl(path);
