import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Conditional import for dart:io (not available on web)
import 'audio_service_stub.dart'
    if (dart.library.io) 'audio_service_io.dart'
    as platform;

/// Simple wrapper for audio file path
class AudioFile {
  final String path;
  AudioFile(this.path);
}

/// Cross-platform audio recording service
/// Supports: Web, Android, iOS, Windows, macOS, Linux
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// Detect current platform
  String get _platformName {
    if (kIsWeb) return 'Web';
    return platform.getPlatformName();
  }

  /// Get appropriate audio encoder for platform
  AudioEncoder get _audioEncoder {
    if (kIsWeb) {
      return AudioEncoder.wav; // Web: WAV format
    }
    return platform.getAudioEncoder();
  }

  /// Get appropriate file extension for platform
  String get _fileExtension {
    if (kIsWeb) return 'wav';
    return platform.getFileExtension();
  }

  /// Request microphone permission
  Future<bool> requestPermission() async {
    try {
      debugPrint('📋 Requesting microphone permission...');
      debugPrint('   Platform: $_platformName');

      if (kIsWeb) {
        // Web: Permission requested automatically when recording starts
        final hasPermission = await _recorder.hasPermission();
        debugPrint('   ✅ Web microphone permission: $hasPermission');
        return hasPermission;
      }

      // Mobile & Desktop: Use permission_handler
      final status = await Permission.microphone.request();
      final granted = status == PermissionStatus.granted;
      debugPrint(
        '   ${granted ? "✅" : "❌"} $_platformName permission: $status',
      );
      return granted;
    } catch (e) {
      debugPrint('❌ Permission request failed: $e');
      return false;
    }
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    try {
      if (kIsWeb) {
        return await _recorder.hasPermission();
      }
      final status = await Permission.microphone.status;
      return status == PermissionStatus.granted;
    } catch (e) {
      debugPrint('❌ Permission check failed: $e');
      return false;
    }
  }

  /// Start recording audio
  Future<void> startRecording() async {
    try {
      debugPrint('🎙️ Starting recording...');
      debugPrint('   Platform: $_platformName');
      debugPrint('   Encoder: $_audioEncoder');

      // Check permission first
      final hasPermission = await _recorder.hasPermission();
      debugPrint('   Has permission: $hasPermission');

      if (!hasPermission) {
        throw Exception(
          'Microphone permission not granted. Please allow microphone access.',
        );
      }

      // Generate recording path for all platforms
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      if (kIsWeb) {
        // WEB: Generate path name (stored in browser memory)
        _currentRecordingPath = 'recording_$timestamp.$_fileExtension';
        debugPrint('   Starting web recording: $_currentRecordingPath');
      } else {
        // MOBILE & DESKTOP: Save to temporary directory
        final directory = await getTemporaryDirectory();
        _currentRecordingPath =
            '${directory.path}/recording_$timestamp.$_fileExtension';
        debugPrint('   Recording to: $_currentRecordingPath');
      }

      await _recorder.start(
        RecordConfig(
          encoder: _audioEncoder,
          sampleRate: 16000,
          bitRate: 128000,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      debugPrint('✅ Recording started successfully');
    } catch (e) {
      debugPrint('❌ Failed to start recording: $e');
      _isRecording = false;
      rethrow;
    }
  }

  /// Stop recording and return the file
  Future<AudioFile?> stopRecording() async {
    try {
      debugPrint('⏹️ Stopping recording...');
      final path = await _recorder.stop();
      _isRecording = false;
      debugPrint('   Path returned: $path');

      if (path != null && path.isNotEmpty) {
        debugPrint('   ✅ Recording saved to: $path');
        return AudioFile(path);
      }
      debugPrint('⚠️ No recording path returned');
      return null;
    } catch (e) {
      debugPrint('❌ Failed to stop recording: $e');
      _isRecording = false;
      rethrow;
    }
  }

  /// Cancel recording without saving
  Future<void> cancelRecording() async {
    try {
      debugPrint('🗑️ Canceling recording...');
      await _recorder.stop();
      _isRecording = false;

      // Delete the file if it exists (only on non-web platforms)
      if (!kIsWeb && _currentRecordingPath != null) {
        try {
          await platform.deleteFile(_currentRecordingPath!);
          debugPrint('   ✅ Recording file deleted');
        } catch (e) {
          debugPrint('   ⚠️ Could not delete file: $e');
        }
      }
      debugPrint('✅ Recording canceled');
    } catch (e) {
      debugPrint('❌ Failed to cancel recording: $e');
      _isRecording = false;
      rethrow;
    }
  }

  /// Dispose the recorder
  void dispose() {
    _recorder.dispose();
  }

  /// Get recording amplitude (for visual feedback)
  Future<double> getAmplitude() async {
    try {
      final amplitude = await _recorder.getAmplitude();
      return amplitude.current.clamp(0.0, 1.0);
    } catch (e) {
      return 0.0;
    }
  }
}
