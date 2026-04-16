import 'package:flutter/material.dart' hide Ink;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

class SignaturePainter extends CustomPainter {
  final Ink ink;
  final double gridSpacing;
  final Map<int, String> linePreviews;
  final double horizontalOffset;

  SignaturePainter({
    required this.ink,
    this.gridSpacing = 80.0,
    this.linePreviews = const {},
    this.horizontalOffset = 0.0, // Default to 0
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaint = Paint()
      ..color = Colors.blue.withOpacity(0.2)
      ..strokeWidth = 1.0;

    for (double y = gridSpacing; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

      int lineIndex = (y / gridSpacing).floor() - 1;

      if (linePreviews.containsKey(lineIndex)) {
        _drawTextPreview(canvas, linePreviews[lineIndex]!, y - gridSpacing);
      }
    }

    final Paint strokePaint = Paint()
      ..color = Colors.black87
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.0;

    for (final stroke in ink.strokes) {
      if (stroke.points.isEmpty) continue;
      for (int i = 0; i < stroke.points.length - 1; i++) {
        final p1 = stroke.points[i];
        final p2 = stroke.points[i + 1];
        canvas.drawLine(Offset(p1.x, p1.y), Offset(p2.x, p2.y), strokePaint);
      }
    }
  }

  void _drawTextPreview(Canvas canvas, String text, double yOffset) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.blue.withOpacity(0.5),
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, Offset(horizontalOffset + 20, yOffset));
  }

  @override
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}