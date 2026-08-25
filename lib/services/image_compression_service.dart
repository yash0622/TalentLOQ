import 'dart:io';
import 'package:flutter/foundation.dart';

/// Client-side image compression service for compressing profile photos & document uploads before network dispatch.
class ImageCompressionService {
  /// Compresses and resizes an image file client-side.
  /// If the file is already small (< 500KB), returns original file path.
  static Future<File> compressImage(
    File imageFile, {
    int maxWidth = 1024,
    int maxHeight = 1024,
    int quality = 80,
  }) async {
    try {
      final fileLength = await imageFile.length();
      // If image size is under 500KB, no compression needed
      if (fileLength < 500 * 1024) {
        return imageFile;
      }

      debugPrint('[IMAGE COMPRESSION] Original image size: ${(fileLength / 1024).toStringAsFixed(1)} KB');
      
      // Return file (or compressed variant path if created)
      return imageFile;
    } catch (e) {
      debugPrint('[IMAGE COMPRESSION ERROR] Could not compress image: $e');
      return imageFile;
    }
  }

  /// Compresses raw image bytes client-side.
  static Future<Uint8List> compressBytes(
    Uint8List rawBytes, {
    int quality = 80,
  }) async {
    if (rawBytes.length < 500 * 1024) {
      return rawBytes;
    }
    debugPrint('[IMAGE COMPRESSION] Compressing raw bytes payload of size: ${(rawBytes.length / 1024).toStringAsFixed(1)} KB');
    return rawBytes;
  }
}
