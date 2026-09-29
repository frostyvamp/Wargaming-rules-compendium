import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'pdf_backend.dart';

/// Pure-Dart [PdfBackend] used on all platforms.
///
/// Rasterisation goes through `printing`'s platform renderer (Android's
/// system PDF engine, Windows Pdfium, Apple PDFKit). No PDFium Gradle
/// subproject like pdfx had, so it builds cleanly under AGP 9. The page
/// count is discovered on [open] by streaming the document once at a low
/// dpi and counting the rasters produced.
class PdfBackendDart implements PdfBackend {
  Uint8List? _bytes;
  int _pagesCount = 0;

  @override
  Future<void> open(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('Not a valid PDF file');
    }
    // Count pages: the raster stream emits one item per page and completes
    // when the document ends. 36 dpi keeps this discovery pass cheap.
    var count = 0;
    await for (final _ in Printing.raster(bytes, dpi: 36).take(5000)) {
      count++;
    }
    if (count == 0) throw const FormatException('PDF has no renderable pages');
    _bytes = bytes;
    _pagesCount = count;
  }

  @override
  int get pagesCount => _pagesCount;

  @override
  Future<PdfPageData> renderPage(int pageNumber, double targetWidthPx) async {
    final bytes = _bytes;
    if (bytes == null) throw StateError('Document not opened');
    // printing uses 0-based pages.
    final idx = (pageNumber - 1).clamp(0, _pagesCount - 1);
    final w = targetWidthPx.round().clamp(1, 4096);
    // dpi controls raster resolution: scale so an A4-wide page (595 pt)
    // comes out about targetWidthPx pixels wide.
    final dpi = (72.0 * w / 595.0).clamp(72.0, 300.0);
    final image = await Printing.raster(bytes, pages: <int>[idx], dpi: dpi)
        .first
        .timeout(const Duration(seconds: 25));
    return PdfPageData(await image.toPng(), image.width, image.height);
  }

  @override
  Future<void> dispose() async {
    _bytes = null;
    _pagesCount = 0;
  }
}