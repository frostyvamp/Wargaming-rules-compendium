import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'pdf_backend.dart';

/// Pure-Dart [PdfBackend] used on all platforms.
///
/// Uses the `pdf` package to read document metadata (page count, page
/// sizes) and the `printing` plugin's rasteriser (platform PDFium/pdf.js)
/// to render pages to PNG — no pdfx, so no AGP-incompatible Gradle plugin.
class PdfBackendDart implements PdfBackend {
  Uint8List? _bytes;
  PdfDocument? _doc;

  @override
  Future<void> open(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    _bytes = bytes;
    _doc = PdfDocument.parseBytes(bytes);
  }

  @override
  int get pagesCount => _doc?.pagesCount ?? 0;

  @override
  Future<PdfPageData> renderPage(int pageNumber, double targetWidthPx) async {
    final doc = _doc;
    final bytes = _bytes;
    if (doc == null || bytes == null) throw StateError('Document not opened');

    // Page dimensions in points (1pt = 1/72 inch)
    final page = doc.page(pageNumber - 1)!;
    final ptWidth = page.pageFormat.width;
    final ptHeight = page.pageFormat.height;

    // Convert the desired pixel width into a DPI for the rasteriser.
    final scale = (targetWidthPx / ptWidth).clamp(0.1, 8.0);
    final dpi = (72.0 * scale).clamp(36.0, 576.0);

    final raster = await Printing.raster(
      bytes,
      pages: [pageNumber - 1],
      dpi: dpi,
    ).first;

    final png = await raster.toPng();
    return PdfPageData(png, raster.width, raster.height);
  }

  @override
  Future<void> dispose() async {
    _doc = null;
    _bytes = null;
  }
}