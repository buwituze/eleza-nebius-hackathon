// Stub implementation for Web platform
// This file is used when dart:io is not available (web)

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

String getPlatformName() {
  return 'web';
}

AudioEncoder getAudioEncoder() {
  // Web supports WAV format
  return AudioEncoder.wav;
}

String getFileExtension() {
  return 'wav';
}

Future<void> deleteFile(String path) async {
  // On web, files are in browser memory/IndexedDB
  // No file system deletion needed
  debugPrint('   ℹ️ Web platform - no file deletion needed');
}
