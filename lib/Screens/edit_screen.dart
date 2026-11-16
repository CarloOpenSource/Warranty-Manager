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

  static Future<String?> exportAllSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const String prefix = 'edit_settings_';
      final settings = <String, dynamic>{};
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix)) settings[key] = prefs.getString(key);
      }
      if (settings.isEmpty) return null;
      return jsonEncode(settings);
    } catch (e) {
      debugPrint('exportAllSettings FEHLER: $e');
      return null;
    }
  }

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
      debugPrint('importSettings FEHLER: $e');
    }
  }
}

class _EditScreenState extends State<EditScreen> with WidgetsBindingObserver {
  bool _istDunkel = true;

  // ── Crop ──────────────────────────────────────────────────────────────────
  Rect _cropRect = Rect.zero;
  bool _isCropMode = false;
  _DragHandle? _activeHandle;

  // ── Farbwerte ─────────────────────────────────────────────────────────────
  double _brightness = 1.0;
  double _contrast   = 1.0;
  double _saturation = 1.0;
  // Rotation existiert nicht mehr als State – wird direkt in _baseDisplayImage
  // eingebrannt.

  // ── Zustand ───────────────────────────────────────────────────────────────
  bool _isLoading  = true;
  bool _isSaving   = false;
  bool _hasChanges = false;

  // ── Display-Puffer ────────────────────────────────────────────────────────
  Uint8List? _displayBytes;
  int _displayWidth  = 0;
  int _displayHeight = 0;

  // ── Arbeitsbilder ─────────────────────────────────────────────────────────
  img.Image? _baseDisplayImage;
  img.Image? _originalBackup;

  // ── Layout-Cache ──────────────────────────────────────────────────────────
  // Wird im LayoutBuilder des Bildbereichs befüllt.
  // renderScale: wie viele Bildschirm-Pixel entsprechen einem Bild-Pixel
  double _renderScale     = 1.0;
  // Offset des Bildes im Vollbild-Container
  double _imageOffsetX    = 0.0;
  double _imageOffsetY    = 0.0;

  // ── Zoom ──────────────────────────────────────────────────────────────────
  late final TransformationController _zoomController;

  // ── Bottom-Sheet ──────────────────────────────────────────────────────────
  // Wir verwenden einen einfachen AnimationController-gesteuerten
  // Slide-In/Out statt DraggableScrollableSheet, da das zuverlässiger mit
  // bottomNavigationBar und Keyboard interagiert.
  // _sheetVisible: ob das Sheet sichtbar (nicht ganz eingezogen) ist
  bool _sheetVisible = true;

  // ── Debounce ──────────────────────────────────────────────────────────────
  Timer? _debounceTimer;
  bool   _pendingUpdate = false;

  // ── Konstanten ────────────────────────────────────────────────────────────
  static const String   _prefsPrefix         = 'edit_settings_';
  static const int      _maxDisplayDimension = 1024;
  static const double   _handleSize          = 28.0;
  static const Duration _debounceDelay       = Duration(milliseconds: 80);
  // Randabstand für Crop-Vorschau (in Bildschirm-Pixeln)
  // Groß genug, damit das Bild nie den Bildschirmrand berührt und
  // Android-Gesten-Bereiche nicht versehentlich getriggert werden.
  static const double _cropPreviewMargin = 40.0;

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    WidgetsBinding.instance.addObserver(this);
    _loadImage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark != _istDunkel) _istDunkel = dark;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _zoomController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _t(String key) {
    final s = Provider.of<SettingsProvider>(context, listen: false);
    return getText(s.languageCode, key);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BILD LADEN
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadImage() async {
    setState(() => _isLoading = true);
    try {
      final file = File(widget.imageDataPath);
      if (!await file.exists()) {
        throw FileSystemException('Datei nicht gefunden', widget.imageDataPath);
      }
      final bytes   = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Bild nicht dekodierbar');

      img.Image work = decoded;
      if (decoded.width > _maxDisplayDimension ||
          decoded.height > _maxDisplayDimension) {
        final s = math.min(
          _maxDisplayDimension / decoded.width,
          _maxDisplayDimension / decoded.height,
        );
        work = img.copyResize(decoded,
          width:  (decoded.width  * s).round(),
          height: (decoded.height * s).round(),
        );
      }

      _originalBackup   = img.Image.from(work);
      _baseDisplayImage = work;

      await _loadSettingsForImage();

      _cropRect = Rect.fromLTWH(
        0, 0,
        _baseDisplayImage!.width.toDouble(),
        _baseDisplayImage!.height.toDouble(),
      );
      _rebuildDisplay();
    } catch (e, stack) {
      debugPrint('_loadImage FEHLER: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler beim Laden: $e')));
        Navigator.pop(context);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EINSTELLUNGEN
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadSettingsForImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = '$_prefsPrefix${widget.imageDataPath.hashCode}';
      final str   = prefs.getString(key);
      if (str == null) return;
      final data = jsonDecode(str) as Map<String, dynamic>;
      _brightness = (data['brightness'] as num?)?.toDouble() ?? 1.0;
      _contrast   = (data['contrast']   as num?)?.toDouble() ?? 1.0;
      _saturation = (data['saturation'] as num?)?.toDouble() ?? 1.0;
      // Geladene Einstellungen zählen NICHT als Änderungen
      _hasChanges = false;
    } catch (e) {
      debugPrint('_loadSettingsForImage FEHLER: $e');
    }
  }

  Future<void> _saveSettingsForImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = '$_prefsPrefix${widget.imageDataPath.hashCode}';
      await prefs.setString(key, jsonEncode({
        'brightness': 1.0,
        'contrast':   1.0,
        'saturation': 1.0,
        'timestamp':  DateTime.now().toIso8601String(),
      }));
    } catch (e) {
      debugPrint('_saveSettingsForImage FEHLER: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ANZEIGE AUFBAUEN
  // ─────────────────────────────────────────────────────────────────────────

  void _rebuildDisplay() {
    if (_baseDisplayImage == null) return;
    final out = img.adjustColor(
      img.Image.from(_baseDisplayImage!),
      brightness: _brightness,
      contrast:   _contrast,
      saturation: _saturation,
    );
    _displayBytes  = Uint8List.fromList(img.encodeJpg(out, quality: 92));
    _displayWidth  = out.width;
    _displayHeight = out.height;
  }

  void _scheduleDisplayUpdate() {
    _pendingUpdate = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      if (_pendingUpdate && mounted) {
        _pendingUpdate = false;
        _rebuildDisplay();
        _hasChanges = true;
        setState(() {});
      }
    });
  }

  void _onBrightnessChanged(double v) { _brightness = v; _scheduleDisplayUpdate(); }
  void _onContrastChanged(double v)   { _contrast   = v; _scheduleDisplayUpdate(); }
  void _onSaturationChanged(double v) { _saturation = v; _scheduleDisplayUpdate(); }

  // ─────────────────────────────────────────────────────────────────────────
  // ROTATION – PERMANENT EINBRENNEN
  // ─────────────────────────────────────────────────────────────────────────

  void _applyRotation(int angleDeg) {
    if (_baseDisplayImage == null || _isSaving) return;
    _debounceTimer?.cancel();
    _pendingUpdate = false;
    _baseDisplayImage = img.copyRotate(_baseDisplayImage!, angle: angleDeg);
    _cropRect = Rect.fromLTWH(
      0, 0,
      _baseDisplayImage!.width.toDouble(),
      _baseDisplayImage!.height.toDouble(),
    );
    _hasChanges = true;
    _rebuildDisplay();
    if (mounted) setState(() {});
  }

  void _rotateLeft()  => _applyRotation(90);
  void _rotateRight() => _applyRotation(-90);

  // ─────────────────────────────────────────────────────────────────────────
  // CROP
  // ─────────────────────────────────────────────────────────────────────────

  void _enterCropMode() {
    // Im Crop-Mode Zoom auf Identity zurücksetzen, damit _renderScale
    // und die Bild-Offsets exakt stimmen und die Handles korrekt sitzen.
    _zoomController.value = Matrix4.identity();
    setState(() => _isCropMode = true);
  }

  void _exitCropMode() {
    _applyCropToBaseImage();
    setState(() {
      _isCropMode   = false;
      _activeHandle = null;
    });
  }

  void _toggleCropMode() {
    if (!_isCropMode) {
      _enterCropMode();
    } else {
      _exitCropMode();
    }
  }

  void _applyCropToBaseImage() {
    if (_baseDisplayImage == null) return;
    final bw = _baseDisplayImage!.width;
    final bh = _baseDisplayImage!.height;
    final x  = _cropRect.left.floor().clamp(0, bw - 1);
    final y  = _cropRect.top.floor().clamp(0, bh - 1);
    final w  = _cropRect.width.floor().clamp(1, bw - x);
    final h  = _cropRect.height.floor().clamp(1, bh - y);
    if (!(x == 0 && y == 0 && w == bw && h == bh)) {
      _baseDisplayImage = img.copyCrop(_baseDisplayImage!,
        x: x, y: y, width: w, height: h,
      );
      _hasChanges = true;
    }
    _cropRect = Rect.fromLTWH(
      0, 0,
      _baseDisplayImage!.width.toDouble(),
      _baseDisplayImage!.height.toDouble(),
    );
    _rebuildDisplay();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ZOOM  (nur im Normal-Mode, nicht im Crop-Mode)
  // ─────────────────────────────────────────────────────────────────────────

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
  }

  /// Setzt den Zoom-Faktor des InteractiveViewers programmatisch.
  /// Der InteractiveViewer füllt den gesamten verfügbaren Bildbereich.
  /// Eine einfache Skalierung um den Mittelpunkt reicht aus.
  void _applyZoom(double targetScale) {
    // Matrix: Identity skaliert → Bild wird kleiner/größer, bleibt zentriert
    // weil der InteractiveViewer den ganzen Bereich abdeckt und
    // BoxFit.contain das Bild von Natur aus zentriert.
    final m = Matrix4.diagonal3Values(targetScale, targetScale, 1.0);
    _zoomController.value = m;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESET
  // ─────────────────────────────────────────────────────────────────────────

  void _resetSlidersOnly() {
    _debounceTimer?.cancel();
    _pendingUpdate = false;
    setState(() {
      _brightness = 1.0;
      _contrast   = 1.0;
      _saturation = 1.0;
    });
    _rebuildDisplay();
    _hasChanges = true;
    if (mounted) setState(() {});
  }

  void _resetToOriginal() {
    if (_originalBackup == null) return;
    _debounceTimer?.cancel();
    _pendingUpdate = false;
    _baseDisplayImage = img.Image.from(_originalBackup!);
    _cropRect = Rect.fromLTWH(
      0, 0,
      _baseDisplayImage!.width.toDouble(),
      _baseDisplayImage!.height.toDouble(),
    );
    _rebuildDisplay();
    _resetZoom();
    setState(() {
      _brightness   = 1.0;
      _contrast     = 1.0;
      _saturation   = 1.0;
      _isCropMode   = false;
      _activeHandle = null;
      // Reset auf Original = keine ungespeicherten Änderungen
      _hasChanges   = false;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SPEICHERN
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _saveAndExit() async {
    if (_baseDisplayImage == null || _isSaving) return;
    if (_isCropMode) {
      _applyCropToBaseImage();
      setState(() { _isCropMode = false; _activeHandle = null; });
    }
    setState(() => _isSaving = true);
    try {
      final baseBytes = Uint8List.fromList(
        img.encodeJpg(_baseDisplayImage!, quality: 100),
      );
      final params = _SaveParams(
        baseImageBytes: baseBytes,
        brightness:     _brightness,
        contrast:       _contrast,
        saturation:     _saturation,
        originalPath:   widget.originalPath,
      );
      _SaveResult result;
      try {
        result = await Isolate.run(() => _saveInBackground(params))
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('Isolate-Fallback: $e');
        result = _saveInBackground(params);
      }
      if (mounted) {
        if (result.success) {
          await _saveSettingsForImage();
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Bild gespeichert!')),
          );
          // ignore: use_build_context_synchronously
          Navigator.pop(context, widget.originalPath);
        } else {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Fehler: ${result.error}')),
          );
          setState(() => _isSaving = false);
        }
      }
    } catch (e) {
      debugPrint('_saveAndExit FEHLER: $e');
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CROP-DRAG
  // ─────────────────────────────────────────────────────────────────────────

  void _onPanStart(PointerDownEvent d) {
    if (!_isCropMode) return;
    // Pointer-Position relativ zum Bild-Offset umrechnen
    final localInImage = Offset(
      d.localPosition.dx - _imageOffsetX,
      d.localPosition.dy - _imageOffsetY,
    );
    _activeHandle = _hitTestHandle(localInImage);
  }

  void _onPanUpdate(PointerMoveEvent d) {
    if (!_isCropMode || _activeHandle == null) return;
    final s = _renderScale > 0 ? _renderScale : 1.0;
    // Pointer relativ zum Bild-Offset → in Bildpixel-Koordinaten
    final localInImage = Offset(
      d.localPosition.dx - _imageOffsetX,
      d.localPosition.dy - _imageOffsetY,
    );
    final imgPos = Offset(localInImage.dx / s, localInImage.dy / s);
    setState(() {
      _cropRect = _resizeRect(_cropRect, _activeHandle!.type, imgPos);
      _hasChanges = true;
    });
  }

  void _onPanEnd(_) => _activeHandle = null;

  _DragHandle? _hitTestHandle(Offset localInImage) {
    if (_renderScale <= 0) return null;
    final s = _renderScale;
    final r = _cropRect;
    final handles = <({_DragType type, Offset pos})>[
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
      if (Rect.fromCenter(center: h.pos, width: _handleSize, height: _handleSize)
              .contains(localInImage)) {
        return _DragHandle(h.type, h.pos);
      }
    }
    return null;
  }

  Rect _resizeRect(Rect r, _DragType t, Offset p) {
    double l = r.left, top = r.top, ri = r.right, b = r.bottom;
    switch (t) {
      case _DragType.topLeft:     l = p.dx; top = p.dy; break;
      case _DragType.topRight:    ri = p.dx; top = p.dy; break;
      case _DragType.bottomLeft:  l = p.dx; b = p.dy;   break;
      case _DragType.bottomRight: ri = p.dx; b = p.dy;  break;
      case _DragType.top:    top = p.dy; break;
      case _DragType.bottom: b   = p.dy; break;
      case _DragType.left:   l   = p.dx; break;
      case _DragType.right:  ri  = p.dx; break;
    }
    // Crop-Rect darf nicht über den Bildschirmrand hinausgehen.
    // Randabstand = _cropMarginPx (in Bild-Pixeln), mindestens 20px.
    final m = _cropMarginPx().clamp(20.0, double.infinity);
    final maxL = _displayWidth.toDouble()  - m;
    final maxT = _displayHeight.toDouble() - m;
    l   = l.clamp(m, maxL);
    ri  = ri.clamp(l + 20.0, _displayWidth.toDouble());
    top = top.clamp(m, maxT);
    b   = b.clamp(top + 20.0, _displayHeight.toDouble());
    return Rect.fromLTRB(l, top, ri, b);
  }

  /// Berechnet den Randabstand für Crop-Handles in Bild-Pixeln.
  /// Basiert auf 24 Screen-Pixeln, skaliert mit _renderScale.
  double _cropMarginPx() {
    final s = _renderScale > 0 ? _renderScale : 1.0;
    return (24.0 / s).clamp(20.0, double.infinity);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ZURÜCK
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    // Nur fragen, wenn ECHTE Änderungen vorliegen
    if (!_hasChanges) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_t('discard_changes_title')),
        content: Text(_t('discard_changes_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(_t('discard')),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    _istDunkel = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final ok = await _onWillPop();
          if (ok && mounted) {
            // ignore: use_build_context_synchronously
            Navigator.pop(context);
          }
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _istDunkel ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: _istDunkel ? Colors.black : Colors.white,
          // Kein bottomNavigationBar – das Sheet liegt direkt im Stack
          body: Column(
            children: [
              // ── Bildbereich ──────────────────────────────────────────
              Expanded(
                child: Stack(
                  children: [
                    // Vollflächiges Bild mit Zoom/Pan
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Positioned.fill(
                        child: (_displayBytes == null ||
                                _displayWidth == 0 ||
                                _displayHeight == 0)
                            ? const SizedBox.shrink()
                            : LayoutBuilder(builder: (ctx, constraints) {
                                final imgW  = _displayWidth.toDouble();
                                final imgH  = _displayHeight.toDouble();

                                // Berechne Skalierung MIT Randabstand für Crop-Modus
                                // Damit das Bild nie den Bildschirmrand berührt
                                final pad = _isCropMode ? _cropPreviewMargin : 0.0;
                                final scale = math.min(
                                  (constraints.maxWidth  - pad * 2) / imgW,
                                  (constraints.maxHeight - pad * 2) / imgH,
                                );
                                final fitW = imgW * scale;
                                final fitH = imgH * scale;
                                final offX = (constraints.maxWidth  - fitW) / 2;
                                final offY = (constraints.maxHeight - fitH) / 2;

                                // Layout-Werte für Crop-Koordinaten cachen
                                _renderScale  = scale;
                                _imageOffsetX = offX;
                                _imageOffsetY = offY;

                                return Stack(children: [
                                  // ── Schwarzer Hintergrund ──
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: _istDunkel
                                          ? Colors.black
                                          : Colors.grey.shade200,
                                    ),
                                  ),

                                  // ── Bild mit Zoom/Pan ──
                                  // Im Crop-Mode: panEnabled=false, damit
                                  // Drag-Gesten zum Crop-Overlay gehen.
                                  // Im Normal-Mode: voller Zoom/Pan.
                                  Positioned(
                                    left: offX, top: offY,
                                    width: fitW, height: fitH,
                                    child: _isCropMode
                                        // Im Crop-Mode: kein InteractiveViewer,
                                        // damit Pointer-Events ans Crop-Overlay
                                        // weitergegeben werden
                                        ? Image.memory(
                                            _displayBytes!,
                                            fit: BoxFit.fill,
                                            gaplessPlayback: true,
                                          )
                                        : InteractiveViewer(
                                            panEnabled: true,
                                            minScale: 0.25,
                                            maxScale: 4.0,
                                            transformationController:
                                                _zoomController,
                                            child: Image.memory(
                                              _displayBytes!,
                                              fit: BoxFit.fill,
                                              gaplessPlayback: true,
                                            ),
                                          ),
                                  ),

                                  // ── Crop-Overlay ──
                                  // Das Listener-Widget spannt den gesamten
                                  // Stack auf, um Pointer-Events zu fangen.
                                  // Die Koordinaten werden relativ zum
                                  // Bild-Offset umgerechnet (in _onPanStart/Update).
                                  if (_isCropMode)
                                    Positioned.fill(
                                      child: Listener(
                                        onPointerDown:  _onPanStart,
                                        onPointerMove:  _onPanUpdate,
                                        onPointerUp:    _onPanEnd,
                                        behavior: HitTestBehavior.translucent,
                                        child: CustomPaint(
                                          painter: _CropPainter(
                                            // Crop-Rect in Screen-Koordinaten
                                            // (relativ zum Stack, nicht zum Bild):
                                            cropRect: Rect.fromLTWH(
                                              offX + _cropRect.left   * scale,
                                              offY + _cropRect.top    * scale,
                                              _cropRect.width  * scale,
                                              _cropRect.height * scale,
                                            ),
                                            // Gesamter Bereich für Abdunkelung
                                            fullSize: Size(
                                              constraints.maxWidth,
                                              constraints.maxHeight,
                                            ),
                                            handleSize: _handleSize,
                                            isDark: _istDunkel,
                                          ),
                                        ),
                                      ),
                                    ),
                                ]);
                              }),
                      ),

                    // ── Schließen (links oben) ──────────────────────────
                    Positioned(
                      top: 0, left: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: _circleButton(
                            color: _istDunkel
                                ? Colors.grey.shade800.withValues(alpha: 0.85)
                                : Colors.grey.shade100.withValues(alpha: 0.85),
                            onTap: _isSaving ? null : () async {
                              final ok = await _onWillPop();
                              if (ok && mounted) {
                                // ignore: use_build_context_synchronously
                                Navigator.pop(context);
                              }
                            },
                            child: Icon(
                              Icons.close, size: 26,
                              color: _istDunkel ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Speichern (rechts oben) ─────────────────────────
                    Positioned(
                      top: 0, right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: _circleButton(
                            color: _istDunkel
                                ? Colors.green.shade700
                                : Colors.green.shade600,
                            onTap: _isSaving ? null : _saveAndExit,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 48, height: 48,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation(
                                            Colors.white),
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check,
                                    size: 26, color: Colors.white),
                          ),
                        ),
                      ),
                    ),

                    // ── Crop-Toggle (unten mitte, über dem Sheet) ───────
                    Positioned(
                      bottom: 12, left: 0, right: 0,
                      child: Center(
                        child: Material(
                          color: _isCropMode
                              ? Colors.blueAccent
                              : (_istDunkel
                                  ? Colors.grey.shade800.withValues(alpha: 0.9)
                                  : Colors.white.withValues(alpha: 0.9)),
                          elevation: 4,
                          borderRadius: BorderRadius.circular(24),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: _isSaving ? null : _toggleCropMode,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isCropMode
                                        ? Icons.crop_free
                                        : Icons.crop_free_outlined,
                                    size: 20,
                                    color: _isCropMode
                                        ? Colors.white
                                        : (_istDunkel
                                            ? Colors.white
                                            : Colors.black87),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isCropMode
                                        ? _t('crop_done')
                                        : _t('crop'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _isCropMode
                                          ? Colors.white
                                          : (_istDunkel
                                              ? Colors.white
                                              : Colors.black87),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Sheet ────────────────────────────────────────────────
              if (!_isLoading)
                _buildSheet(settings),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHEET  (kein DraggableScrollableSheet – einfacher AnimatedContainer)
  // ─────────────────────────────────────────────────────────────────────────
  // Das Sheet ist ein einfacher Container am unteren Bildschirmrand.
  // Per GestureDetector (vertikaler Drag) kann der Nutzer es einziehen
  // oder ausfahren. Wenn _sheetVisible == false, zeigt es nur den
  // Anfasser (~24px); alle Buttons sind dann ausgegraut/disabled.
  // ─────────────────────────────────────────────────────────────────────────

  // Mindesthöhe wenn eingezogen (nur Anfasser)
  static const double _sheetCollapsedH = 24.0;

  // Volle Höhe des Sheets (Anfasser + Inhalt)
  // Wird erst nach dem ersten Build korrekt befüllt; vorher Schätzwert.
  double _sheetExpandedH = 180.0;

  // Aktuelle Höhe (wird per Drag verändert)
  double _sheetCurrentH  = 180.0;
  bool   _sheetMeasured  = false;

  // Drag-Startpunkt für vertikales Ziehen
  double? _dragStartY;
  double? _dragStartH;

  void _onSheetDragStart(DragStartDetails d) {
    _dragStartY = d.globalPosition.dy;
    _dragStartH = _sheetCurrentH;
  }

  void _onSheetDragUpdate(DragUpdateDetails d) {
    if (_dragStartY == null || _dragStartH == null) return;
    final delta = _dragStartY! - d.globalPosition.dy; // positiv = hochziehen
    final newH = (_dragStartH! + delta)
        .clamp(_sheetCollapsedH, _sheetExpandedH);
    setState(() {
      _sheetCurrentH = newH;
      _sheetVisible  = newH > _sheetCollapsedH + 10;
    });
  }

  void _onSheetDragEnd(DragEndDetails d) {
    // Snap: unter 50% → zuziehen, über 50% → ausfahren
    final half = (_sheetExpandedH + _sheetCollapsedH) / 2;
    setState(() {
      if (_sheetCurrentH < half) {
        _sheetCurrentH = _sheetCollapsedH;
        _sheetVisible  = false;
      } else {
        _sheetCurrentH = _sheetExpandedH;
        _sheetVisible  = true;
      }
    });
    _dragStartY = null;
    _dragStartH = null;
  }

  Widget _buildSheet(SettingsProvider settings) {
    // Bestimme ob Buttons aktiv sind:
    // ausgegraut wenn Sheet eingezogen ODER Speichern läuft ODER Crop-Mode
    final btnsActive = _sheetVisible && !_isSaving && !_isCropMode;
    // SafeArea-Bottom: Platz für Navigationsleiste / Gesten-Zone
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      onVerticalDragStart:  _onSheetDragStart,
      onVerticalDragUpdate: _onSheetDragUpdate,
      onVerticalDragEnd:    _onSheetDragEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        // Extra Höhe für SafeArea-Bottom einrechnen
        height: _sheetCurrentH + bottomPad,
        decoration: BoxDecoration(
          color: _istDunkel ? const Color(0xFF1C1C1E) : Colors.white,
          border: Border(
            top: BorderSide(
              color: _istDunkel ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Anfasser ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: _istDunkel
                        ? Colors.grey.shade600
                        : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // ── Inhalt (MeasureSize für erste Höhenermittlung) ─────────
            if (_sheetVisible)
              Flexible(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: MeasureSize(
                    onChange: (size) {
                      if (!_sheetMeasured) {
                        final fullH = size.height + 20 + _sheetCollapsedH;
                        setState(() {
                          _sheetExpandedH  = fullH.clamp(120.0, 260.0);
                          _sheetCurrentH   = _sheetExpandedH;
                          _sheetMeasured   = true;
                        });
                      }
                    },
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(12, 0, 12, 8 + bottomPad),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── FARBE: alle 3 Slider in einer Zeile ──────────────
                          _sectionHeader(_t('color')),
                          Row(
                            children: [
                              Expanded(child: _sliderCompact(
                                'brightness', Icons.wb_sunny_outlined,
                                _brightness, _onBrightnessChanged, settings,
                                active: btnsActive,
                              )),
                              Expanded(child: _sliderCompact(
                                'contrast', Icons.contrast_outlined,
                                _contrast, _onContrastChanged, settings,
                                active: btnsActive,
                              )),
                              Expanded(child: _sliderCompact(
                                'saturation', Icons.color_lens_outlined,
                                _saturation, _onSaturationChanged, settings,
                                active: btnsActive,
                              )),
                            ],
                          ),
                          _divider(),

                          // ── AKTIONEN: Drehen, Zoom, Reset in einer Zeile ─────
                          _sectionHeader(_t('actions')),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _iconLabelBtn(
                                icon: Icons.rotate_left,
                                label: _t('rotate_left'),
                                active: btnsActive,
                                onTap: _rotateLeft,
                              ),
                              _iconLabelBtn(
                                icon: Icons.rotate_right,
                                label: _t('rotate_right'),
                                active: btnsActive,
                                onTap: _rotateRight,
                              ),
                              _iconLabelBtn(
                                icon: Icons.fit_screen,
                                label: _t('fit_to_screen'),
                                active: btnsActive,
                                onTap: () => _applyZoom(1.0),
                              ),
                              _iconLabelBtn(
                                icon: Icons.tune_outlined,
                                label: _t('reset_all'),
                                color: Colors.orangeAccent,
                                active: btnsActive,
                                onTap: _resetSlidersOnly,
                              ),
                              _iconLabelBtn(
                                icon: Icons.restore,
                                label: _t('reset_to_original'),
                                color: Colors.redAccent,
                                active: btnsActive,
                                onTap: _resetToOriginal,
                              ),
                            ],
                          ),
                        ],
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

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _istDunkel ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _divider() => SizedBox(
    height: 24,
    child: Center(
      child: Container(
        height: 1,
        width: double.infinity,
        color: _istDunkel ? Colors.grey.shade700 : Colors.grey.shade300,
      ),
    ),
  );

  /// Kompakter Slider für die 3-Spalten-Farb-Zeile:
  /// Icon + kurzer Label oben, Slider darunter – passt in Expanded.
  Widget _sliderCompact(
    String key,
    IconData icon,
    double value,
    void Function(double) onChange,
    SettingsProvider s, {
    required bool active,
  }) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13,
            color: active
                ? (_istDunkel ? Colors.white60 : Colors.grey.shade600)
                : Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(
          _t(key),
          style: TextStyle(
            fontSize: 10,
            color: active
                ? (_istDunkel ? Colors.white70 : Colors.black87)
                : Colors.grey.shade500,
          ),
        ),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Slider(
          value: value,
          min: 0.0, max: 2.0, divisions: 100,
          label: value.toStringAsFixed(1),
          onChanged: active ? onChange : null,
          activeColor: active ? s.appButtonColor : Colors.grey.shade500,
          inactiveColor: Colors.grey.shade600,
        ),
      ),
    ]);
  }

  /// Icon + kleiner Label-Text, vertikal gestapelt – für Aktions-Zeile.
  Widget _iconLabelBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    Color? color,
  }) {
    final col = active
        ? (color ?? (_istDunkel ? Colors.white70 : Colors.black87))
        : Colors.grey.shade500;
    return InkWell(
      onTap: active ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22, color: col),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: col),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ]),
      ),
    );
  }

  Widget _circleButton({
    required Color color,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return Material(
      color: color,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48,
            child: Center(child: child)),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MeasureSize – misst einmalig die Größe eines Widgets
// ════════════════════════════════════════════════════════════════════════════

typedef OnWidgetSizeChange = void Function(Size size);

class MeasureSize extends StatefulWidget {
  final Widget child;
  final OnWidgetSizeChange onChange;

  const MeasureSize({
    super.key,
    required this.onChange,
    required this.child,
  });

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        widget.onChange(box.size);
      }
    });
    return widget.child;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ISOLATE
// ════════════════════════════════════════════════════════════════════════════

class _SaveParams {
  final Uint8List baseImageBytes;
  final double    brightness;
  final double    contrast;
  final double    saturation;
  final String    originalPath;

  const _SaveParams({
    required this.baseImageBytes,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.originalPath,
  });
}

class _SaveResult {
  final bool    success;
  final String? error;
  const _SaveResult({required this.success, this.error});
}

_SaveResult _saveInBackground(_SaveParams p) {
  try {
    final img.Image? base = img.decodeImage(p.baseImageBytes);
    if (base == null) {
      return const _SaveResult(success: false, error: 'Bild nicht decodierbar');
    }
    final out = img.adjustColor(base,
      brightness: p.brightness,
      contrast:   p.contrast,
      saturation: p.saturation,
    );
    final bytes = Uint8List.fromList(img.encodeJpg(out, quality: 95));
    File(p.originalPath).writeAsBytesSync(bytes);
    return const _SaveResult(success: true);
  } catch (e) {
    return _SaveResult(success: false, error: e.toString());
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CROP-PAINTER
// ════════════════════════════════════════════════════════════════════════════

enum _DragType {
  topLeft, topRight, bottomLeft, bottomRight,
  top, bottom, left, right,
}

class _DragHandle {
  final _DragType type;
  final Offset    pos;
  _DragHandle(this.type, this.pos);
}

class _CropPainter extends CustomPainter {
  final Rect   cropRect;   // in Screen-Koordinaten (inkl. Bild-Offset)
  final Size   fullSize;   // Gesamtgröße des Painter-Bereichs
  final double handleSize;
  final bool   isDark;

  _CropPainter({
    required this.cropRect,
    required this.fullSize,
    required this.handleSize,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withValues(alpha: isDark ? 0.6 : 0.5);

    final w = fullSize.width;
    final h = fullSize.height;

    // Abdunkeln außerhalb des Crop-Rects
    canvas.drawRect(Rect.fromLTWH(0, 0, w, cropRect.top), dim);
    canvas.drawRect(
        Rect.fromLTWH(0, cropRect.bottom, w, h - cropRect.bottom), dim);
    canvas.drawRect(
        Rect.fromLTWH(0, cropRect.top, cropRect.left, cropRect.height), dim);
    canvas.drawRect(
        Rect.fromLTWH(
            cropRect.right, cropRect.top,
            w - cropRect.right, cropRect.height),
        dim);

    // Rahmen
    canvas.drawRect(
      cropRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    // Drittelregel
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withValues(alpha: 0.5);
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(cropRect.left + cropRect.width  / 3 * i, cropRect.top),
        Offset(cropRect.left + cropRect.width  / 3 * i, cropRect.bottom),
        grid);
      canvas.drawLine(
        Offset(cropRect.left, cropRect.top + cropRect.height / 3 * i),
        Offset(cropRect.right, cropRect.top + cropRect.height / 3 * i),
        grid);
    }

    // Handles
    final fill   = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final border = Paint()..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke..strokeWidth = 2;
    for (final p in [
      cropRect.topLeft, cropRect.topRight,
      cropRect.bottomLeft, cropRect.bottomRight,
      Offset(cropRect.center.dx, cropRect.top),
      Offset(cropRect.center.dx, cropRect.bottom),
      Offset(cropRect.left,  cropRect.center.dy),
      Offset(cropRect.right, cropRect.center.dy),
    ]) {
      final r = Rect.fromCenter(center: p, width: handleSize, height: handleSize);
      canvas.drawRect(r, fill);
      canvas.drawRect(r, border);
    }
  }

  @override
  bool shouldRepaint(_CropPainter o) =>
      o.cropRect != cropRect || o.fullSize != fullSize;
}

// ════════════════════════════════════════════════════════════════════════════
// BildVollbildScreen
// ════════════════════════════════════════════════════════════════════════════

class BildVollbildResult {
  const BildVollbildResult();
}

class BildVollbildScreen extends StatefulWidget {
  final String bildPfad;
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
  int _version = 0;

  void _evictImageCache(String path) {
    try {
      if (!path.startsWith('http')) {
        final f = File(path);
        if (f.existsSync()) {
          PaintingBinding.instance.imageCache.evict(FileImage(f));
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
      } else {
        PaintingBinding.instance.imageCache.evict(NetworkImage(path));
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
    } catch (e) {
      debugPrint('Cache evict: $e');
      try { PaintingBinding.instance.imageCache.clear(); } catch (_) {}
    }
  }

  Future<void> _oeffneEditor() async {
    if (widget.bildPfad.startsWith('http')) return;
    if (!File(widget.bildPfad).existsSync()) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditScreen(
          imageDataPath: widget.bildPfad,
          originalPath:  widget.bildPfad,
        ),
      ),
    );
    if (result != null && mounted) {
      _evictImageCache(widget.bildPfad);
      setState(() => _version++);
      widget.onImageEdited?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark       = Theme.of(context).brightness == Brightness.dark;
    final kreisFarbe = dark ? Colors.black : Colors.white;
    final symFarbe   = dark ? Colors.white : Colors.black;

    final bild = widget.bildPfad.startsWith('http')
        ? Image.network(
            widget.bildPfad,
            fit: BoxFit.contain,
            key: ValueKey('${widget.bildPfad}_$_version'),
          )
        : Image.file(
            File(widget.bildPfad),
            fit: BoxFit.contain,
            gaplessPlayback: false,
            key: ValueKey('${widget.bildPfad}_$_version'),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: dark ? Colors.black : Colors.white,
        body: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.3,
              maxScale: 4.0,
              child: bild,
            ),
          ),
          Positioned(top: 0, left: 0,
            child: SafeArea(
              child: Padding(padding: const EdgeInsets.all(8),
                child: Material(
                  color: kreisFarbe, elevation: 3, shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(padding: const EdgeInsets.all(10),
                      child: Icon(Icons.close, size: 28, color: symFarbe)),
                  ),
                ),
              ),
            ),
          ),
          if (!widget.bildPfad.startsWith('http'))
            Positioned(top: 0, right: 0,
              child: SafeArea(
                child: Padding(padding: const EdgeInsets.all(8),
                  child: Material(
                    color: kreisFarbe, elevation: 3, shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _oeffneEditor,
                      child: Padding(padding: const EdgeInsets.all(12),
                        child: Icon(Icons.edit, size: 24, color: symFarbe)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}