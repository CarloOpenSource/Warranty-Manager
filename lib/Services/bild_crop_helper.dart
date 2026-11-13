import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Stellt einen einfachen, eigengeschriebenen Bild-Zuschneide-Editor bereit.
///
/// Da die App kein externes Native-Plugin für das Zuschneiden nutzt, wird
/// der Schnitt manuell als Rechteck (in Pixelkoordinaten des Bildes)
/// ermittelt und mit dem Paket `image` (bereits als transitive
/// Abhängigkeit vorhanden) auf die Datei angewandt.
class BildCropHelper {
  BildCropHelper();

  /// Führt einen Zuschchnitt auf der Datei [quelle] durch.
  ///
  /// [crop] gibt das Rechteck an, das im Koordinatensystem der
  /// [quelle] liegt. Die Ausgabe wird als neue Datei im App-
  /// Dokumentenordner gespeichert und der Pfad zurückgeliefert.
  Future<String> cropFile({
    required String quelle,
    required Rect crop,
    int? maxWidth,
    int? maxHeight,
  }) async {
    final File quellDatei = File(quelle);
    if (!await quellDatei.exists()) {
      throw FileSystemException('Quelldatei existiert nicht', quelle);
    }

    final Uint8List bytes = await quellDatei.readAsBytes();
    final img.Image? original = img.decodeImage(bytes);
    if (original == null) {
      throw FileSystemException('Bild nicht decodierbar', quelle);
    }

    // Koordinaten auf das Bild clampen.
    int x = crop.left.floor().clamp(0, original.width);
    int y = crop.top.floor().clamp(0, original.height);
    int w = crop.width.floor().clamp(1, original.width - x);
    int h = crop.height.floor().clamp(1, original.height - y);

    final img.Image clipped = img.copyCrop(original, x: x, y: y, width: w, height: h);

    // Optional auf eine maximale Größe skaliieren (spart Speicher).
    img.Image result = clipped;
    if (maxWidth != null && result.width > maxWidth) {
      result = img.copyResize(result, width: maxWidth);
    }
    if (maxHeight != null && result.height > maxHeight) {
      result = img.copyResize(result, height: maxHeight);
    }

    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String dateiName =
        'crop_${DateTime.now().millisecondsSinceEpoch}_${path.basename(quelle)}';
    final String zielPfad = path.join(appDocDir.path, dateiName);
    final File zielDatei = File(zielPfad);

    final Uint8List outBytes;
    final String ext = path.extension(quelle).toLowerCase();
    if (ext == '.png' || ext == '') {
      outBytes = Uint8List.fromList(img.encodePng(result));
    } else {
      outBytes = Uint8List.fromList(img.encodeJpg(result, quality: 90));
    }

    await zielDatei.writeAsBytes(outBytes);
    return zielPfad;
  }

  /// Gibt die natürliche Bildgröße als [Size] zurück (null bei Fehler).
  Future<Size?> getFileSize(String pfad) async {
    try {
      final File datei = File(pfad);
      if (!await datei.exists()) return null;
      final Uint8List bytes = await datei.readAsBytes();
      final img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;
      return Size(image.width.toDouble(), image.height.toDouble());
    } catch (_) {
      return null;
    }
  }
}