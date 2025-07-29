import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mass_pdf_scanner/helpers.dart';
import 'package:mass_pdf_scanner/ocr_result.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:collection/collection.dart';

class Scanner {
  Future<void> scan(String pdfPath) async {
    final pdf = await PdfDocument.openFile(pdfPath);
    debugPrint('📄 Total pages: ${pdf.pages.length}');

    if (pdf.pages.isEmpty) return;

    final page = await pdf.pages.first.render();
    final image = await page?.createImage();
    if (image == null) {
      debugPrint('❌ Failed to render PDF page to image.');
      return;
    }

    final pngBytes = await _imageToBytes(image);
    if (pngBytes == null) return;

    final preprocessedBytes = _preprocessImage(pngBytes);
    final imagePath = await _saveImage(preprocessedBytes);

    final result = await _extractTextWithCoordinates(imagePath);
    if (result != null) {
      debugPrint('✅ Extracted label: ${result['label']}');
      debugPrint('✅ Extracted value: ${result['value']}');
    }
  }

  Future<Uint8List?> _imageToBytes(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Uint8List _preprocessImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    final grayscale = img.grayscale(decoded);
    final contrast = img.adjustColor(grayscale, contrast: 1.5);
    final inverted = img.invert(contrast);

    return img.encodePng(inverted);
  }

  Future<String> _saveImage(Uint8List bytes) async {
    final dir = Directory('${Directory.current.path}$pathSeparator.tmp');
    if (!await dir.exists()) await dir.create(recursive: true);

    final path = '${dir.path}$pathSeparator${DateTime.now().millisecondsSinceEpoch}.png';
    await File(path).writeAsBytes(bytes);

    debugPrint('💾 Saved image to: $path');
    return path;
  }

  Future<Map<String, dynamic>?> _extractTextWithCoordinates(String imagePath) async {
    final tesseractPath =
        '${Directory.current.path}${pathSeparator}bin${pathSeparator}tesseract5${pathSeparator}tesseract.exe';

    final resultScan = await Process.run(tesseractPath, [imagePath, 'stdout', '--psm', '3', '-l', 'ind', 'tsv']);

    if (resultScan.exitCode != 0) {
      debugPrint('❌ Tesseract failed: ${resultScan.stderr}');
      return null;
    }

    final output = resultScan.stdout.toString();
    final lines = output.split('\n');
    if (lines.length <= 1) return null;

    final ocrList = <OCRResult>[];
    final header = lines.first.split('\t');
    if (!(header.length >= 12 && header[0] == 'level')) {
      debugPrint('❌ Not a valid TSV output');
      return null;
    }

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final parts = line.split('\t');
      if (parts.length < 12 || parts[11].trim().isEmpty) continue;

      final text = parts[11].trim();
      final left = int.tryParse(parts[6]) ?? 0;
      final top = int.tryParse(parts[7]) ?? 0;
      final width = int.tryParse(parts[8]) ?? 0;
      final height = int.tryParse(parts[9]) ?? 0;

      final ocr = OCRResult(
        text: text,
        left: left,
        top: top,
        width: width,
        height: height,
        right: left + width,
        bottom: top + height,
        centerX: left + width / 2,
        centerY: top + height / 2,
      );
      debugPrint('text[$i]: $ocr');
      ocrList.add(ocr);
    }

    // X.1. Pekerjaan Yang Dilakukan
    final labelBox1 = _findMergedLabelBoxFuzzyFlexible('Pekerjaan Yang Dilakukan', ocrList);
    if (labelBox1 == null) {
      debugPrint('⚠️ Label "Pekerjaan Yang Dilakukan" not found.');
      return null;
    }
    final resultText1 = _findTextRightOfBoxSmart(labelBox1, ocrList);

    // X.2. No JSA
    final labelBox2 = _findMergedLabelBoxFuzzy('Lokasi', ocrList);
    if (labelBox2 == null) {
      debugPrint('⚠️ Label "Lokasi" not found.');
      return null;
    }
    final resultText2 = _findTextRightOfBoxSmart(labelBox2, ocrList);

    final finalResult = {
      'pekerjaan_yang_dilakukan': {"key": labelBox1, 'value': resultText1},
      'no_jsa': {"key": labelBox2, 'value': resultText2},
    };

    debugPrint('finalResult: ${finalResult.toString()}');

    return {};
  }

  OCRResult? _findMergedLabelBox(String phrase, List<OCRResult> list) {
    final words = phrase.toLowerCase().split(' ');
    for (var i = 0; i <= list.length - words.length; i++) {
      final candidate = list.sublist(i, i + words.length);
      final textMatch = candidate.map((e) => e.text.toLowerCase()).join(' ');
      if (textMatch == phrase.toLowerCase()) {
        final merged = candidate.reduce((a, b) => a.merge(b));
        return merged;
      }
    }
    return null;
  }

  Map<String, dynamic> _findTextRightOfBox(OCRResult labelBox, List<OCRResult> ocrList) {
    const rowThreshold = 15;

    final rightSideTexts =
        ocrList.where((e) => (e.centerY - labelBox.centerY).abs() < rowThreshold && e.left > labelBox.right).toList()
          ..sort((a, b) => a.left.compareTo(b.left));

    if (rightSideTexts.isEmpty) {
      debugPrint('⚠️ No text found to the right of label: "${labelBox.text}"');
      return {'text': '', 'box': labelBox};
    }

    final mergedBox = rightSideTexts.reduce((a, b) => a.merge(b));
    final combinedText = rightSideTexts.map((e) => e.text).join(' ').trim();

    debugPrint('✅ Right side of "${labelBox.text}": $combinedText');
    return {'text': combinedText, 'box': mergedBox};
  }

  int _levenshtein(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;

    final dp = List.generate(len1 + 1, (_) => List<int>.filled(len2 + 1, 0));

    for (int i = 0; i <= len1; i++) dp[i][0] = i;
    for (int j = 0; j <= len2; j++) dp[0][j] = j;

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        dp[i][j] = [dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + cost].reduce(min);
      }
    }

    return dp[len1][len2];
  }

  OCRResult? _findMergedLabelBoxFuzzy(String expectedPhrase, List<OCRResult> ocrList, {int maxDistance = 1}) {
    final words = expectedPhrase.toLowerCase().split(' ');
    final int wordCount = words.length;

    for (int i = 0; i <= ocrList.length - wordCount; i++) {
      final candidates = ocrList.sublist(i, i + wordCount);
      final phraseCandidate = candidates.map((e) => e.text.toLowerCase()).join(' ');

      final distance = _levenshtein(phraseCandidate, expectedPhrase.toLowerCase());

      if (distance <= maxDistance) {
        final mergedBox = candidates.reduce((a, b) => a.merge(b));
        debugPrint('🧠 Fuzzy matched: "$phraseCandidate" (dist=$distance) → "$expectedPhrase"');
        return OCRResult(
          text: expectedPhrase,
          left: mergedBox.left,
          top: mergedBox.top,
          width: mergedBox.width,
          height: mergedBox.height,
          right: mergedBox.right,
          bottom: mergedBox.bottom,
          centerX: mergedBox.centerX,
          centerY: mergedBox.centerY,
        );
      }
    }

    return null;
  }

  OCRResult? _findMergedLabelBoxFuzzyFlexible(
    String expectedPhrase,
    List<OCRResult> ocrList, {
    int maxDistance = 1,
    int maxPhraseLength = 5,
  }) {
    final expectedLower = expectedPhrase.toLowerCase();

    for (int len = 1; len <= maxPhraseLength; len++) {
      for (int i = 0; i <= ocrList.length - len; i++) {
        final segment = ocrList.sublist(i, i + len);
        final phraseCandidate = segment.map((e) => e.text.toLowerCase()).join(' ');
        final distance = _levenshtein(phraseCandidate, expectedLower);

        if (distance <= maxDistance) {
          final merged = segment.reduce((a, b) => a.merge(b));
          debugPrint('🧠 Fuzzy matched: "$phraseCandidate" (dist=$distance) → "$expectedPhrase"');
          return merged;
        }
      }
    }

    return null;
  }

  Map<String, dynamic> _findTextRightOfBoxSmart(OCRResult labelBox, List<OCRResult> ocrList) {
    const rowThreshold = 20;
    const minTextLength = 2;

    final rightTexts =
        ocrList
            .where(
              (e) =>
                  (e.centerY - labelBox.centerY).abs() < rowThreshold &&
                  e.left > labelBox.right &&
                  e.text.trim().length >= minTextLength,
            )
            .toList()
          ..sort((a, b) => a.left.compareTo(b.left));

    if (rightTexts.isEmpty) {
      debugPrint('⚠️ No suitable right-side text found for "${labelBox.text}"');
      return {'text': '', 'box': labelBox};
    }

    final text = rightTexts.map((e) => e.text).join(' ').trim();
    final box = rightTexts.reduce((a, b) => a.merge(b));

    debugPrint('✅ Smart right of "${labelBox.text}": $text');
    return {'text': text, 'box': box};
  }
}
