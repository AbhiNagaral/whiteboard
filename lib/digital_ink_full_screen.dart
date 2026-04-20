import 'dart:async';
import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';
import 'signature_painter.dart';

class DigitalInkFullScreen extends StatefulWidget {
  final String languageCode;
  const DigitalInkFullScreen({Key? key, required this.languageCode}) : super(key: key);

  @override
  State<DigitalInkFullScreen> createState() => _DigitalInkFullScreenState();
}

class _DigitalInkFullScreenState extends State<DigitalInkFullScreen> with SingleTickerProviderStateMixin {
  late final DigitalInkRecognizer _recognizer;
  final DigitalInkRecognizerModelManager _modelManager = DigitalInkRecognizerModelManager();

  late AnimationController _fadeController;
  late Animation<double> _inkOpacity;

  final Ink _ink = Ink();
  List<StrokePoint> _currentStrokePoints = [];
  Map<int, String> _linePreviews = {};

  bool _isReadOnlyMode = false;
  bool _isEraserMode = false;
  bool _isModelReady = false;
  bool _isProcessing = false;
  bool _isMenuOpen = false;
  bool _isLandscape = false;
  bool _isPreviewExpanded = false;

  final double _canvasHeight = 3000.0;
  final double _canvasWidth = 5000.0; // Ample width for horizontal scrolling [cite: 191]
  final double _gridSpacing = 120.0;

  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  Timer? _debounceTimer;
  Timer? _scrollDebounce;
  Timer? _eraserLockTimer;
  int? _lastErasedIndex;
  int? _lastErasedLine;

  @override
  void initState() {
    super.initState();
    _recognizer = DigitalInkRecognizer(languageCode: widget.languageCode);
    _checkModelStatus();

    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _inkOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(_fadeController);

    _horizontalScrollController.addListener(() => setState(() {}));
  }

  Future<void> _checkModelStatus() async {
    final isDownloaded = await _modelManager.isModelDownloaded(widget.languageCode);
    if (mounted) setState(() => _isModelReady = isDownloaded);
  }

  void _handleVelocityAutoScroll(Offset position, double velocityX) {
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final screenWidth = MediaQuery.of(context).size.width;
      final currentHOffset = _horizontalScrollController.offset;

      double dynamicTrigger = velocityX > 500 ? 0.7 : 0.8;
      double triggerEdge = currentHOffset + (screenWidth * dynamicTrigger);

      if (position.dx > triggerEdge) {
        double targetOffset = (position.dx - (screenWidth * 0.2)).clamp(0, _canvasWidth - screenWidth);
        _horizontalScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _onUserStoppedScribbling() {
    // Reset timer every time user moves the pen [cite: 10]
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () async {
      if (_ink.strokes.isNotEmpty) {
        await _fadeController.forward();
        _performRecognition(isPreview: true);
        _fadeController.reset();
      }
    });
  }

  Future<void> _performRecognition({bool isPreview = false}) async {
    if (!_isModelReady || _ink.strokes.isEmpty) return;
    if (!isPreview) setState(() => _isProcessing = true);

    Map<int, Ink> lineInks = {};
    for (var stroke in _ink.strokes) {
      if (stroke.points.isEmpty) continue;
      double avgY = stroke.points.map((p) => p.y).reduce((a, b) => a + b) / stroke.points.length;
      int lineIndex = (avgY / _gridSpacing).floor();
      if (!lineInks.containsKey(lineIndex)) lineInks[lineIndex] = Ink();
      lineInks[lineIndex]!.strokes.add(stroke);
    }

    try {
      for (var entry in lineInks.entries) {
        final candidates = await _recognizer.recognize(entry.value);
        if (candidates.isNotEmpty) {
          setState(() {
            String existingText = _linePreviews[entry.key] ?? "";
            _linePreviews[entry.key] = existingText.isEmpty
                ? candidates.first.text
                : "$existingText ${candidates.first.text}";
            _ink.strokes.removeWhere((s) => lineInks[entry.key]!.strokes.contains(s));
          });
        }
      }
      if (!isPreview) {
        final sortedKeys = _linePreviews.keys.toList()..sort();
        Navigator.pop(context, sortedKeys.map((i) => _linePreviews[i]).join('\n'));
      }
    } catch (e) {
      debugPrint("Recognition Error: $e");
    } finally {
      if (!isPreview) setState(() => _isProcessing = false);
    }
  }

  void _erasePointsAt(Offset position) {
    setState(() {
      int lineIndex = (position.dy / _gridSpacing).floor();
      double localYInRow = position.dy % _gridSpacing;

      // Vertical offset fixed: hit-box now strictly aligned with text
      if (localYInRow >= 5 && localYInRow <= 55 && _linePreviews.containsKey(lineIndex)) {
        String currentText = _linePreviews[lineIndex]!;
        final textPainter = TextPainter(
          text: TextSpan(text: currentText, style: const TextStyle(fontSize: 22, fontFamily: 'monospace')),
          textDirection: TextDirection.ltr,
        )..layout();

        double relativeX = position.dx - (_horizontalScrollController.offset + 24);
        if (relativeX >= 0) {
          TextPosition pos = textPainter.getPositionForOffset(Offset(relativeX, 10));
          int index = pos.offset;
          if (index >= 0 && index < currentText.length) {
            if (_lastErasedIndex == index && _lastErasedLine == lineIndex) return;
            _linePreviews[lineIndex] = currentText.substring(0, index) + " " + currentText.substring(index + 1);
            _lastErasedIndex = index;
            _lastErasedLine = lineIndex;

            _eraserLockTimer?.cancel();
            _eraserLockTimer = Timer(const Duration(seconds: 1), () {
              if (mounted) setState(() {
                _linePreviews.forEach((key, value) => _linePreviews[key] = value.replaceAll(RegExp(r' +'), ' ').trim());
                _linePreviews.removeWhere((k, v) => v.isEmpty);
                _lastErasedIndex = null; _lastErasedLine = null;
              });
            });
          }
        }
      }
      for (var s in _ink.strokes) s.points.removeWhere((p) => (Offset(p.x, p.y) - position).distance < 25.0);
      _ink.strokes.removeWhere((s) => s.points.isEmpty);
    });
  }

  void _toggleRotation() {
    setState(() {
      _isLandscape = !_isLandscape;
      SystemChrome.setPreferredOrientations(_isLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp]);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isModelReady) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final sortedPreviewKeys = _linePreviews.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium Whiteboard'),
        actions: [
          IconButton(icon: Icon(_isLandscape ? Icons.screen_lock_portrait : Icons.screen_lock_landscape), onPressed: _toggleRotation),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() { _ink.strokes.clear(); _linePreviews.clear(); })),
        ],
      ),
      floatingActionButton: _buildFABMenu(),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _inkOpacity,
              builder: (context, child) => _buildCanvasArea(_inkOpacity.value),
            ),
          ),
          if (_linePreviews.isNotEmpty) _buildBottomPreview(sortedPreviewKeys),
          _buildDoneButton(),
        ],
      ),
    );
  }

  Widget _buildFABMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isMenuOpen) ...[
          _miniFAB(Icons.pan_tool, Colors.green, () => setState(() { _isReadOnlyMode = true; _isEraserMode = false; _isMenuOpen = false; })),
          const SizedBox(height: 12),
          _miniFAB(Icons.auto_fix_high, Colors.orange, () => setState(() { _isReadOnlyMode = false; _isEraserMode = true; _isMenuOpen = false; })),
          const SizedBox(height: 12),
          _miniFAB(Icons.edit, Colors.blue, () => setState(() { _isReadOnlyMode = false; _isEraserMode = false; _isMenuOpen = false; })),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          heroTag: 'main_fab',
          backgroundColor: Colors.blueAccent,
          child: Icon(_isMenuOpen ? Icons.close : (_isEraserMode ? Icons.auto_fix_high : (_isReadOnlyMode ? Icons.pan_tool : Icons.edit))),
          onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
        ),
      ],
    );
  }

  Widget _miniFAB(IconData icon, Color color, VoidCallback onPressed) => FloatingActionButton.small(heroTag: null, backgroundColor: Colors.white, child: Icon(icon, color: color), onPressed: onPressed);

  Widget _buildCanvasArea(double opacity) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          controller: _verticalScrollController,
          physics: _isReadOnlyMode ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            physics: _isReadOnlyMode ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
            child: GestureDetector(
              onPanStart: _isReadOnlyMode ? null : (d) {
                // Cancel recognition timer when user touches the screen [cite: 10]
                _debounceTimer?.cancel();
                if (!_isEraserMode) {
                  setState(() {
                    _ink.strokes.add(Stroke());
                    _currentStrokePoints = [];
                  });
                } else {
                  _erasePointsAt(d.localPosition);
                }
              },
              onPanUpdate: _isReadOnlyMode ? null : (d) {
                if (_isEraserMode) {
                  _erasePointsAt(d.localPosition);
                } else if (_ink.strokes.isNotEmpty) {
                  // Safety check implemented here to prevent StateError [cite: 181, 219]
                  setState(() {
                    final point = StrokePoint(x: d.localPosition.dx, y: d.localPosition.dy, t: DateTime.now().millisecondsSinceEpoch);
                    _currentStrokePoints.add(point);
                    _ink.strokes.last.points = List.from(_currentStrokePoints);
                    _handleVelocityAutoScroll(d.localPosition, d.delta.dx.abs());
                  });
                }
              },
              onPanEnd: _isReadOnlyMode ? null : (_) => _onUserStoppedScribbling(),
              child: Container(
                color: Colors.white, width: _canvasWidth, height: _canvasHeight,
                child: CustomPaint(
                  painter: SignaturePainter(
                    ink: _ink, gridSpacing: _gridSpacing, linePreviews: _linePreviews,
                    horizontalOffset: _horizontalScrollController.hasClients ? _horizontalScrollController.offset : 0.0,
                    inkOpacity: opacity,
                  ),
                  size: Size(_canvasWidth, _canvasHeight),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPreview(List<int> keys) {
    return GestureDetector(
      onTap: () => setState(() => _isPreviewExpanded = !_isPreviewExpanded),
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.blue.shade50,
        child: Column(
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text("Live Text Preview", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              Icon(_isPreviewExpanded ? Icons.expand_more : Icons.expand_less),
            ]),
            if (_isPreviewExpanded) ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: ListView(shrinkWrap: true, children: keys.map((k) => Text("Line ${k+1}: ${_linePreviews[k]}")).toList()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneButton() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: FilledButton(
      onPressed: _isProcessing ? null : () => _performRecognition(isPreview: false),
      child: _isProcessing ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Done"),
    ),
  );

  @override
  void dispose() {
    _fadeController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _recognizer.close();
    super.dispose();
  }
}