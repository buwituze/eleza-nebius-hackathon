// IO implementation for mobile and desktop platforms
// This file is used when dart:io is available (Android, iOS, Windows, macOS, Linux)

import 'dart:io';
import 'package:record/record.dart';

String getPlatformName() {
  if (Platform.isAndroid) {
    return 'android';
  } else if (Platform.isIOS) {
    return 'ios';
  } else if (Platform.isWindows) {
    return 'windows';
  } else if (Platform.isMacOS) {
    return 'macos';
  } else if (Platform.isLinux) {
    return 'linux';
  }
  return 'unknown';
}

AudioEncoder getAudioEncoder() {
  return AudioEncoder.wav;
}

String getFileExtension() {
  return 'wav';
}

Future<void> deleteFile(String path) async {
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
