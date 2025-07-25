import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mass_pdf_scanner/helpers.dart';
import 'package:mass_pdf_scanner/ocr_result.dart';
import 'package:pdfrx/pdfrx.dart';

class Scanner {
  Future<void> scan(String pdfPath) async {
    final pdf = await PdfDocument.openFile(pdfPath);
    debugPrint('pages length: ${pdf.pages.length}');

    // for (var i = 0; i < pdf.pages.length; i++) {
    for (var i = 0; i < 1; i++) {
      var page = await pdf.pages[0].render();
      debugPrint('page width: ${page?.width ?? 0}, height: ${page?.height ?? 0}');
      // store the page as an image to where fileDir points
      var image = await page?.createImage();
      debugPrint('image width: ${image?.width ?? 0}, height: ${image?.height ?? 0}');

      final byteData = await image?.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('Failed to convert image to byte data');
        return;
      }

      // pdf berhasil jadi gambar
      final pngBytes = byteData.buffer.asUint8List();

      // Save PNG image to .tmp/
      final outputPath =
          '${Directory.current.path}$pathSeparator.tmp$pathSeparator${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(outputPath);
      await file.writeAsBytes(pngBytes);
      debugPrint('Saved page image to: $outputPath');

      final ocrResults = await extractTextWithCoordinates(outputPath);
    }
  }

  Future<List<OCRResult>> extractTextWithCoordinates(String imagePath) async {
    final tesseractPath =
        '${Directory.current.path}${pathSeparator}bin${pathSeparator}tesseract${pathSeparator}tesseract.exe';
    final result = await Process.run(tesseractPath, [imagePath, 'stdout', '--psm', '3', 'tsv']);

    final List<OCRResult> results = [];

    final lines = result.stdout.toString().split('\n');
    for (final line in lines.skip(1)) {
      final parts = line.split('\t');
      if (parts.length >= 12 && parts[11].trim().isNotEmpty) {
        final text = parts[11].trim();
        final left = int.tryParse(parts[6]) ?? 0;
        final top = int.tryParse(parts[7]) ?? 0;
        final width = int.tryParse(parts[8]) ?? 0;
        final height = int.tryParse(parts[9]) ?? 0;

        final centerX = left + width / 2;
        final centerY = top + height / 2;

        debugPrint('Text: $text, Center X: $centerX, Center Y: $centerY');
        results.add(OCRResult(text, centerX, centerY));
      }
    }

    return results;
  }
}
