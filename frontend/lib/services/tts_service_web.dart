import 'dart:js_interop';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Web implementation: creates a Blob URL from bytes and plays via UrlSource.
Future<void> playAudioBytes(AudioPlayer player, Uint8List bytes) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'audio/mpeg'),
  );
  final url = web.URL.createObjectURL(blob);
  await player.play(UrlSource(url));
  // Revoke after a delay to allow playback to start
  Future.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
