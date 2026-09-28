import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import '../models/game_model.dart';
import '../services/database_service.dart';

/// Renders a Book's PDF with a backend per platform:
///  - Windows: pdfx PdfView (instant, reliable, no zoom) so desktop
///    stays a fast playground for search and database features.
///  - Android: custom lazy page renderer with crisp zoom and pinch.
class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final DatabaseService _db = DatabaseService.instance;
  final TransformationController _transformController =
      TransformationController();
  final ScrollController _hScrollController = ScrollController();
  final ScrollController _vScrollController = ScrollController();

  PdfDocument? _doc;
  PdfController? _pdfController; // Windows backend only.
  int _currentPage = 1;
  int _totalPages = 1;
  double _sliderValue = 1;
  bool _draggingSlider = false;

  int _zoomPercent = 100;
  int _gestureStartPercent = 100;
  bool _ctrlHeld = false;
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  double _pageAspect = 1.414;

  static const int _minPercent = 50;
  static const int _maxPercent = 300;
  static const double _bubbleHeight = 28;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _bootstrap();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _db.updateBookLastPage(widget.book.id!, _currentPage);
    _transformController.dispose();
    _hScrollController.dispose();
    _vScrollController.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    final isCtrl = event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight;
    if (isCtrl) {
      final down = event is KeyDownEvent || event is KeyRepeatEvent;
      if (down != _ctrlHeld) setState(() => _ctrlHeld = down);
    }
    return false;
  }

  Future<void> _bootstrap() async {
    final fresh = await _db.getBook(widget.book.id!);
    final startPage = fresh?.lastPage ?? widget.book.lastPage;
    final doc = await PdfDocument.openFile(widget.book.filePath);

    if (!mounted) return;
    setState(() {
      _doc = doc;
      _totalPages = doc.pagesCount;
      _currentPage = startPage.clamp(1, doc.pagesCount);
      _sliderValue = _currentPage.toDouble();
      if (Platform.isWindows) {
        _pdfController = PdfController(
          document: Future.value(doc),
          initialPage: _currentPage,
        );
      }
    });
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToPage(_currentPage, animate: false);
    });
  }

  double get _factor => _zoomPercent / 100.0;
  double get _pageWidth => _viewportWidth * _factor;
  double get _pageHeight => _pageWidth * _pageAspect;

  // ---------- Navigation ----------

  void _goToPage(int page) {
    final target = page.clamp(1, _totalPages);
    if (Platform.isWindows) {
      _pdfController?.jumpToPage(target);
    } else {
      _scrollToPage(target, animate: true);
    }
    setState(() {
      _currentPage = target;
      _sliderValue = target.toDouble();
    });
  }

  void _scrollToPage(int page, {bool animate = false}) {
    if (!_vScrollController.hasClients) return;
    final target = page.clamp(1, _totalPages);
    final offset = ((target - 1) * _pageHeight)
        .clamp(0.0, _vScrollController.position.maxScrollExtent);
    if (animate) {
      _vScrollController.animateTo(offset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut);
    } else {
      _vScrollController.jumpTo(offset);
    }
  }

  void _onVerticalScroll(ScrollNotification notification) {
    if (_pageHeight <= 0) return;
    final center = notification.metrics.pixels + _viewportHeight / 2;
    final page = (center / _pageHeight).ceil().clamp(1, _totalPages);
    if (page != _currentPage) {
      setState(() {
        _currentPage = page;
        if (!_draggingSlider) _sliderValue = page.toDouble();
      });
    }
  }

  // ---------- Zoom (Android backend) ----------

  void _setZoomPercent(int percent) {
    final target = percent.clamp(_minPercent, _maxPercent);
    if (target == _zoomPercent) return;
    final oldHeight = _pageHeight;
    final oldOffset =
        _vScrollController.hasClients ? _vScrollController.offset : 0.0;
    final oldHContent = _viewportWidth * _factor;
    final oldHCenter = _hScrollController.hasClients
        ? _hScrollController.offset + _viewportWidth / 2
        : _viewportWidth / 2;
    setState(() => _zoomPercent = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_vScrollController.hasClients) {
        final oldCenter = oldOffset + _viewportHeight / 2;
        final fraction = oldHeight <= 0 ? 0.0 : oldCenter / oldHeight;
        final maxOffset = _vScrollController.position.maxScrollExtent;
        _vScrollController.jumpTo(
            (fraction * _pageHeight - _viewportHeight / 2)
                .clamp(0.0, maxOffset));
      }
      if (_hScrollController.hasClients && _viewportWidth > 0) {
        final hFraction = oldHContent <= 0
            ? 0.0
            : (oldHCenter / oldHContent).clamp(0.0, 1.0);
        final hMax = math.max(0.0, _pageWidth - _viewportWidth);
        _hScrollController.jumpTo(
            (hFraction * _pageWidth - _viewportWidth / 2).clamp(0.0, hMax));
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      final step = event.scrollDelta.dy < 0 ? 10 : -10;
      _setZoomPercent(_zoomPercent + step);
    }
  }

  Future<void> _showJumpDialog() async {
    final controller = TextEditingController(text: '$_currentPage');
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Jump to page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: '1 - $_totalPages'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Jump'),
          ),
        ],
      ),
    );
    final parsed = int.tryParse(input?.trim() ?? '');
    if (parsed != null) _goToPage(parsed);
  }

  // ---------- UI ----------

  AppBar _buildAppBar({required bool showZoom}) {
    return AppBar(
      title: Text(widget.book.title),
      actions: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed:
              _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
        ),
        Center(
          child: Text(
            '$_currentPage / $_totalPages',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: _currentPage < _totalPages
              ? () => _goToPage(_currentPage + 1)
              : null,
        ),
        if (showZoom)
          PopupMenuButton<int>(
            tooltip: 'Zoom',
            onSelected: _setZoomPercent,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 50, child: Text('50%')),
              PopupMenuItem(value: 100, child: Text('100%')),
              PopupMenuItem(value: 125, child: Text('125%')),
              PopupMenuItem(value: 150, child: Text('150%')),
              PopupMenuItem(value: 200, child: Text('200%')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_in),
                  Text('$_zoomPercent%'),
                ],
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.format_list_numbered),
          tooltip: 'Jump to page',
          onPressed: _showJumpDialog,
        ),
      ],
    );
  }

  List<Widget> _buildOverlays(double trackHeight) {
    final span = (_totalPages - 1).toDouble().clamp(1.0, double.infinity);
    final fraction = ((_sliderValue - 1) / span).clamp(0.0, 1.0);
    final maxTop = (trackHeight - _bubbleHeight).clamp(0.0, double.infinity);
    final bubbleTop = (fraction * maxTop).clamp(0.0, maxTop);

    return [
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        child: SizedBox(
          width: 40,
          child: RotatedBox(
            quarterTurns: 1,
            child: Slider(
              value: _sliderValue.clamp(1.0, _totalPages.toDouble()),
              min: 1,
              max: _totalPages.toDouble(),
              onChanged: (v) {
                setState(() {
                  _draggingSlider = true;
                  _sliderValue = v;
                });
              },
              onChangeEnd: (v) {
                setState(() => _draggingSlider = false);
                _goToPage(v.round());
              },
            ),
          ),
        ),
      ),
      if (_draggingSlider)
        Positioned(
          right: 48,
          top: bubbleTop,
          child: Container(
            height: _bubbleHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            alignment: Alignment.center,
            child: Text(
              '${_sliderValue.round()} / $_totalPages',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
    ];
  }

  Widget _buildWindowsView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: PdfView(
                controller: _pdfController!,
                scrollDirection: Axis.vertical,
                pageSnapping: false,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                    if (!_draggingSlider) _sliderValue = page.toDouble();
                  });
                },
              ),
            ),
            ..._buildOverlays(constraints.maxHeight),
          ],
        );
      },
    );
  }

  Widget _buildAndroidView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        _viewportHeight = constraints.maxHeight;

        final Widget pageColumn = SizedBox(
          width: _pageWidth,
          height: constraints.maxHeight,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                _onVerticalScroll(n);
                return false;
              },
              child: ListView.builder(
                controller: _vScrollController,
                physics: _ctrlHeld
                    ? const NeverScrollableScrollPhysics()
                    : null,
                itemCount: _totalPages,
                itemBuilder: (context, index) => _PageImage(
                  document: _doc!,
                  ownerKey: widget.book.filePath,
                  pageNumber: index + 1,
                  logicalWidth: _pageWidth,
                  onAspectKnown: (aspect) {
                    if ((aspect - _pageAspect).abs() > 0.001) {
                      setState(() => _pageAspect = aspect);
                    }
                  },
                ),
              ),
            ),
          ),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _hScrollController,
                scrollDirection: Axis.horizontal,
                child: Center(
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    panEnabled: false,
                    minScale: 0.5,
                    maxScale: 3.0,
                    onInteractionStart: (_) =>
                        _gestureStartPercent = _zoomPercent,
                    onInteractionEnd: (_) {
                      final scale =
                          _transformController.value.getMaxScaleOnAxis();
                      _transformController.value = Matrix4.identity();
                      if (scale != 1.0) {
                        _setZoomPercent(
                            (_gestureStartPercent * scale).round());
                      }
                    },
                    child: pageColumn,
                  ),
                ),
              ),
            ),
            ..._buildOverlays(constraints.maxHeight),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(showZoom: !Platform.isWindows),
      body: _doc == null
          ? const Center(child: CircularProgressIndicator())
          : Platform.isWindows
              ? _buildWindowsView()
              : _buildAndroidView(),
    );
  }
}

/// One lazily rendered PDF page for the Android backend. Requests its
/// raster at an explicit pixel width so zoom is always crisp.
class _PageImage extends StatefulWidget {
  final PdfDocument document;
  final String ownerKey;
  final int pageNumber;
  final double logicalWidth;
  final ValueChanged<double> onAspectKnown;

  const _PageImage({
    required this.document,
    required this.ownerKey,
    required this.pageNumber,
    required this.logicalWidth,
    required this.onAspectKnown,
  });

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  // Renders must be strictly one-at-a-time: pdfx's PDFium backend
  // deadlocks when several page renders run concurrently.
  static Future<void> _renderQueue = Future.value();
  static final Map<String, Future<PdfPageImage>> _cache = {};

  Future<PdfPageImage>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logicalWidth != widget.logicalWidth) _load();
  }

  void _load() {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final px = (widget.logicalWidth * dpr).round();
    final key = '${widget.ownerKey}:${widget.pageNumber}@$px';
    _future = _cache.putIfAbsent(key, () {
      final completer = Completer<PdfPageImage>();
      _renderQueue = _renderQueue.then<void>((_) async {
        try {
          final page = await widget.document.getPage(widget.pageNumber);
          try {
            final dynamic rawWidth = page.width;
            final dynamic rawHeight = page.height;
            final double pageW =
                rawWidth == null ? 1.0 : (rawWidth as num).toDouble();
            final double pageH = rawHeight == null
                ? pageW * 1.414
                : (rawHeight as num).toDouble();
            final double aspect = pageW > 0 ? pageH / pageW : 1.414;
            final image = await page
                .render(
                  width: px.toDouble(),
                  height: px.toDouble() * aspect,
                  format: PdfPageImageFormat.jpeg,
                )
                .timeout(const Duration(seconds: 20));
            if (image == null) {
              throw StateError(
                  'PDFium returned no image for page ${widget.pageNumber}');
            }
            completer.complete(image);
          } finally {
            await page.close();
          }
        } catch (e) {
          _cache.remove(key);
          completer.completeError(e);
        }
      });
      return completer.future;
    });
    if (_cache.length > 60) {
      _cache.removeWhere((k, _) => !k.startsWith('${widget.ownerKey}:'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PdfPageImage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final img = snapshot.data!;
          final w = img.width ?? 0;
          final h = img.height ?? 0;
          final aspect = w > 0 ? h / w : 1.414;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onAspectKnown(aspect);
          });
          return Image.memory(
            img.bytes,
            width: widget.logicalWidth,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
          );
        }
        if (snapshot.hasError) {
          return Container(
            width: widget.logicalWidth,
            height: widget.logicalWidth * 1.414,
            color: Colors.red.shade900,
            child: Center(child: Text('Page ${widget.pageNumber} failed')),
          );
        }
        return Container(
          width: widget.logicalWidth,
          height: widget.logicalWidth * 1.414,
          color: Colors.white10,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}