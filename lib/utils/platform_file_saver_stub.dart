import 'dart:typed_data';

/// Web and Wasm stub implementation for saving and opening files.
Future<bool> platformSaveAndOpenFile({
  required Uint8List bytes,
  required String title,
  required String extension,
}) async {
  // Web / Wasm does not support local dart:io filesystem access or OpenFilex.
  return false;
}
