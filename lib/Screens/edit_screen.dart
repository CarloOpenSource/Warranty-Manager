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
  late bool _istDunkel;

  // Crop-Bereich (in Bildschirm-Koordinaten)
  Rect _cropRect = Rect.zero;
  bool _isDragging = false;
  bool _croppingInProgress = false;

  // Bildbearbeitungswerte
  double _brightness = 1.0; // 1.0 = normal, 0.0 = schwarz, >1 = heller
  double _contrast = 1.0;   // 1.0 = normal, 0.0 = grau, >1 = mehr Kontrast
  double _saturation = 1.0; // 1.0 = normal, 0.0 = Graustufen, >1 = mehr Sättigung

  // Ladezustand
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _istDunkel = Theme.of(context).brightness == Brightness.dark;
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

  Future<void> _loadImage() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final bytes = await File(widget.imageDataPath).readAsBytes();
      _originalImage = img.decodeImage(bytes)!;
      _processedImage = img.Image.from(_originalImage);

      // Standard: Bild auf maximale Bildschirmgröße skalieren für Anzeige
      _applyImageSettings();
    } catch (e) {
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

  void _applyImageSettings() {
    img.Image image = img.Image.from(_originalImage);

    // Helligkeit, Kontrast, Sättigung anwenden
    image = img.adjustColor(
      image,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
    );

    _processedImage = image;

    // Standard-Crop-Bereich auf das gesamte Bild
    if (_cropRect.isEmpty && _processedImage != null) {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final scale = math.min(screenWidth / _processedImage!.width, screenHeight / _processedImage!.height);
      final scaledWidth = _processedImage!.width * scale;
      final scaledHeight = _processedImage!.height * scale;
      _cropRect = Rect.fromLTWH(
        (screenWidth - scaledWidth) / 2,
        (screenHeight - scaledHeight) / 2,
        scaledWidth,
        scaledHeight,
      );
    }
  }

  void _applyCrop() async {
    if (_processedImage == null || _croppingInProgress) return;

    setState(() {
      _croppingInProgress = true;
    });

    try {
      final original = _processedImage!;

      // Berechne die Pixel-Koordinaten im Originalbild
      // _cropRect ist in Bildschirm-Koordinaten, muss auf Bild-Koordinaten umgerechnet werden
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;

      // Berechne Skalierungsfaktor: Bild -> Bildschirm
      final scaleX = screenWidth / original.width;
      final scaleY = screenHeight / original.height;
      final scale = math.min(scaleX, scaleY);

      final x = (_cropRect.left / scale).floor().clamp(0, original.width);
      final y = (_cropRect.top / scale).floor().clamp(0, original.height);
      final w = (_cropRect.width / scale).floor().clamp(1, original.width - x);
      final h = (_cropRect.height / scale).floor().clamp(1, original.height - y);

      // Als neue Datei speichern
      final savedPath = await _cropHelper.cropFile(
        quelle: widget.originalPath,
        crop: Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
      );

      if (mounted) {
        Navigator.pop(context, savedPath);
      }
    } catch (e) {
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
      _processedImage = img.Image.from(_originalImage);
      _brightness = 1.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _cropRect = Rect.zero;
    });
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
                    if (_croppingInProgress || _processedImage == null) return;
                    setState(() {
                      _isDragging = true;
                      _cropRect = Rect.fromPoints(details.localPosition, details.localPosition);
                    });
                  },
                  onPanUpdate: (details) {
                    if (_croppingInProgress || !_isDragging || _processedImage == null) return;
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
                        child: _processedImage != null
                            ? InteractiveViewer(
                                panEnabled: false,
                                scaleEnabled: false,
                                child: SizedBox(
                                  width: _processedImage!.width.toDouble(),
                                  height: _processedImage!.height.toDouble(),
                                  child: Image.memory(
                                    Uint8List.fromList(img.encodeJpg(_processedImage!)),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      // --- Crop-Overlay ---
                      if (_processedImage != null)
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
                            _applyImageSettings();
                          });
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
                            _applyImageSettings();
                          });
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
                            _applyImageSettings();
                          });
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
                      if (_processedImage != null) {
                        setState(() {
                          _processedImage = img.copyRotate(_processedImage!, angle: 90);
                          _applyImageSettings();
                        });
                      }
                    },
                  ),

                  // Drehen - Rechts
                  IconButton(
                    icon: const Icon(Icons.rotate_right),
                    onPressed: () {
                      if (_processedImage != null) {
                        setState(() {
                          _processedImage = img.copyRotate(_processedImage!, angle: -90);
                          _applyImageSettings();
                        });
                      }
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