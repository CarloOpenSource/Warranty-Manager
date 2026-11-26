import 'dart:io';
import 'package:flutter/material.dart' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Offline OCR Service (on-device, via Google ML Kit Text Recognition).
/// No network calls are made.
class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  TextRecognizer? _recognizer;

  TextRecognizer get _textRecognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  /// Preprocesses an image to improve OCR accuracy:
  /// grayscale, contrast boost, mild sharpen. Returns path to prepared file.
  Future<String> prepareImage(String sourcePath) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return sourcePath;

      // Upscale small images
      img.Image work = decoded;
      if (work.width < 1000) {
        final scale = 1000 / work.width;
        work = img.copyResize(work,
            width: (work.width * scale).round(),
            height: (work.height * scale).round(),
            interpolation: img.Interpolation.cubic);
      }

      // Grayscale
      work = img.grayscale(work);
      // Contrast
      work = img.adjustColor(work, contrast: 1.4, brightness: 1.05);
      // Sharpen
      work = img.convolution(work, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

      final tempDir = await getTemporaryDirectory();
      final outPath = path.join(tempDir.path,
          'ocr_prep_${DateTime.now().millisecondsSinceEpoch}.png');
      final png = img.encodePng(work);
      await File(outPath).writeAsBytes(png);
      return outPath;
    } catch (_) {
      return sourcePath;
    }
  }

  /// Runs OCR on the given image path and returns the recognized text.
  /// Tries both a preprocessed variant and the original image and keeps the
  /// result with more recognized text, which improves robustness on receipts
  /// with unusual lighting or skew.
  Future<String> recognizeText(String imagePath) async {
    final prepared = await prepareImage(imagePath);
    String best = '';
    for (final candidate in <String>[prepared, imagePath]) {
      if (candidate.isEmpty) continue;
      try {
        final inputImage = InputImage.fromFilePath(candidate);
        final result = await _textRecognizer.processImage(inputImage);
        if (result.text.trim().length > best.trim().length) {
          best = result.text;
        }
      } catch (_) {}
    }
    return best;
  }

  /// Crops a region from [sourcePath] given normalized rect (0..1) and runs OCR.
  Future<String> recognizeRegion(String sourcePath, Rect region) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return await recognizeText(sourcePath);

      final x = (region.left * decoded.width).round().clamp(0, decoded.width - 1);
      final y = (region.top * decoded.height).round().clamp(0, decoded.height - 1);
      final w = (region.width * decoded.width).round().clamp(1, decoded.width - x);
      final h = (region.height * decoded.height).round().clamp(1, decoded.height - y);

      final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      final tempDir = await getTemporaryDirectory();
      final outPath = path.join(tempDir.path,
          'ocr_crop_${DateTime.now().millisecondsSinceEpoch}.png');
      await File(outPath).writeAsBytes(img.encodePng(cropped));
      return await recognizeText(outPath);
    } catch (_) {
      return await recognizeText(sourcePath);
    }
  }

  /// Parses recognized text into warranty-relevant fields.
  /// Returns a map with keys: name, woGekauft, preis, hersteller, kaufDatum.
  static Map<String, String> parseFields(String text) {
    final result = <String, String>{
      'name': '',
      'woGekauft': '',
      'preis': '',
      'hersteller': '',
      'kaufDatum': '',
      'kategorie': '',
    };

    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // Store / seller: look for line containing typical store keywords or first line
    for (final line in lines.take(6)) {
      final lower = line.toLowerCase();
      if (lower.contains('gmbh') ||
          lower.contains('ag') ||
          lower.contains('ltd') ||
          lower.contains('inc') ||
          lower.contains('llc') ||
          lower.contains('markt') ||
          lower.contains('market') ||
          lower.contains('supermarket') ||
          lower.contains('store') ||
          lower.contains('shop') ||
          lower.contains('magasin') ||
          lower.contains('tienda') ||
          lower.contains('boutique') ||
          lower.contains('filiale')) {
        String storeVal = line;
        final ci = line.indexOf(RegExp(r'[:：]'));
        if (ci != -1) storeVal = line.substring(ci + 1);
        result['woGekauft'] = _cleanStore(storeVal);
        break;
      }
    }
    if (result['woGekauft']!.isEmpty && lines.isNotEmpty) {
      // fallback: first non-numeric line
      for (final line in lines.take(6)) {
        if (!RegExp(r'^\d').hasMatch(line) && line.length > 3) {
          String storeVal = line;
          final ci = line.indexOf(RegExp(r'[:：]'));
          if (ci != -1) storeVal = line.substring(ci + 1);
          result['woGekauft'] = _cleanStore(storeVal);
          break;
        }
      }
    }

    // Manufacturer
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('hersteller') ||
          lower.contains('manufacturer') ||
          lower.contains('fabricant') ||
          lower.contains('fabricante') ||
          lower.contains('marke') ||
          lower.contains('brand') ||
          lower.contains('marca') ||
          lower.contains('maker') ||
          lower.contains('herst')) {
        final parts = line.split(RegExp(r'[:：]'));
        if (parts.length > 1 && parts.last.trim().isNotEmpty) {
          result['hersteller'] = parts.last.trim();
        } else {
          // next line
          final idx = lines.indexOf(line);
          if (idx >= 0 && idx + 1 < lines.length) {
            result['hersteller'] = lines[idx + 1].trim();
          }
        }
        break;
      }
    }

    // Dates: prefer a line that explicitly mentions a date/purchase, otherwise
    // take the first date found (usually the purchase date on receipts).
    final dateRegex = RegExp(r'(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})');
    String? chosenDate;
    for (final line in lines) {
      final lower = line.toLowerCase();
      final isDateLine = lower.contains('datum') ||
          lower.contains('date') ||
          lower.contains('kauf') ||
          lower.contains('bought') ||
          lower.contains('purchase');
      final m = dateRegex.firstMatch(line);
      if (m != null) {
        final d = m.group(1)!.padLeft(2, '0');
        final mo = m.group(2)!.padLeft(2, '0');
        var y = m.group(3)!;
        if (y.length == 2) y = '20$y';
        final candidate = '$d.$mo.$y';
        if (isDateLine) {
          chosenDate = candidate;
          break;
        }
        chosenDate ??= candidate;
      }
    }
    if (chosenDate != null) {
      result['kaufDatum'] = chosenDate;
    }

    // Price: find decimal number
    final priceRegex = RegExp(r'(\d{1,6}[.,]\d{2})');
    final prices = <String>[];
    for (final line in lines) {
      for (final m in priceRegex.allMatches(line)) {
        prices.add(m.group(1)!.replaceAll(',', '.'));
      }
    }
    if (prices.isNotEmpty) {
      // Prefer the largest value found (usually the total at the bottom of
      // the receipt), falling back to the last one.
      double best = 0;
      String bestStr = prices.last;
      for (final p in prices) {
        final v = double.tryParse(p) ?? 0;
        if (v >= best) {
          best = v;
          bestStr = p;
        }
      }
      result['preis'] = bestStr;
    }

    // Product name: line that contains a price, text before price
    bool isLabelLine(String s) {
      final l = s.toLowerCase();
      return l.contains('date') || l.contains('datum') || l.contains('price') ||
          l.contains('preis') || l.contains('bought') || l.contains('gekauft') ||
          l.contains('store') || l.contains('kauf') || l.contains('hersteller') ||
          l.contains('manufacturer') || l.contains('fabricant') ||
          l.contains('total') || l.contains('summe') || l.contains('mwst') ||
          l.contains('tax') || l.contains('receipt') || l.contains('kassenbon');
    }

    for (final line in lines) {
      final m = priceRegex.firstMatch(line);
      if (m != null) {
        var namePart = line.substring(0, m.start).trim();
        if (namePart.isEmpty) {
          final afterPrice = line.substring(m.end).trim();
          if (afterPrice.length > 2) namePart = afterPrice;
        }
        namePart = namePart.replaceFirst(
            RegExp(r'^(name|produkt|product|artikel|item|bezeichnung|beschreibung)\s*[:：]?\s*',
                caseSensitive: false),
            '');
        final ci = namePart.indexOf(RegExp(r'[:：]'));
        if (ci != -1 && ci < namePart.length - 1) {
          final after = namePart.substring(ci + 1).trim();
          if (after.isNotEmpty) namePart = after;
        }
        if (namePart.length > 2 && !isLabelLine(namePart)) {
          result['name'] = _cleanName(namePart);
          break;
        }
      }
    }
    if (result['name']!.isEmpty) {
      // fallback: best non-label line (most letters), preferring top
      String? best;
      int bestScore = 0;
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (line.length < 3) continue;
        if (dateRegex.hasMatch(line)) continue;
        if (isLabelLine(lower)) continue;
        final letters = line.replaceAll(RegExp(r'[^a-zA-ZäöüÄÖÜß]'), '').length;
        if (letters > bestScore) {
          bestScore = letters;
          best = line;
        }
      }
      if (best != null) {
        result['name'] = _cleanName(best);
      }
    }
    // last resort: first non-empty line that is not a date
    if (result['name']!.isEmpty) {
      for (final line in lines) {
        if (line.trim().length > 2 && !dateRegex.hasMatch(line)) {
          result['name'] = _cleanName(line);
          break;
        }
      }
    }

    // Category detection
    final combined = ('${result['name']} $text').toLowerCase();
    const categoryMap = <String, List<String>>{
      'electronics': [
        'phone', 'smartphone', 'laptop', 'notebook', 'tv', 'fernseher',
        'computer', 'tablet', 'kopfhörer', 'headphone', 'kamera', 'camera',
        'elektronik', 'electronic', 'monitor', 'drucker', 'printer'
      ],
      'furniture': [
        'stuhl', 'chair', 'tisch', 'table', 'schrank', 'cabinet', 'sofa',
        'bett', 'bed', 'möbel', 'furniture', 'regal', 'shelf'
      ],
      'household': [
        'staubsauger', 'vacuum', 'mixer', 'toaster', 'kühlschrank', 'fridge',
        'waschmaschine', 'washer', 'haushalt', 'household', 'küche', 'kitchen',
        'bügeleisen', 'iron'
      ],
    };
    for (final entry in categoryMap.entries) {
      if (entry.value.any((k) => combined.contains(k))) {
        result['kategorie'] = entry.key;
        break;
      }
    }

    return result;
  }

  /// Extracts product candidates (name + price) from receipt text.
  static List<Map<String, String>> extractCandidates(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final priceRegex = RegExp(r'(\d{1,6}[.,]\d{2})');
    final candidates = <Map<String, String>>[];
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('total') || lower.contains('summe') || lower.contains('mwst') ||
          lower.contains('tax') || lower.contains('subtotal')) {
        continue;
      }
      final m = priceRegex.firstMatch(line);
      if (m != null) {
        var namePart = line.substring(0, m.start).trim();
        namePart = namePart.replaceFirst(
            RegExp(r'^(name|produkt|product|artikel|item|bezeichnung)\s*[:：]?\s*',
                caseSensitive: false),
            '');
        final price = m.group(1)!.replaceAll(',', '.');
        if (namePart.length > 1) {
          candidates.add({
            'name': _cleanName(namePart),
            'preis': price,
          });
        }
      }
    }
    if (candidates.isEmpty) {
      candidates.add({'name': '', 'preis': ''});
    }
    return candidates;
  }

  static String _cleanStore(String s) {
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 20) s = s.substring(0, 20);
    return s.toUpperCase();
  }

  static String _cleanName(String s) {
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // remove leading numbers/bullets
    s = s.replaceFirst(RegExp(r'^[\d.\-•\s]+'), '');
    if (s.length > 40) s = s.substring(0, 40);
    return s;
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}