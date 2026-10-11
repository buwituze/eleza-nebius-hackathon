// Web implementation for multipart file upload
// Uses dart:html to read blob URLs

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html; // ignore: deprecated_member_use
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

/// Read blob URL and create multipart file for web
Future<http.MultipartFile> createMultipartFile(
  String fieldName,
  String filePath,
) async {
  // On web, filePath is actually a blob URL like:
  // blob:http://localhost:56582/4ca6c4bb-f055-487f-84f5-f8dfdeb5cb82

  debugPrint('   🌐 Web: Reading blob URL...');

  // Use XMLHttpRequest to read the blob
  final xhr = html.HttpRequest();
  xhr.open('GET', filePath);
  xhr.responseType = 'arraybuffer';
  // Subscribe before send() so we don't miss the load event
  final loadFuture = xhr.onLoadEnd.first;
  xhr.send(); // Required: actually send the request
  await loadFuture;

  if (xhr.status == 200) {
    // Get the bytes from the response
    final buffer = xhr.response as ByteBuffer;
    final bytes = buffer.asUint8List();

    debugPrint('   ✅ Read ${bytes.length} bytes from blob');

    // Determine filename and content type
    String filename = 'recording.wav';
    String contentType = 'audio/wav';

    return http.MultipartFile.fromBytes(
      fieldName,
      bytes,
      filename: filename,
      contentType: MediaType.parse(contentType),
    );
  } else {
    throw Exception('Failed to read blob: ${xhr.status}');
  }
}
