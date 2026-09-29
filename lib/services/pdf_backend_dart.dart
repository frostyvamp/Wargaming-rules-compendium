import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/rendering.dart' as rendering;
import 'package:printing/printing.dart';

import 'pdf_backend.dart';

/// Pure-Dart [PdfBackend] used on all platforms.
///
/// Page structure comes from the `pdf` package's pure-Dart parser;
/// rasterisation goes through `printing`'s platform renderer (Android's
/// system PDF engine, Windows Pdfium, Apple PDFKit). No PDFium Gradle
/// subproject like pdfx had, so it builds cleanly under AGP 9.
class PdfBackendDart implements PdfBackend {
  rendering.PdfDocument? _doc;
  Uint8List? _bytes;
  int _pagesCount = 0;
  double _aspect = 1.414;

  @override
  Future<void> open(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    // Throws if the file is not a valid PDF.
    final doc = await rendering.PdfDocument.parseBytes(bytes);
    _bytes = bytes;
    _doc = doc;
    _pagesCount = doc.pagesCount;
    final first = doc.getPage(0);
    if (first.width > 0) _aspect = first.height / first.width;
  }

  @override
  int get pagesCount => _pagesCount;

  @override
  Future<PdfPageData> renderPage(int pageNumber, double targetWidthPx) async {
    final bytes = _bytes;
    if (bytes == null) throw StateError('Document not opened');
    final w = targetWidthPx.round().clamp(1, 4096);
    final h = (w * _aspect).round().clamp(1, 65536);
    // Printing.raster serialises jobs internally and runs them off the
    // UI thread. The timeout mirrors the reader's own guard.
    final image = await Printing.raster(
      bytes,
      page: pageNumber - 1, // printing uses 0-based pages
      dpi: 150,
      format: PdfRasterFormat.png,
      width: w,
      height: h,
    ).first.timeout(const Duration(seconds: 25));
    return PdfPageData(image.toPng(), image.width, image.height);
  }

  @override
  Future<void> dispose() async {
    final doc = _doc;
    _doc = null;
    _bytes = null;
    try {
      await doc?.dispose();
    } catch (_) {
      // Dispose errors are non-fatal; the process owns the memory anyway.
    }
  }
}
