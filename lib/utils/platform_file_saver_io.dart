import 'dart:io' as io;
import 'dart:typed_data';
import 'package:open_filex/open_filex.dart';

/// Native (Android, iOS, Windows, macOS, Linux) implementation for saving and opening files.
Future<bool> platformSaveAndOpenFile({
  required Uint8List bytes,
  required String title,
  required String extension,
}) async {
  try {
    final tempDir = io.Directory.systemTemp;
    final cleanName = title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final targetFile = io.File('${tempDir.path}/${cleanName}_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await targetFile.writeAsBytes(bytes);

    final openResult = await OpenFilex.open(targetFile.path);
    return openResult.type == ResultType.done;
  } catch (_) {
    return false;
  }
}
