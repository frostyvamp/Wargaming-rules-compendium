import 'dart:typed_data';

/// Minimal PDF backend abstraction used by the reader.
///
/// Replaces pdfx: its native PDFium Android plugin is incompatible with
/// the AGP 9 build chain required by current Flutter stable. Pages are
/// rendered by a pure-Dart backend (`pdf` + `printing`) instead, so the
/// app no longer depends on any platform-specific PDF engine.
class PdfPageData {
  /// Decoded image bytes (PNG) of the rendered page.
  final Uint8List bytes;
  final int widthPx;
  final int heightPx;

  const PdfPageData(this.bytes, this.widthPx, this.heightPx);

  double get aspect => widthPx > 0 ? heightPx / widthPx : 1.414;
}

abstract class PdfBackend {
  Future<void> open(String filePath);

  int get pagesCount;

  /// Render [pageNumber] (1-based) so its raster is about [targetWidthPx]
  /// pixels wide. Calls are serialised by the caller's render queue.
  Future<PdfPageData> renderPage(int pageNumber, double targetWidthPx);

  Future<void> dispose();
}
