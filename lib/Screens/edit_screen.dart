import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../Services/settings_provider.dart';
import '../Services/bild_crop_helper.dart';
import 'package:garantiemanager/Translations/translations_de.dart';
import 'package:garantiemanager/Translations/translations_en.dart';
import 'package:garantiemanager/Translations/translations_fr.dart';
import 'package:garantiemanager/Translations/translations_es.dart';

/// Vollbild-Bild-Editor mit Zuschneide-Funktion ganz links.
///
/// Diese Screen ermöglicht es Benutzern, auf Fotos zuzugreifen und
/// sie zu bearbeiten, was für normale Nutzer verfügbar ist.
class EditScreen extends StatefulWidget {
  final String imageDataPath;
  final String originalPath;

  const EditScreen({
    super.key,
    required this.imageDataPath,
    required this.originalPath,
  });

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> with WidgetsBindingObserver {
  late img.Image _originalImage;
  img.Image? _processedImage;
  final BildCropHelper _cropHelper = BildCropHelper();
  bool _istDunkel = true;

  // Crop-Bereich (in Bildschirm-Koordinaten)
  Rect _cropRect = Rect.zero;
  bool _isDragging = false;
  bool _croppingInProgress = false;

  // Bildbearbeitungswerte
  double _brightness = 1.0; // 1.0 = normal, 0.0 = schwarz, >1 = heller
  double _contrast = 1.0;   // 1.0 = normal, 0.0 = grau, >1 = mehr Kontrast
  double _saturation = 1.0; // 1.0 = normal, 0.0 = Graustufen, >1 = mehr Sättigung
  int _rotation = 0; // 0, 90, -90 (Drehung aus dem Bottom-Sheet)

  // Ladezustand
  bool _isLoading = true;

  // Display-Parameter (für schnelle Anzeige)
  Uint8List? _displayBytes;
  int _displayWidth = 0;
  int _displayHeight = 0;

  static const int _maxDisplayDimension = 1024; // max. Kantenlänge für Anzeige

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadImage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newBrightness = Theme.of(context).brightness == Brightness.dark;
    if (newBrightness != _istDunkel) {
      setState(() {
        _istDunkel = newBrightness;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lädt das Bild und skaliert es aggressiv für die Anzeige herunter.
  /// Das verhindert "App friert ein" bei großen Fotos (z. B. 12 MP).
  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('EditScreen._loadImage: Pfad = ${widget.imageDataPath}');
      final file = File(widget.imageDataPath);
      if (!await file.exists()) {
        debugPrint('EditScreen._loadImage: Datei existiert NICHT');
        throw FileSystemException('Datei nicht gefunden', widget.imageDataPath);
      }
      final bytes = await file.readAsBytes();
      debugPrint('EditScreen._loadImage: Bytes gelesen: ${bytes.length}');

      // 1. Bild dekodieren (gibt volle Auflösung)
      _originalImage = img.decodeImage(bytes)!;
      debugPrint('EditScreen._loadImage: Original: ${_originalImage.width}x${_originalImage.height}');

      // 2. Für Anzeige herunterskalieren (max 1024px Kantenlänge)
      img.Image displayImage = _originalImage;
      if (_originalImage.width > _maxDisplayDimension || _originalImage.height > _maxDisplayDimension) {
        final scale = math.min(
          _maxDisplayDimension / _originalImage.width,
          _maxDisplayDimension / _originalImage.height,
        );
        displayImage = img.copyResize(_originalImage,
          width: (_originalImage.width * scale).round(),
          height: (_originalImage.height * scale).round(),
        );
        debugPrint('EditScreen._loadImage: Skaliert auf: ${displayImage.width}x${displayImage.height}');
      }

      // 3. Initial verarbeiten (Rotation + Helligkeit/Kontrast/Sättigung)
      _processedImage = _applySettingsToImage(displayImage);

      // 4. Als JPEG für schnelle Anzeige kodieren
      _displayBytes = Uint8List.fromList(img.encodeJpg(_processedImage!, quality: 85));
      _displayWidth = _processedImage!.width;
      _displayHeight = _processedImage!.height;

      _setCropRectForDisplay();
      debugPrint('EditScreen._loadImage: Fertig');
    } catch (e, stack) {
      debugPrint('EditScreen._loadImage FEHLER: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Laden des Bildes: $e')),
        );
        Navigator.pop(context);
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Wendet Helligkeit, Kontrast, Sättigung und Rotation auf ein Bild an.
  /// Wird synchron auf dem Main-Thread aufgerufen, aber auf das *kleine* Display-Bild.
  img.Image _applySettingsToImage(img.Image source) {
    img.Image image = img.Image.from(source);

    // Drehung anwenden
    if (_rotation == 90) {
      image = img.copyRotate(image, angle: 90);
    } else if (_rotation == -90) {
      image = img.copyRotate(image, angle: -90);
    }

    // Helligkeit, Kontrast, Sättigung anwenden
    image = img.adjustColor(
      image,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
    );

    return image;
  }

  /// Berechnet den Crop-Bereich (in Bildschirm-Koordinaten) für das geladene Bild.
  void _setCropRectForDisplay() {
    if (_displayWidth == 0 || _displayHeight == 0) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final scale = math.min(screenWidth / _displayWidth, screenHeight / _displayHeight);
    final scaledWidth = _displayWidth * scale;
    final scaledHeight = _displayHeight * scale;
    _cropRect = Rect.fromLTWH(
      (screenWidth - scaledWidth) / 2,
      (screenHeight - scaledHeight) / 2,
      scaledWidth,
      scaledHeight,
    );
  }

  /// Aktualisiert die Anzeige nach Änderung von Helligkeit/Kontrast/Sättigung/Rotation.
  /// Arbeitet auf dem *kleinen* Display-Bild -> sehr schnell, blockiert nicht.
  Future<void> _applyImageSettings() async {
    try {
      // Skalieren auf Display-Größe
      img.Image displayImage = _originalImage;
      if (_originalImage.width > _maxDisplayDimension || _originalImage.height > _maxDisplayDimension) {
        final scale = math.min(
          _maxDisplayDimension / _originalImage.width,
          _maxDisplayDimension / _originalImage.height,
        );
        displayImage = img.copyResize(_originalImage,
          width: (_originalImage.width * scale).round(),
          height: (_originalImage.height * scale).round(),
        );
      }

      // Einstellungen anwenden
      _processedImage = _applySettingsToImage(displayImage);

      // Neu kodieren
      _displayBytes = Uint8List.fromList(img.encodeJpg(_processedImage!, quality: 85));
      _displayWidth = _processedImage!.width;
      _displayHeight = _processedImage!.height;

      setState(() {}); // UI aktualisieren
      _setCropRectForDisplay();
    } catch (e) {
      debugPrint('EditScreen._applyImageSettings FEHLER: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Bildbearbeitung: $e')),
        );
      }
    }
  }

  void _applyCrop() async {
    if (_displayWidth == 0 || _displayHeight == 0 || _croppingInProgress) return;

    setState(() {
      _croppingInProgress = true;
    });

    try {
      // Berechne Skalierungsfaktor: Display-Bild -> Bildschirm
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final scaleX = screenWidth / _displayWidth;
      final scaleY = screenHeight / _displayHeight;
      final scale = math.min(scaleX, scaleY);

      // Crop-Rechteck auf Display-Bild-Koordinaten umrechnen
      final x = (_cropRect.left / scale).floor().clamp(0, _displayWidth);
      final y = (_cropRect.top / scale).floor().clamp(0, _displayHeight);
      final w = (_cropRect.width / scale).floor().clamp(1, _displayWidth - x);
      final h = (_cropRect.height / scale).floor().clamp(1, _displayHeight - y);

      // WICHTIG: Die Koordinaten müssen auf das ORIGINAL-Bild hochgerechnet werden
      // für den eigentlichen Crop in cropFile
      final origScaleX = _originalImage.width / _displayWidth;
      final origScaleY = _originalImage.height / _displayHeight;

      final origX = (x * origScaleX).floor().clamp(0, _originalImage.width);
      final origY = (y * origScaleY).floor().clamp(0, _originalImage.height);
      final origW = (w * origScaleX).floor().clamp(1, _originalImage.width - origX);
      final origH = (h * origScaleY).floor().clamp(1, _originalImage.height - origY);

      debugPrint('EditScreen._applyCrop: Display-Crop: $x,$y ${w}x$h -> Original-Crop: $origX,$origY ${origW}x$origH');

      // Als neue Datei speichern (nutzt Original-Pfad und Original-Koordinaten)
      final savedPath = await _cropHelper.cropFile(
        quelle: widget.originalPath,
        crop: Rect.fromLTWH(origX.toDouble(), origY.toDouble(), origW.toDouble(), origH.toDouble()),
      );

      if (mounted) {
        Navigator.pop(context, savedPath);
      }
    } catch (e) {
      debugPrint('EditScreen._applyCrop FEHLER: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Zuschneiden: $e')),
        );
        setState(() {
          _croppingInProgress = false;
        });
      }
    }
  }

  void _restoreOriginal() {
    setState(() {
      _brightness = 1.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _rotation = 0;
      _cropRect = Rect.zero;
    });
    _applyImageSettings();
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _istDunkel
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _istDunkel ? Colors.black : Colors.white,
        body: Stack(
          children: [
            // --- Hauptbildbereich ---
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Center(
                child: GestureDetector(
                  onPanStart: (details) {
                    if (_croppingInProgress || _displayWidth == 0) return;
                    setState(() {
                      _isDragging = true;
                      _cropRect = Rect.fromPoints(details.localPosition, details.localPosition);
                    });
                  },
                  onPanUpdate: (details) {
                    if (_croppingInProgress || !_isDragging || _displayWidth == 0) return;
                    setState(() {
                      _cropRect = Rect.fromPoints(
                        _cropRect.topLeft,
                        details.localPosition,
                      );
                    });
                  },
                  onPanEnd: (details) {
                    if (_croppingInProgress || !_isDragging) return;
                    setState(() {
                      _isDragging = false;
                    });
                  },
                  child: Stack(
                    children: [
                      Center(
                        child: _displayBytes != null && _displayBytes!.isNotEmpty
                            ? InteractiveViewer(
                                panEnabled: false,
                                scaleEnabled: false,
                                child: SizedBox(
                                  width: _displayWidth.toDouble(),
                                  height: _displayHeight.toDouble(),
                                  child: Image.memory(
                                    _displayBytes!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      // --- Crop-Overlay ---
                      if (_displayWidth > 0)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CropPainter(
                              cropRect: _cropRect,
                              isDragging: _isDragging,
                              brightness: Theme.of(context).brightness,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // --- Ganz links: Crop-Button (vorne im Stack, ganz links) ---
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: _istDunkel ? Colors.grey.shade800 : Colors.grey.shade300,
                    elevation: 3,
                    borderRadius: BorderRadius.circular(50),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _croppingInProgress ? null : _applyCrop,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _istDunkel ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.7),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: _croppingInProgress
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Icon(
                                  Icons.crop_free_outlined,
                                  size: 24,
                                  color: _istDunkel ? Colors.white : Colors.black,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- Ganz rechts: Zurücksetzen-Button ---
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: _istDunkel ? Colors.grey.shade800 : Colors.grey.shade300,
                    elevation: 3,
                    borderRadius: BorderRadius.circular(50),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _restoreOriginal,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.refresh,
                          size: 24,
                          color: _istDunkel ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // --- Bottom Sheet mit Bearbeitungsoptionen ---
        bottomNavigationBar:
            _isLoading ? null : _buildEditOptionsSheet(settings),
      ),
    );
  }

  Widget _buildEditOptionsSheet(SettingsProvider settings) {
    return Container(
      decoration: BoxDecoration(
        color: _istDunkel ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: _istDunkel ? Colors.grey.shade700 : Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _istDunkel ? Colors.grey.shade600 : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Bearbeitungsoptionen
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // Helligkeit
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_getLabelText('brightness'), style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: _brightness,
                        min: 0.0,
                        max: 2.0,
                        divisions: 100,
                        label: _brightness.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() {
                            _brightness = value;
                          });
                          _applyImageSettings();
                        },
                        activeColor: settings.appButtonColor,
                      ),
                    ],
                  ),

                  // Kontrast
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_getLabelText('contrast'), style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: _contrast,
                        min: 0.0,
                        max: 2.0,
                        divisions: 100,
                        label: _contrast.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() {
                            _contrast = value;
                          });
                          _applyImageSettings();
                        },
                        activeColor: settings.appButtonColor,
                      ),
                    ],
                  ),

                  // Sättigung
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_getLabelText('saturation'), style: const TextStyle(fontSize: 12)),
                      Slider(
                        value: _saturation,
                        min: 0.0,
                        max: 2.0,
                        divisions: 100,
                        label: _saturation.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() {
                            _saturation = value;
                          });
                          _applyImageSettings();
                        },
                        activeColor: settings.appButtonColor,
                      ),
                    ],
                  ),

                  // Trenner
                  const VerticalDivider(thickness: 1, indent: 0, endIndent: 0),

                  // Drehen - Links
                  IconButton(
                    icon: const Icon(Icons.rotate_left),
                    onPressed: () {
                      setState(() {
                        _rotation = (_rotation + 90) % 360;
                      });
                      _applyImageSettings();
                    },
                  ),

                  // Drehen - Rechts
                  IconButton(
                    icon: const Icon(Icons.rotate_right),
                    onPressed: () {
                      setState(() {
                        _rotation = (_rotation - 90) % 360;
                      });
                      _applyImageSettings();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getLabelText(String key) {
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    return _getText(lang, key);
  }

  String _getText(String lang, String key) {
    switch (lang) {
      case 'en':
        return translationsEn[key] ?? key;
      case 'fr':
        return translationsFr[key] ?? key;
      case 'es':
        return translationsEs[key] ?? key;
      default:
        return translationsDe[key] ?? key;
    }
  }
}

/// CustomPainter für das Crop-Overlay
class _CropPainter extends CustomPainter {
  final Rect cropRect;
  final bool isDragging;
  final Brightness brightness;

  _CropPainter({required this.cropRect, required this.isDragging, required this.brightness});

  @override
  void paint(Canvas canvas, Size size) {
    // Dunkler Overlay für Bereiche AUSSERHALB des Crop-Rechtecks
    final darkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = brightness == Brightness.dark
          ? Colors.black.withValues(alpha: 0.7)
          : Colors.black.withValues(alpha: 0.6);

    // Zeichne 4 Rechtecke für die Bereiche außerhalb des Crop-Bereichs
    // Oben
    if (cropRect.top > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, cropRect.top),
        darkPaint,
      );
    }
    // Unten
    if (cropRect.bottom < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(0, cropRect.bottom, size.width, size.height - cropRect.bottom),
        darkPaint,
      );
    }
    // Links
    if (cropRect.left > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, cropRect.top, cropRect.left, cropRect.height),
        darkPaint,
      );
    }
    // Rechts
    if (cropRect.right < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(cropRect.right, cropRect.top, size.width - cropRect.right, cropRect.height),
        darkPaint,
      );
    }

    // Rahmen zeichnen
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;

    final cornerPaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.fill;

    // Linien
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top),
      Offset(cropRect.right, cropRect.top),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.top),
      Offset(cropRect.right, cropRect.bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cropRect.right, cropRect.bottom),
      Offset(cropRect.left, cropRect.bottom),
      borderPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.bottom),
      Offset(cropRect.left, cropRect.top),
      borderPaint,
    );

    // Ecken-Punkte (kleine Quadrate an den Ecken)
    const cornerSize = 12.0;
    final cornerRects = [
      Rect.fromLTWH(cropRect.left - cornerSize / 2, cropRect.top - cornerSize / 2, cornerSize, cornerSize),
      Rect.fromLTWH(cropRect.right - cornerSize / 2, cropRect.top - cornerSize / 2, cornerSize, cornerSize),
      Rect.fromLTWH(cropRect.left - cornerSize / 2, cropRect.bottom - cornerSize / 2, cornerSize, cornerSize),
      Rect.fromLTWH(cropRect.right - cornerSize / 2, cropRect.bottom - cornerSize / 2, cornerSize, cornerSize),
    ];

    for (final rect in cornerRects) {
      canvas.drawRect(rect, borderPaint);
      canvas.drawRect(rect, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect ||
        oldDelegate.isDragging != isDragging;
  }
}