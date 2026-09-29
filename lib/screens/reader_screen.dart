import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../models/game_model.dart';
import '../services/database_service.dart';
import '../services/pdf_backend.dart';
import '../services/pdf_backend_dart.dart';

// pdfx was replaced by a pure-Dart backend (pdf + printing): pdfx's
// native PDFium Android plugin is incompatible with the AGP 9 build
// chain required by current Flutter stable. The lazy per-page raster
// approach is kept so zoom stays crisp on the Fold5's screens.
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

  PdfBackend? _doc;
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
    _doc?.dispose();
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
    final doc = PdfBackendDart();
    await doc.open(widget.book.filePath);

    if (!mounted) return;
    setState(() {
      _doc = doc;
      _totalPages = doc.pagesCount;
      _currentPage = startPage.clamp(1, doc.pagesCount);
      _sliderValue = _currentPage.toDouble();
    });
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
    _scrollToPage(target, animate: true);
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

  // ---------- Zoom ----------

  void _setZoomPercent(int percent) {
    final target = percent.clamp(_minPercent, _maxPercent);
    if (target == _zoomPercent) return;
    setState(() => _zoomPercent = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToPage(_currentPage, animate: false);
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _ctrlHeld) {
      final delta = event.scrollDelta.dy > 0 ? -10 : 10;
      _setZoomPercent(_zoomPercent + delta);
    }
  }

  // ---------- UI ----------

  List<Widget> _buildOverlays(double maxHeight) {
    return [
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          color: Colors.black.withOpacity(0.35),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () => _goToPage(_currentPage - 1),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: _sliderValue.clamp(1, _totalPages.toDouble()),
                    min: 1,
                    max: _totalPages.toDouble(),
                    divisions: _totalPages > 1 ? _totalPages - 1 : null,
                    onChanged: _totalPages > 1
                        ? (v) {
                            setState(() => _draggingSlider = true);
                            _goToPage(v.round());
                          }
                        : null,
                    onChangeEnd: (_) =>
                        setState(() => _draggingSlider = false),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () => _goToPage(_currentPage + 1),
              ),
              Text('$_currentPage / $_totalPages',
                  style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    ];
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
      actions: [
        PopupMenuButton<int>(
          icon: const Icon(Icons.zoom_out_map),
          tooltip: 'Zoom',
          onSelected: _setZoomPercent,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 50, child: Text('50%')),
            PopupMenuItem(value: 75, child: Text('75%')),
            PopupMenuItem(value: 100, child: Text('100%')),
            PopupMenuItem(value: 150, child: Text('150%')),
            PopupMenuItem(value: 200, child: Text('200%')),
            PopupMenuItem(value: 300, child: Text('300%')),
          ],
        ),
      ],
    );
  }

  Widget _buildReaderView() {
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
    // FIX (Fold5 gesture-nav overlap): the app is edge-to-edge on Android,
    // so MediaQuery.padding.bottom carries the system navigation-bar inset.
    // Without this, the page slider overlay sits under the nav buttons.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: _buildAppBar(),
      body: _doc == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: _buildReaderView(),
            ),
    );
  }
}

/// One lazily rendered PDF page. Requests its raster at an explicit
/// pixel width so zoom is always crisp.
class _PageImage extends StatefulWidget {
  final PdfBackend document;
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
  // Renders must be strictly one-at-a-time to keep memory bounded and
  // avoid saturating the raster isolate.
  static Future<void> _renderQueue = Future.value();
  static final Map<String, Future<PdfPageData>> _cache = {};

  Future<PdfPageData>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // FIX (Fold5 red screen): _load() reads MediaQuery.devicePixelRatioOf,
    // which registers an inherited-widget dependency. Calling it from
    // initState() threw "dependOnInheritedWidgetOfExactType<MediaQuery>()
    // ... was called before _PageImageState.initState() completed".
    // didChangeDependencies runs after initState with a fully valid context.
    _load();
  }

  @override
  void didUpdateWidget(covariant _PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logicalWidth != widget.logicalWidth ||
        oldWidget.pageNumber != widget.pageNumber) {
      _load();
    }
  }

  void _load() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (widget.logicalWidth * dpr).round().toDouble();
    final key = '${widget.ownerKey}:${widget.pageNumber}@${px.round()}';
    _future = _cache.putIfAbsent(key, () {
      final completer = Completer<PdfPageData>();
      _renderQueue = _renderQueue.then<void>((_) async {
        try {
          final image = await widget.document
              .renderPage(widget.pageNumber, px)
              .timeout(const Duration(seconds: 30));
          completer.complete(image);
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
    return FutureBuilder<PdfPageData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final img = snapshot.data!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onAspectKnown(img.aspect);
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
