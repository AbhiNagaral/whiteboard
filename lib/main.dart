import 'package:flutter/material.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';
import 'handwriting_text_field.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HandwritingApp());
}

class HandwritingApp extends StatelessWidget {
  const HandwritingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const FormScreen(),
    );
  }
}

class FormScreen extends StatefulWidget {
  const FormScreen({super.key});

  @override
  State<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<FormScreen> {
  final TextEditingController _textController = TextEditingController();
  final DigitalInkRecognizerModelManager _modelManager = DigitalInkRecognizerModelManager();

  String _selectedLang = 'en-US';
  Map<String, bool> _downloadedModels = {};

  final List<Map<String, String>> _languages = [
    {'code': 'en-US', 'label': 'English'},
    {'code': 'hi', 'label': 'Hindi'},
    {'code': 'mr', 'label': 'Marathi'},
  ];

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  Future<void> _refreshModelStatus() async {
    for (var lang in _languages) {
      final isDownloaded = await _modelManager.isModelDownloaded(lang['code']!);
      setState(() => _downloadedModels[lang['code']!] = isDownloaded);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isCurrentModelReady = _downloadedModels[_selectedLang] ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Patient Records')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _selectedLang,
              decoration: const InputDecoration(labelText: "Language"),
              items: _languages.map((l) => DropdownMenuItem(value: l['code'], child: Text(l['label']!))).toList(),
              onChanged: (v) => setState(() => _selectedLang = v!),
            ),
            const SizedBox(height: 16),
            if (!isCurrentModelReady)
              ElevatedButton.icon(
                onPressed: () async {
                  await _modelManager.downloadModel(_selectedLang);
                  _refreshModelStatus();
                },
                icon: const Icon(Icons.download),
                label: const Text("Download Language Pack"),
              )
            else
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text("Model ready for use", style: TextStyle(color: Colors.green)),
                ],
              ),
            const SizedBox(height: 32),
            CustomTextField(
              controller: _textController,
              languageCode: _selectedLang,
              labelText: 'Clinical Observations',
              showHandwritingIcon: isCurrentModelReady,
            ),
          ],
        ),
      ),
    );
  }
}