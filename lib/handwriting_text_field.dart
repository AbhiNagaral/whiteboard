import 'package:flutter/material.dart';
import 'digital_ink_full_screen.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String languageCode;
  final bool showHandwritingIcon;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.languageCode,
    this.labelText = 'Write notes',
    this.showHandwritingIcon = false,
  });

  Future<void> _openDrawingBoard(BuildContext context) async {
    final String? recognizedText = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => DigitalInkFullScreen(languageCode: languageCode),
      ),
    );

    if (recognizedText != null) {
      controller.text = recognizedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: null,
      decoration: InputDecoration(
        labelText: labelText,
        border: const OutlineInputBorder(),
        suffixIcon: showHandwritingIcon
            ? IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _openDrawingBoard(context),
        )
            : null,
      ),
    );
  }
}