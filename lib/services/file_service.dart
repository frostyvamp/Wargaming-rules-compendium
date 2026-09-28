import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// Handles moving rule files into the app's private storage.
/// We never reference the user's original file directly because:
///  - On Android, picked files live in a cache the OS can clear.
///  - On any platform, the user might move or delete the original.
/// Copying makes the library self-contained and offline-safe.
class FileService {
  static final FileService instance = FileService._internal();
  FileService._internal();

  /// Copies a PDF from anywhere on disk into the app's private
  /// books/ folder and returns the new internal path.
  Future<String> importPdf(String sourcePath, String title) async {
    final appDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appDir.path, 'books'));
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }

    // Build a filesystem-safe filename: timestamp + cleaned title
    final safeName = title.replaceAll(RegExp(r'[^\w\d-]'), '_');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = p.join(booksDir.path, '$stamp-$safeName.pdf');

    await File(sourcePath).copy(destPath);
    debugPrint('Imported book stored at: $destPath');
    return destPath;
  }

  /// Deletes a rule file from app storage when a book is removed.
  Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}