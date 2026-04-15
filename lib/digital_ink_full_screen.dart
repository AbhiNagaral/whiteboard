import 'dart:async';
import 'package:flutter/material.dart' hide Ink;
import 'package:flutter/services.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';
import 'signature_painter.dart';

class DigitalInkFullScreen extends StatefulWidget {
  final String languageCode;

  const DigitalInkFullScreen({
    Key? key,
    required this.languageCode
  }) : super(key: key);

  @override
  State<DigitalInkFullScreen> createState() => _DigitalInkFullScreenState();
}

class _DigitalInkFullScreenState extends State<DigitalInkFullScreen> {
  late final DigitalInkRecognizer _recognizer;
  final DigitalInkRecognizerModelManager _modelManager = DigitalInkRecognizerModelManager();

  final Ink _ink = Ink();
  List<StrokePoint> _currentStrokePoints = [];

  bool _isReadOnlyMode = false;
  bool _isEraserMode = false;
  bool _isModelReady = false;
  bool _isProcessing = false;
  bool _isMenuOpen = false;
  bool _isLandscape = false;
  bool _isPreviewExpanded = false;

  final double _canvasHeight = 3000.0;
  final double _gridSpacing = 120.0;
  final ScrollController _scrollController = ScrollController();

  Map<int, String> _linePreviews = {};
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _recognizer = DigitalInkRecognizer(languageCode: widget.languageCode);
    _checkModelStatus();
  }

  Future<void> _checkModelStatus() async {
    final isDownloaded = await _modelManager.isModelDownloaded(widget.languageCode);
    if (mounted) {
      setState(() => _isModelReady = isDownloaded);
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _recognizer.close();
    super.dispose();
  }

  void _toggleRotation() {
    setState(() {
      _isLandscape = !_isLandscape;
      if (_isLandscape) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    });
  }

  void _onUserStoppedScribbling() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _performRecognition(isPreview: true);
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
      Map<int, String> currentResults = {};
      for (var entry in lineInks.entries) {
        final candidates = await _recognizer.recognize(entry.value);
        if (candidates.isNotEmpty) currentResults[entry.key] = candidates.first.text;
      }
      setState(() {
        _linePreviews = currentResults;
        if (_linePreviews.isNotEmpty && !_isPreviewExpanded) {
          _isPreviewExpanded = true;
        }
      });
      if (!isPreview) {
        final sortedKeys = _linePreviews.keys.toList()..sort();
        String finalOutput = sortedKeys.map((i) => _linePreviews[i]).join('\n');
        Navigator.pop(context, finalOutput);
      }
    } catch (e) {
      debugPrint("Recognition Error: $e");
    } finally {
      if (!isPreview) setState(() => _isProcessing = false);
    }
  }

  void _erasePointsAt(Offset position) {
    const double eraseRadius = 30.0;
    bool changed = false;
    setState(() {
      for (var stroke in _ink.strokes) {
        int countBefore = stroke.points.length;
        stroke.points.removeWhere((p) => (Offset(p.x, p.y) - position).distance < eraseRadius);
        if (stroke.points.length != countBefore) changed = true;
      }
      _ink.strokes.removeWhere((s) => s.points.isEmpty);
    });
    if (changed) _onUserStoppedScribbling();
  }

  IconData _getActiveIcon() {
    if (_isReadOnlyMode) return Icons.pan_tool;
    if (_isEraserMode) return Icons.auto_fix_high;
    return Icons.edit;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isModelReady) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final sortedPreviewKeys = _linePreviews.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Structured Writing'),
        actions: [
          IconButton(
            icon: Icon(_isLandscape ? Icons.screen_lock_portrait : Icons.screen_lock_landscape),
            onPressed: _toggleRotation,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() {
              _ink.strokes.clear();
              _linePreviews.clear();
            }),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isMenuOpen) ...[
            FloatingActionButton.small(
              heroTag: 'opt_scroll',
              backgroundColor: Colors.white,
              child: const Icon(Icons.pan_tool, color: Colors.green),
              onPressed: () => setState(() {
                _isReadOnlyMode = true;
                _isEraserMode = false;
                _isMenuOpen = false;
              }),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.small(
              heroTag: 'opt_eraser',
              backgroundColor: Colors.white,
              child: const Icon(Icons.auto_fix_high, color: Colors.orange),
              onPressed: () => setState(() {
                _isReadOnlyMode = false;
                _isEraserMode = true;
                _isMenuOpen = false;
              }),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.small(
              heroTag: 'opt_pencil',
              backgroundColor: Colors.white,
              child: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => setState(() {
                _isReadOnlyMode = false;
                _isEraserMode = false;
                _isMenuOpen = false;
              }),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton(
            heroTag: 'main_fab',
            backgroundColor: _isMenuOpen ? Colors.grey : Colors.blueAccent,
            child: Icon(_isMenuOpen ? Icons.close : _getActiveIcon()),
            onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: _isReadOnlyMode
                      ? const AlwaysScrollableScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  child: GestureDetector(
                    onPanStart: _isReadOnlyMode ? null : (d) {
                      if (!_isEraserMode) {
                        _ink.strokes.add(Stroke());
                        _currentStrokePoints = [];
                      } else {
                        _erasePointsAt(d.localPosition);
                      }
                    },
                    onPanUpdate: _isReadOnlyMode ? null : (d) {
                      if (_isEraserMode) {
                        _erasePointsAt(d.localPosition);
                      } else {
                        setState(() {
                          _currentStrokePoints.add(StrokePoint(
                            x: d.localPosition.dx,
                            y: d.localPosition.dy,
                            t: DateTime.now().millisecondsSinceEpoch,
                          ));
                          _ink.strokes.last.points = List.from(_currentStrokePoints);
                        });
                      }
                    },
                    onPanEnd: _isReadOnlyMode ? null : (_) => _onUserStoppedScribbling(),
                    child: Container(
                      color: Colors.white,
                      width: double.infinity,
                      height: _canvasHeight,
                      child: CustomPaint(
                        painter: SignaturePainter(
                            ink: _ink,
                            gridSpacing: _gridSpacing
                        ),
                        size: Size(double.infinity, _canvasHeight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_linePreviews.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _isPreviewExpanded = !_isPreviewExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border(top: BorderSide(color: Colors.blue.shade100)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Preview",
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900
                          ),
                        ),
                        Icon(
                          _isPreviewExpanded ? Icons.expand_more : Icons.expand_less,
                          size: 18,
                          color: Colors.blue.shade900,
                        ),
                      ],
                    ),
                    if (_isPreviewExpanded) ...[
                      const Divider(height: 12),
                      ConstrainedBox(
                        // FIXED: Max height set to 120 as requested
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: ListView(
                          shrinkWrap: true,
                          children: sortedPreviewKeys.map((key) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              "Row ${key + 1}: ${_linePreviews[key]}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.blueGrey
                              ),
                            ),
                          )).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              // FIXED: Done button with 100 width
              child: SizedBox(
                width: 100,
                height: 45,
                child: FilledButton(
                  onPressed: _isProcessing ? null : () => _performRecognition(),
                  child: _isProcessing
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text("Done", style: TextStyle(fontSize: 14)),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}