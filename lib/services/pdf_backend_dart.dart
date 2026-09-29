import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'pdf_backend.dart';

/// Pure-Dart [PdfBackend] used on all platforms.
///
/// Uses the `pdf` package to load the document and `printing`'s
/// PdfRaster (Skia-based, bundled with the printing plugin) to rasterise
/// pages — no PDFium native library, hence no Gradle/AGP involvement.
class PdfBackendDart implements PdfBackend {
  Document? _doc;

  @override
  Future<void> open(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    _doc = await Document.load(bytes);
  }

  @override
  int get pagesCount => _doc?.pagesCount ?? 0;

  @override
  Future<PdfPageData> renderPage(int pageNumber, double targetWidthPx) async {
    final doc = _doc;
    if (doc == null) throw StateError('Document not opened');
    final page = doc.getPage(pageNumber - 1);
    final ptWidth = page.width.toDouble();
    final ptHeight = page.height.toDouble();
    final scale = (targetWidthPx / ptWidth).clamp(0.1, 8.0);
    final w = (ptWidth * scale).round().clamp(1, 4096);
    final h = (ptHeight * scale).round().clamp(1, 4096);

    final raster =
        await PdfRaster.fromPage(doc, pageNumber - 1, width: w, height: h);
    final png = await raster.toPngImageData();
    return PdfPageData(png, raster.width, raster.height);
  }

  @override
  Future<void> dispose() async {
    // The `pdf` Document holds only in-memory structures; nothing to free.
    _doc = null;
  }
}
