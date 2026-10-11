import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// Web-only import for Blob URL playback
import 'tts_service_web.dart' if (dart.library.io) 'tts_service_io.dart'
    as platform;

/// ElevenLabs Text-to-Speech service.
///
/// Uses the "Benitha - Rwandan Nurse 1" voice (flash v2.5).
/// Handles both Kinyarwanda and English.
/// API key loaded from frontend/.env → ELEVENLABS_API_KEY
class TTSService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSpeaking = false;

  static const String _voiceId = 'cYewvtoDtKjvFBC0o8AH'; // Benitha - Rwandan Nurse 1
  static const String _modelId = 'eleven_flash_v2_5';

  String get _apiKey => dotenv.env['ELEVENLABS_API_KEY'] ?? '';

  String get _endpoint =>
      'https://api.elevenlabs.io/v1/text-to-speech/$_voiceId';

  bool get isSpeaking => _isSpeaking;

  Future<Uint8List?> _synthesize(String text) async {
    if (_apiKey.isEmpty) {
      debugPrint('⚠️ ELEVENLABS_API_KEY not set in frontend/.env');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'xi-api-key': _apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': _modelId,
          'voice_settings': {'stability': 0.50},
        }),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        debugPrint(
          '❌ ElevenLabs error ${response.statusCode}: ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('❌ ElevenLabs request failed: $e');
      return null;
    }
  }

  /// Speak text using ElevenLabs TTS.
  /// Benitha handles both Kinyarwanda and English — no language parameter needed.
  Future<void> speak(String text, {String language = 'english'}) async {
    if (text.isEmpty) return;

    _isSpeaking = true;
    debugPrint('🔊 TTS ($language): "$text"');

    try {
      final audioBytes = await _synthesize(text);
      if (audioBytes != null) {
        await platform.playAudioBytes(_audioPlayer, audioBytes);
        await _audioPlayer.onPlayerComplete.first;
      } else {
        // Fallback: simulate speaking duration
        await Future.delayed(Duration(milliseconds: text.length * 50));
      }
    } catch (e) {
      debugPrint('❌ TTS error: $e');
    }

    _isSpeaking = false;
  }

  /// Stop currently playing audio
  Future<void> stop() async {
    await _audioPlayer.stop();
    _isSpeaking = false;
  }

  /// Release resources
  void dispose() {
    _audioPlayer.dispose();
  }
}
