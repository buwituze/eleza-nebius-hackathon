import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Native (iOS/Android/Desktop) implementation: BytesSource works fine.
Future<void> playAudioBytes(AudioPlayer player, Uint8List bytes) async {
  await player.play(BytesSource(bytes));
}
