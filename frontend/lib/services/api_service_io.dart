// Mobile/Desktop implementation for multipart file upload
// Uses dart:io for file access

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Create multipart file from file path (mobile/desktop)
Future<http.MultipartFile> createMultipartFile(
  String fieldName,
  String filePath,
) async {
  debugPrint('   📱 Mobile/Desktop: Reading file from path...');
  return await http.MultipartFile.fromPath(fieldName, filePath);
}
