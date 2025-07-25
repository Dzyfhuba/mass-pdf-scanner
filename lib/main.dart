import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mass_pdf_scanner/scanner.dart';

void main() {
  runApp(const PlaceholderApp());
}

class PlaceholderApp extends StatelessWidget {
  const PlaceholderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Placeholder App',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: const PlaceholderHomePage(title: 'Placeholder Home Page'),
    );
  }
}

class PlaceholderHomePage extends StatefulWidget {
  const PlaceholderHomePage({super.key, required this.title});

  final String title;

  @override
  State<PlaceholderHomePage> createState() => _PlaceholderHomePageState();
}

class _PlaceholderHomePageState extends State<PlaceholderHomePage> {
  TextEditingController _chooseDirectoryController = TextEditingController();

  void _chooseDirectory() async {
    // TEMPORARY: pilih file dulu sebagai test OCR
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      File file = File(result.files.single.path!);

      debugPrint(file.path);
      setState(() {
        _chooseDirectoryController.text = file.path;
      });
    } else {
      // User canceled the picker
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _chooseDirectoryController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Pilih File atau Folder',
                      suffixIcon: _chooseDirectoryController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.clear),
                              onPressed: () => _chooseDirectoryController.clear(), // This will be set later
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                ElevatedButton(
                  style: ButtonStyle(backgroundColor: WidgetStateProperty.all<Color>(Colors.blue)),
                  onPressed: () {
                    _chooseDirectory();
                  },
                  child: const Text('Browse'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    if (_chooseDirectoryController.text.isEmpty) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Pilih file atau folder terlebih dahulu')));
                    } else {
                      await Scanner().scan(_chooseDirectoryController.text);
                    }
                  },
                  child: const Text('Scan'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
