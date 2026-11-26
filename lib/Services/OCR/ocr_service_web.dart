// Web stub for OcrService (OCR not available on web).
import 'package:flutter/material.dart' show Rect;

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  Future<String> prepareImage(String sourcePath) async => sourcePath;
  Future<String> recognizeText(String imagePath) async => '';
  Future<String> recognizeRegion(String sourcePath, Rect region) async => '';

  static Map<String, String> parseFields(String text) => {
        'name': '',
        'woGekauft': '',
        'preis': '',
        'hersteller': '',
        'kaufDatum': '',
        'kategorie': '',
      };

  static List<Map<String, String>> extractCandidates(String text) => [];

  void dispose() {}
}