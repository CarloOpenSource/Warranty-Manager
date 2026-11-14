import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Services/settings_provider.dart';

/// Professioneller Bild-Editor (wie Galerie-Apps):
/// - Freier Crop mit ziehbaren Ecken/Rändern NUR auf dem Bild
/// - Debounced Slider für flüssige Performance
/// - Buttons: Links Schließen, Rechts Speichern
/// - **Speichert IN DIE ORIGINALDATEI** (globale Aktualisierung)
/// - **Isolate für schweres Speichern** (kein UI-Lag)
/// - Persistente Einstellungen pro Bild
/// - **Backup der Originaldatei beim ersten Laden** - Reset stellt Original wieder her
/// - Rotation 0, 90, 180, 270 Grad
/// - Crop NUR auf dem Bildbereich
/// - Export/Import von Einstellungen
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

  /// Exportiert alle Bearbeitungseinstellungen als JSON-String (für Backup/Import).
  static Future<String?> exportAllSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const String prefix = 'edit_settings_';
      final settings = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix)) {
          settings[key] = prefs.getString(key);
        }
      }
      if (settings.isEmpty) return null;
      return jsonEncode(settings);
    } catch (e) {
      debugPrint('EditScreen.exportAllSettings FEHLER: $e');
      return null;
    }
  }

  /// Importiert Bearbeitungseinstellungen aus JSON-String.
  static Future<void> importSettings(String jsonStr) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const String prefix = 'edit_settings_';
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      for (final entry in data.entries) {
        if (entry.key.startsWith(prefix)) {
          await prefs.setString(entry.key, entry.value as String);
        }
      }
    } catch (e) {
      debugPrint('EditScreen.importSettings FEHLER: $e');
    }
  }
}

class _EditScreenState extends State<EditScreen> with WidgetsBindingObserver {
  bool _istDunkel = true;

  // Crop-Bereich (in Display-Bild-Koordinaten)
  Rect _cropRect = Rect.zero;
  bool _isCropMode = false;
  _DragHandle? _activeHandle;

  // Bildbearbeitungswerte
  double _brightness = 1.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  int _rotation = 0; // 0, 90, 180, 270

  // Ladezustand
  bool _isLoading = true;
  bool _isSaving = false;

  // Display-Parameter (max 1024px für flüssige Performance)
  Uint8List? _displayBytes;
  int _displayWidth = 0;
  int _displayHeight = 0;
  img.Image? _originalImage;
  img.Image? _baseDisplayImage; // aktuelles Arbeitsbild (rotiert, gecroppt)
  img.Image? _originalBackup;   // KOPIE des Originalbildes für Reset

  // Track ob Änderungen gemacht wurden
  bool _hasChanges = false;

  // Skalierungsfaktor: Bildschirmpixel / Display-Bildpixel
  // Wird in LayoutBuilder berechnet und für Crop-Koordinaten genutzt.
  double _renderScale = 1.0;

  // Debounce Timer für Slider
  Timer? _debounceTimer;
  bool _pendingUpdate = false;

  // Persistente Einstellungen pro Bild
  static const String _prefsPrefix = 'edit_settings_';

  static const int _maxDisplayDimension = 1024;
  static const double _handleSize = 24.0;
  static const Duration _debounceDelay = Duration(milliseconds: 80);

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
      _istDunkel = newBrightness;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Hilfsmethode für übersetzte Texte
  String _getLabelText(String key) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    return getText(settings.languageCode, key);
  }

  /// Lädt das Bild und skaliert es auf max 1024px für die Anzeige.
  /// Erstellt eine KOPIE des Originals für Reset-Funktionalität.
  Future<void> _loadImage() async {
    setState(() => _isLoading = true);

    try {
      final file = File(widget.imageDataPath);
      if (!await file.exists()) {
        throw FileSystemException('Datei nicht gefunden', widget.imageDataPath);
      }
      final bytes = await file.readAsBytes();
      _originalImage = img.decodeImage(bytes)!;

      // BACKUP des Originalbildes erstellen (für Reset)
      _originalBackup = img.Image.from(_originalImage!);

      // Display-Bild vorbereiten (max 1024px)
      _baseDisplayImage = _originalImage!;
      if (_originalImage!.width > _maxDisplayDimension || _originalImage!.height > _maxDisplayDimension) {
        final scale = math.min(
          _maxDisplayDimension / _originalImage!.width,
          _maxDisplayDimension / _originalImage!.height,
        );
        _baseDisplayImage = img.copyResize(_originalImage!,
          width: (_originalImage!.width * scale).round(),
          height: (_originalImage!.height * scale).round(),
        );
      }

      // Gespeicherte Einstellungen für dieses Bild laden
      await _loadSettingsForImage();

      // Initiales Crop-Rechteck = ganzes Bild
      _cropRect = Rect.fromLTWH(0, 0, _baseDisplayImage!.width.toDouble(), _baseDisplayImage!.height.toDouble());
      _rebuildDisplay();
    } catch (e, stack) {
      debugPrint('EditScreen._loadImage FEHLER: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e')));
        Navigator.pop(context);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// Lädt die gespeicherten Bearbeitungseinstellungen für das aktuelle Bild.
  Future<void> _loadSettingsForImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsPrefix${widget.imageDataPath.hashCode}';
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        _brightness = (data['brightness'] as num?)?.toDouble() ?? 1.0;
        _contrast = (data['contrast'] as num?)?.toDouble() ?? 1.0;
        _saturation = (data['saturation'] as num?)?.toDouble() ?? 1.0;
        _rotation = (data['rotation'] as int?) ?? 0;
        if (data['cropRect'] != null && _baseDisplayImage != null) {
          final crop = data['cropRect'] as Map<String, dynamic>;
          final double imgW = _baseDisplayImage!.width.toDouble();
          final double imgH = _baseDisplayImage!.height.toDouble();
          final double left = ((crop['left'] as num?)?.toDouble() ?? 0).clamp(0, imgW - 1);
          final double top = ((crop['top'] as num?)?.toDouble() ?? 0).clamp(0, imgH - 1);
          final double width = ((crop['width'] as num?)?.toDouble() ?? imgW).clamp(1, imgW - left);
          final double height = ((crop['height'] as num?)?.toDouble() ?? imgH).clamp(1, imgH - top);
          _cropRect = Rect.fromLTWH(left, top, width, height);
        }
        _hasChanges = true;
      }
    } catch (e) {
      debugPrint('EditScreen._loadSettingsForImage FEHLER: $e');
    }
  }

  /// Speichert die aktuellen Bearbeitungseinstellungen für das aktuelle Bild.
  Future<void> _saveSettingsForImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsPrefix${widget.imageDataPath.hashCode}';
      final data = {
        'brightness': _brightness,
        'contrast': _contrast,
        'saturation': _saturation,
        'rotation': _rotation,
        'cropRect': {
          'left': _cropRect.left,
          'top': _cropRect.top,
          'width': _cropRect.width,
          'height': _cropRect.height,
        },
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      debugPrint('EditScreen._saveSettingsForImage FEHLER: $e');
    }
  }

  /// Baut das Anzeige-Bild aus _baseDisplayImage + Einstellungen.
  void _rebuildDisplay() {
    if (_baseDisplayImage == null) return;
    final processed = _applySettingsToImage(_baseDisplayImage!);
    _displayBytes = Uint8List.fromList(img.encodeJpg(processed, quality: 92));
    _displayWidth = processed.width;
    _displayHeight = processed.height;
  }

  /// Wendet Helligkeit, Kontrast, Sättigung, Rotation an.
  /// _rotation: 0, 90, 180, 270
  img.Image _applySettingsToImage(img.Image source) {
    img.Image image = img.Image.from(source);
    if (_rotation == 90) {
      image = img.copyRotate(image, angle: 90);
    } else if (_rotation == 180) {
      image = img.copyRotate(image, angle: 180);
    } else if (_rotation == 270) {
      image = img.copyRotate(image, angle: 270);
    }
    image = img.adjustColor(image, brightness: _brightness, contrast: _contrast, saturation: _saturation);
    return image;
  }

  /// Debounced Update für Slider - verhindert Lag.
  void _scheduleDisplayUpdate() {
    _pendingUpdate = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      if (_pendingUpdate && mounted) {
        _pendingUpdate = false;
        _rebuildDisplay();
        _hasChanges = true;
        setState(() {}); // nur UI neu zeichnen
      }
    });
  }

  void _onBrightnessChanged(double v) { _brightness = v; _scheduleDisplayUpdate(); }
  void _onContrastChanged(double v) { _contrast = v; _scheduleDisplayUpdate(); }
  void _onSaturationChanged(double v) { _saturation = v; _scheduleDisplayUpdate(); }

  void _rotateLeft() {
    _rotation = (_rotation + 90) % 360;
    _debounceTimer?.cancel();
    _pendingUpdate = false;
    _rebuildDisplay(); // aktualisiert _displayWidth/_displayHeight
    // Crop-Rect auf volle neue (rotierte) Bildgröße zurücksetzen
    _cropRect = Rect.fromLTWH(0, 0, _displayWidth.toDouble(), _displayHeight.toDouble());
    _hasChanges = true;
    if (mounted) setState(() {});
  }
  void _rotateRight() {
    _rotation = (_rotation - 90 + 360) % 360;
    _debounceTimer?.cancel();
    _pendingUpdate = false;
    _rebuildDisplay();
    _cropRect = Rect.fromLTWH(0, 0, _displayWidth.toDouble(), _displayHeight.toDouble());
    _hasChanges = true;
    if (mounted) setState(() {});
  }

  /// Sofortiges Rebuild (für Rotation, Crop-Mode Toggle).
  void _rebuildFromBase() {
    _debounceTimer?.cancel();
    _pendingUpdate = false;
    _rebuildDisplay();
    _hasChanges = true;
    if (mounted) setState(() {});
  }

  /// Speichert ALLES (Crop + Anpassungen) in die ORIGINALDATEI.
  /// Erst per Isolate (Hintergrund-Thread), bei Fehler Fallback auf Main-Thread.
  Future<void> _saveAndExit() async {
    if (_originalImage == null || _isSaving) return;

    setState(() {
      _isSaving = true;
      _isCropMode = false;
    });

    try {
      // 1. Original-Bytes laden
      final originalBytes = await File(widget.originalPath).readAsBytes();
      final saveParams = _SaveParams(
        originalBytes: originalBytes,
        originalWidth: _originalImage!.width,
        originalHeight: _originalImage!.height,
        displayWidth: _displayWidth,
        displayHeight: _displayHeight,
        cropRect: _cropRect,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        rotation: _rotation,
        originalPath: widget.originalPath,
      );

      // 2. Versuch per Isolate (nicht-blockierend)
      _SaveResult result;
      try {
        result = await Isolate.run(() => _saveInBackground(saveParams))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('Isolate fehlgeschlagen, Fallback auf Main-Thread: $e');
        result = _saveInBackground(saveParams);
      }

      if (mounted) {
        if (result.success) {
          await _saveSettingsForImage(); // Einstellungen persistent speichern
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Bild gespeichert!')));
          // ignore: use_build_context_synchronously
          Navigator.pop(context, widget.originalPath);
        } else {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Fehler: ${result.error}')));
          setState(() => _isSaving = false);
        }
      }
    } catch (e) {
      debugPrint('EditScreen._saveAndExit FEHLER: $e');
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  /// Crop-Mode toggeln. Beim Beenden wird das Bild permanent gecropped.
  void _toggleCropMode() {
    if (!_isCropMode) {
      // Crop-Mode starten
      setState(() {
        _isCropMode = true;
      });
    } else {
      // Crop-Mode beenden -> Bild PERMANENT croppen
      _applyCropToBaseImage();
      setState(() {
        _isCropMode = false;
        _activeHandle = null;
      });
    }
  }

  /// Wendet den Crop permanent auf das Base-Display-Image an.
  void _applyCropToBaseImage() {
    if (_baseDisplayImage == null || _cropRect.isEmpty) return;
    if (_displayWidth == 0 || _displayHeight == 0) return;

    // Crop-Rect auf Base-Image Koordinaten (1:1 da Base = Display)
    final x = _cropRect.left.floor().clamp(0, _baseDisplayImage!.width);
    final y = _cropRect.top.floor().clamp(0, _baseDisplayImage!.height);
    final w = _cropRect.width.floor().clamp(1, _baseDisplayImage!.width - x);
    final h = _cropRect.height.floor().clamp(1, _baseDisplayImage!.height - y);

    _baseDisplayImage = img.copyCrop(_baseDisplayImage!, x: x, y: y, width: w, height: h);
    _rebuildDisplay(); // aktualisiert _displayWidth/_displayHeight
    _cropRect = Rect.fromLTWH(0, 0, _displayWidth.toDouble(), _displayHeight.toDouble());
    _hasChanges = true;
  }

  /// Setzt ALLES auf Original zurück (Backup wiederherstellen).
  void _resetToOriginal() {
    if (_originalBackup != null) {
      // Original-Backup wiederherstellen
      _baseDisplayImage = img.Image.from(_originalBackup!);
      if (_originalBackup!.width > _maxDisplayDimension || _originalBackup!.height > _maxDisplayDimension) {
        final scale = math.min(
          _maxDisplayDimension / _originalBackup!.width,
          _maxDisplayDimension / _originalBackup!.height,
        );
        _baseDisplayImage = img.copyResize(_originalBackup!,
          width: (_originalBackup!.width * scale).round(),
          height: (_originalBackup!.height * scale).round(),
        );
      }
    }
    // Crop-Rect auf VOLLES Bild setzen
    final fullRect = Rect.fromLTWH(0, 0, _baseDisplayImage!.width.toDouble(), _baseDisplayImage!.height.toDouble());
    setState(() {
      _brightness = 1.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _rotation = 0;
      _cropRect = fullRect;
      _activeHandle = null;
    });
    _rebuildFromBase();
  }

  /// Crop-Handle Hit-Test.
  /// Pan-Start für Crop-Handles.
  void _onPanStart(PointerDownEvent d) {
    if (!_isCropMode) return;
    // d.localPosition ist bereits relativ zum Listener (= Bildbereich)
    _activeHandle = _hitTestHandleScreen(d.localPosition);
  }

  /// Pan-Update für Crop-Handles.
  void _onPanUpdate(PointerMoveEvent d) {
    if (!_isCropMode || _activeHandle == null) return;
    // Bildschirmkoordinaten → Bildpixel-Koordinaten
    final s = _renderScale > 0 ? _renderScale : 1.0;
    final imgPos = Offset(d.localPosition.dx / s, d.localPosition.dy / s);
    setState(() {
      _cropRect = _resizeRect(_cropRect, _activeHandle!.type, imgPos);
      _hasChanges = true;
    });
  }

  void _onPanEnd(_) {
    _activeHandle = null;
  }

  /// Prüft, ob eine Bildschirmposition (relativ zum Bild-Listener) einen Handle trifft.
  /// Handles werden in Bildschirm-Pixeln verglichen (= Bildpixel × _renderScale).
  _DragHandle? _hitTestHandleScreen(Offset screenLocal) {
    if (!_isCropMode || _renderScale <= 0) return null;
    final s = _renderScale;
    final r = _cropRect;
    final List<({_DragType type, Offset pos})> handles = [
      (type: _DragType.topLeft,     pos: Offset(r.left * s,      r.top * s)),
      (type: _DragType.topRight,    pos: Offset(r.right * s,     r.top * s)),
      (type: _DragType.bottomLeft,  pos: Offset(r.left * s,      r.bottom * s)),
      (type: _DragType.bottomRight, pos: Offset(r.right * s,     r.bottom * s)),
      (type: _DragType.top,         pos: Offset(r.center.dx * s, r.top * s)),
      (type: _DragType.bottom,      pos: Offset(r.center.dx * s, r.bottom * s)),
      (type: _DragType.left,        pos: Offset(r.left * s,      r.center.dy * s)),
      (type: _DragType.right,       pos: Offset(r.right * s,     r.center.dy * s)),
    ];
    for (final h in handles) {
      final hitRect = Rect.fromCenter(center: h.pos, width: _handleSize, height: _handleSize);
      if (hitRect.contains(screenLocal)) return _DragHandle(h.type, h.pos);
    }
    return null;
  }

  /// Vergrößert/verkleinert das Crop-Rechteck am Handle.
  Rect _resizeRect(Rect rect, _DragType type, Offset pos) {
    double left = rect.left, top = rect.top, right = rect.right, bottom = rect.bottom;
    switch (type) {
      case _DragType.topLeft: left = pos.dx; top = pos.dy; break;
      case _DragType.topRight: right = pos.dx; top = pos.dy; break;
      case _DragType.bottomLeft: left = pos.dx; bottom = pos.dy; break;
      case _DragType.bottomRight: right = pos.dx; bottom = pos.dy; break;
      case _DragType.top: top = pos.dy; break;
      case _DragType.bottom: bottom = pos.dy; break;
      case _DragType.left: left = pos.dx; break;
      case _DragType.right: right = pos.dx; break;
    }
    // Clamping & Mindestgröße - NUR innerhalb des Bildes!
    left = left.clamp(0.0, _displayWidth - 20.0).toDouble();
    right = right.clamp(left + 20.0, _displayWidth.toDouble()).toDouble();
    top = top.clamp(0.0, _displayHeight - 20.0).toDouble();
    bottom = bottom.clamp(top + 20.0, _displayHeight.toDouble()).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Bestätigung beim Schließen mit ungespeicherten Änderungen.
  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_getLabelText('discard_changes_title')),
        content: Text(_getLabelText('discard_changes_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_getLabelText('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(_getLabelText('discard'))),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    _istDunkel = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            // ignore: use_build_context_synchronously
            Navigator.pop(context);
          }
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _istDunkel ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: _istDunkel ? Colors.black : Colors.white,
          body: Stack(
            children: [
              // --- Hauptbildbereich ---
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                // LayoutBuilder passt das Bild an die verfügbare Fläche an,
                // damit der Crop-Rahmen nie außerhalb des Bildschirms liegt.
                Positioned.fill(
                  child: _displayBytes == null || _displayWidth == 0 || _displayHeight == 0
                      ? const SizedBox.shrink()
                      : LayoutBuilder(
                          builder: (ctx, constraints) {
                            final double imgW = _displayWidth.toDouble();
                            final double imgH = _displayHeight.toDouble();
                            final double scale = math.min(
                              constraints.maxWidth / imgW,
                              constraints.maxHeight / imgH,
                            );
                            final double fitW = imgW * scale;
                            final double fitH = imgH * scale;
                            final double offsetX = (constraints.maxWidth - fitW) / 2;
                            final double offsetY = (constraints.maxHeight - fitH) / 2;
                            // Skalierungsfaktor für Koordinaten-Umrechnung speichern
                            _renderScale = scale;
                            return Stack(
                              children: [
                                // Bild – mit Zoom/Pan wenn NICHT im Crop-Mode
                                Positioned(
                                  left: offsetX, top: offsetY,
                                  width: fitW, height: fitH,
                                  child: _isCropMode
                                      ? Image.memory(
                                          _displayBytes!,
                                          fit: BoxFit.fill,
                                          gaplessPlayback: true,
                                        )
                                      : InteractiveViewer(
                                          panEnabled: true,
                                          minScale: 0.5,
                                          maxScale: 4.0,
                                          child: Image.memory(
                                            _displayBytes!,
                                            fit: BoxFit.fill,
                                            gaplessPlayback: true,
                                          ),
                                        ),
                                ),
                                // Crop-Overlay – exakt über dem skalierten Bild,
                                // AUSSERHALB des InteractiveViewer damit Koordinaten
                                // immer zum sichtbaren Bild passen.
                                if (_isCropMode)
                                  Positioned(
                                    left: offsetX, top: offsetY,
                                    width: fitW, height: fitH,
                                    child: Listener(
                                      onPointerDown: _onPanStart,
                                      onPointerMove: _onPanUpdate,
                                      onPointerUp: _onPanEnd,
                                      behavior: HitTestBehavior.translucent,
                                      child: CustomPaint(
                                        size: Size(fitW, fitH),
                                        painter: _CropPainter(
                                          // Crop-Rect von Bildpixeln → Bildschirmpixel
                                          cropRect: Rect.fromLTWH(
                                            _cropRect.left * scale,
                                            _cropRect.top * scale,
                                            _cropRect.width * scale,
                                            _cropRect.height * scale,
                                          ),
                                          isActive: true,
                                          handleSize: _handleSize,
                                          brightness: Theme.of(context).brightness,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),

              // --- GANZ LINKS: SCHLIESSEN (Kreuz) ---
              Positioned(
                top: 0, left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: _istDunkel ? Colors.grey.shade800 : Colors.grey.shade200,
                      elevation: 4, shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _isSaving ? null : () async {
                          final shouldPop = await _onWillPop();
                          if (shouldPop && mounted) {
                            // ignore: use_build_context_synchronously
                            Navigator.pop(context);
                          }
                        },
                        child: const SizedBox(width: 48, height: 48, child: Icon(Icons.close, size: 28, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),

              // --- GANZ RECHTS: SPEICHERN (Haken) ---
              Positioned(
                top: 0, right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: _istDunkel ? Colors.green.shade700 : Colors.green.shade600,
                      elevation: 4, shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _isSaving ? null : _saveAndExit,
                        child: _isSaving
                            ? const SizedBox(width: 48, height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(Colors.white))))
                            : const SizedBox(width: 48, height: 48, child: Icon(Icons.check, size: 28, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),

              // --- UNTEN MITTE: CROP-TOGGLE ---
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Material(
                        color: _istDunkel ? Colors.grey.shade800 : Colors.white,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: _isSaving ? null : _toggleCropMode,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(_isCropMode ? Icons.crop_free : Icons.crop_free_outlined, size: 22, color: _istDunkel ? Colors.white : Colors.black),
                              const SizedBox(width: 8),
                              Text(_isCropMode ? _getLabelText('crop_done') : _getLabelText('crop'), style: TextStyle(color: _istDunkel ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _isLoading ? null : _buildEditOptionsSheet(settings),
        ),
      ),
    );
  }

  Widget _buildEditOptionsSheet(SettingsProvider settings) {
    return Container(
      decoration: BoxDecoration(
        color: _istDunkel ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(top: BorderSide(color: _istDunkel ? Colors.grey.shade700 : Colors.grey.shade300)),
      ),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: _istDunkel ? Colors.grey.shade600 : Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Wrap(spacing: 12, runSpacing: 12, children: [
          _buildSlider('brightness', Icons.wb_sunny_outlined, _brightness, _onBrightnessChanged, settings),
          _buildSlider('contrast', Icons.contrast_outlined, _contrast, _onContrastChanged, settings),
          _buildSlider('saturation', Icons.color_lens_outlined, _saturation, _onSaturationChanged, settings),
          const VerticalDivider(thickness: 1),
          IconButton(icon: const Icon(Icons.rotate_left), onPressed: _isSaving ? null : _rotateLeft, tooltip: _getLabelText('rotate_left')),
          IconButton(icon: const Icon(Icons.rotate_right), onPressed: _isSaving ? null : _rotateRight, tooltip: _getLabelText('rotate_right')),
          const VerticalDivider(thickness: 1),
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.redAccent),
            onPressed: _isSaving ? null : _resetToOriginal,
            tooltip: _getLabelText('reset_all'),
          ),
        ])),
      ])),
    );
  }

  Widget _buildSlider(String key, IconData icon, double value, void Function(double) onChanged, SettingsProvider settings) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: Colors.grey), const SizedBox(width: 4), Text(_getLabelText(key), style: const TextStyle(fontSize: 11))]),
      SizedBox(width: 160, child: Slider(value: value, min: 0.0, max: 2.0, divisions: 100, label: value.toStringAsFixed(1), onChanged: _isSaving ? null : onChanged, activeColor: settings.appButtonColor)),
    ]);
  }
}

/// Parameter für Hintergrund-Speichern
class _SaveParams {
  final Uint8List originalBytes;
  final int originalWidth;
  final int originalHeight;
  final int displayWidth;
  final int displayHeight;
  final Rect cropRect;
  final double brightness;
  final double contrast;
  final double saturation;
  final int rotation;
  final String originalPath;

  const _SaveParams({
    required this.originalBytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.displayWidth,
    required this.displayHeight,
    required this.cropRect,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.rotation,
    required this.originalPath,
  });
}

class _SaveResult {
  final bool success;
  final String? error;
  const _SaveResult({required this.success, this.error});
}

/// Läuft im ISOLATE (Hintergrund-Thread) - UI blockiert NICHT!
_SaveResult _saveInBackground(_SaveParams p) {
  try {
    // 1. Original dekodieren
    final img.Image? original = img.decodeImage(p.originalBytes);
    if (original == null) return const _SaveResult(success: false, error: 'Bild nicht decodierbar');

    // 2. Anpassungen anwenden
    img.Image finalImage = img.Image.from(original);
    if (p.rotation == 90) {
      finalImage = img.copyRotate(finalImage, angle: 90);
    } else if (p.rotation == 180) {
      finalImage = img.copyRotate(finalImage, angle: 180);
    } else if (p.rotation == 270) {
      finalImage = img.copyRotate(finalImage, angle: 270);
    }
    finalImage = img.adjustColor(finalImage, brightness: p.brightness, contrast: p.contrast, saturation: p.saturation);

    // 3. Crop auf Original-Koordinaten umrechnen & anwenden
    if (!p.cropRect.isEmpty && p.displayWidth > 0 && p.displayHeight > 0) {
      final scaleX = p.originalWidth / p.displayWidth;
      final scaleY = p.originalHeight / p.displayHeight;

      final origX = ((p.cropRect.left * scaleX).floor().clamp(0, p.originalWidth));
      final origY = ((p.cropRect.top * scaleY).floor().clamp(0, p.originalHeight));
      final origW = ((p.cropRect.width * scaleX).floor().clamp(1, p.originalWidth - origX));
      final origH = ((p.cropRect.height * scaleY).floor().clamp(1, p.originalHeight - origY));

      finalImage = img.copyCrop(finalImage, x: origX, y: origY, width: origW, height: origH);
    }

    // 4. IN ORIGINALDATEI überschreiben
    final outBytes = Uint8List.fromList(img.encodeJpg(finalImage, quality: 95));
    File(p.originalPath).writeAsBytesSync(outBytes);

    return const _SaveResult(success: true);
  } catch (e) {
    return _SaveResult(success: false, error: e.toString());
  }
}

/// Crop-Handle Typen
enum _DragType { topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right }
class _DragHandle { final _DragType type; final Offset pos; _DragHandle(this.type, this.pos); }

/// CustomPainter für professionellen Crop-Overlay
class _CropPainter extends CustomPainter {
  final Rect cropRect;
  final bool isActive;
  final double handleSize;
  final Brightness brightness;

  _CropPainter({
    required this.cropRect,
    required this.isActive,
    required this.handleSize,
    required this.brightness,
  }) : super();

  @override
  void paint(Canvas canvas, Size size) {
    // Dunkel-Overlay außerhalb Crop
    final darkPaint = Paint()..style = PaintingStyle.fill
      ..color = brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, cropRect.top), darkPaint);
    canvas.drawRect(Rect.fromLTWH(0, cropRect.bottom, size.width, size.height - cropRect.bottom), darkPaint);
    canvas.drawRect(Rect.fromLTWH(0, cropRect.top, cropRect.left, cropRect.height), darkPaint);
    canvas.drawRect(Rect.fromLTWH(cropRect.right, cropRect.top, size.width - cropRect.right, cropRect.height), darkPaint);

    // Crop-Rahmen
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(cropRect, borderPaint);

    // Gitternetz (Drittel-Regel)
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.5);
    final w3 = cropRect.width / 3, h3 = cropRect.height / 3;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(Offset(cropRect.left + i * w3, cropRect.top), Offset(cropRect.left + i * w3, cropRect.bottom), gridPaint);
      canvas.drawLine(Offset(cropRect.left, cropRect.top + i * h3), Offset(cropRect.right, cropRect.top + i * h3), gridPaint);
    }

    // Handles (Ecken + Mitte Kanten)
    final handlePaint = Paint()..color = Colors.white ..style = PaintingStyle.fill;
    final handleBorder = Paint()..color = Colors.cyan ..style = PaintingStyle.stroke ..strokeWidth = 2;
    final handles = [
      cropRect.topLeft, cropRect.topRight, cropRect.bottomLeft, cropRect.bottomRight,
      Offset(cropRect.center.dx, cropRect.top), Offset(cropRect.center.dx, cropRect.bottom),
      Offset(cropRect.left, cropRect.center.dy), Offset(cropRect.right, cropRect.center.dy),
    ];
    for (final p in handles) {
      final r = Rect.fromCenter(center: p, width: handleSize, height: handleSize);
      canvas.drawRect(r, handlePaint);
      canvas.drawRect(r, handleBorder);
    }
  }

  @override
  bool shouldRepaint(_CropPainter o) => o.cropRect != cropRect || o.isActive != isActive;
}

// ═══════════════════════════════════════════════════════════════════════════
// BildVollbildScreen – wiederverwendbarer Vollbild-Betrachter mit Bearbeiten-
// Button. Verwaltet seinen eigenen Version-Counter, damit Image.file nach
// einem Speichern automatisch neu geladen wird.
// ═══════════════════════════════════════════════════════════════════════════

/// Ergebnis, das nach einer Bildbearbeitung an den Aufrufer zurückgegeben wird.
class BildVollbildResult {
  const BildVollbildResult();
}

class BildVollbildScreen extends StatefulWidget {
  final String bildPfad;

  /// Wird nach einer erfolgreichen Bearbeitung aufgerufen, damit der Aufrufer
  /// z. B. seine Thumbnail-Liste aktualisieren kann.
  final VoidCallback? onImageEdited;

  const BildVollbildScreen({
    super.key,
    required this.bildPfad,
    this.onImageEdited,
  });

  @override
  State<BildVollbildScreen> createState() => _BildVollbildScreenState();
}

class _BildVollbildScreenState extends State<BildVollbildScreen> {
  /// Erhöhen erzwingt Flutter ein neues Widget (neuer Key → Cache verworfen).
  int _version = 0;

  Future<void> _oeffneEditor() async {
    if (widget.bildPfad.startsWith('http')) return;
    final file = File(widget.bildPfad);
    if (!file.existsSync()) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditScreen(
          imageDataPath: widget.bildPfad,
          originalPath: widget.bildPfad,
        ),
      ),
    );

    if (result != null && mounted) {
      // Eigenen Counter erhöhen → Vollbild-Bild wird neu geladen
      setState(() => _version++);
      // Eltern-Widget informieren (z. B. für Thumbnail-Update)
      widget.onImageEdited?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool istDunkel = Theme.of(context).brightness == Brightness.dark;
    final Color kreisFarbe = istDunkel ? Colors.black : Colors.white;
    final Color symbolFarbe = istDunkel ? Colors.white : Colors.black;

    Widget bild;
    if (widget.bildPfad.startsWith('http')) {
      bild = Image.network(
        widget.bildPfad,
        fit: BoxFit.contain,
        key: ValueKey('${widget.bildPfad}_$_version'),
      );
    } else {
      bild = Image.file(
        File(widget.bildPfad),
        fit: BoxFit.contain,
        key: ValueKey('${widget.bildPfad}_$_version'),
        gaplessPlayback: true,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: istDunkel ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: istDunkel ? Colors.black : Colors.white,
        body: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: bild,
              ),
            ),
            // Schließen (links)
            Positioned(
              top: 0, left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: kreisFarbe,
                    elevation: 3,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.close, size: 28, color: symbolFarbe),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bearbeiten (rechts) – nur für lokale Dateien
            if (!widget.bildPfad.startsWith('http'))
              Positioned(
                top: 0, right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: kreisFarbe,
                      elevation: 3,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _oeffneEditor,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(Icons.edit, size: 24, color: symbolFarbe),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}