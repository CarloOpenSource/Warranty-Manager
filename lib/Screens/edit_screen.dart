import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
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
      const String pristinePrefix = 'edit_pristine_backup_';
      final settings = <String, dynamic>{};
      
      for (final key in prefs.getKeys()) {
        if (key.startsWith(prefix) || key.startsWith(pristinePrefix)) {
          settings[key] = prefs.getString(key);
        }
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
      const String pristinePrefix = 'edit_pristine_backup_';
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      
      for (final entry in data.entries) {
        if (entry.key.startsWith(prefix) || entry.key.startsWith(pristinePrefix)) {
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

  // ── Farb- & Schärfewerte ──────────────────────────────────────────────────
  double _brightness = 1.0;
  double _contrast   = 1.0;
  double _saturation = 1.0;
  double _sharpness  = 1.0;

  // ── Zustand ───────────────────────────────────────────────────────────────
  bool _isLoading     = true;
  bool _isSaving      = false;
  bool _hasChanges    = false;
  bool _isHighResMode = false;

  // ── Display-Puffer ────────────────────────────────────────────────────────
  Uint8List? _displayBytes;
  int _displayWidth  = 0;
  int _displayHeight = 0;

  // ── Arbeitsbilder ─────────────────────────────────────────────────────────
  img.Image? _baseDisplayImage; 
  img.Image? _lowResBaseImage;  
  img.Image? _originalBackup;   

  // ── Layout-Cache ──────────────────────────────────────────────────────────
  double _renderScale  = 1.0;
  double _imageOffsetX = 0.0;
  double _imageOffsetY = 0.0;

  // ── Zoom ──────────────────────────────────────────────────────────────────
  late final TransformationController _zoomController;
  double _currentZoomScale = 1.0;

  // ── Bottom-Sheet ──────────────────────────────────────────────────────────
  bool _sheetVisible = true;

  // ── Debounce & Timer ──────────────────────────────────────────────────────
  Timer? _debounceTimer;
  Timer? _highResTimer;
  bool   _pendingUpdate = false;
  int    _renderGeneration = 0;
  Future<void>? _pendingLowResJob;

  // ── Konstanten ────────────────────────────────────────────────────────────
  static const String   _prefsPrefix         = 'edit_settings_';
  static const String   _pristinePrefsPrefix = 'edit_pristine_backup_';
  static const int      _maxDisplayDimension = 1024;
  static const int      _lowResMaxDimension  = 320;
  static const double   _handleSize          = 28.0;
  static const Duration _debounceDelay       = Duration(milliseconds: 50);
  static const Duration _highResDelay        = Duration(seconds: 3); // Wechsel auf High-Res nach 3 Sekunden Inaktivität
  static const double   _previewMargin       = 40.0;

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController.addListener(_onZoomChanged);
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
    _highResTimer?.cancel();
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if ((scale - _currentZoomScale).abs() > 0.01) {
      setState(() {
        _currentZoomScale = scale;
      });
    }
  }

  String _t(String key) {
    final s = Provider.of<SettingsProvider>(context, listen: false);
    final res = getText(s.languageCode, key);
    if (key == 'sharpness' && (res == key || res.isEmpty)) {
      return s.languageCode == 'en' ? 'Sharpness' : 'Schärfe';
    }
    return res;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LOKALES & PERMANENTES ORIGINAL-BACKUP (Cache-sicher & exportierbar)
  // ─────────────────────────────────────────────────────────────────────────

  Future<File> _getOrCreatePristineBackupFile(File currentFile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backupKey = '$_pristinePrefsPrefix${widget.originalPath.hashCode}';
      final savedBackupPath = prefs.getString(backupKey);

      if (savedBackupPath != null && savedBackupPath.isNotEmpty) {
        final existingBackup = File(savedBackupPath);
        if (await existingBackup.exists() && await existingBackup.length() > 0) {
          return existingBackup;
        }
      }

      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/edit_pristine_originals');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final backupFile = File(
        '${backupDir.path}/pristine_${widget.originalPath.hashCode.abs()}.jpg',
      );

      if (!await backupFile.exists() || await backupFile.length() == 0) {
        await currentFile.copy(backupFile.path);
      }

      await prefs.setString(backupKey, backupFile.path);
      return backupFile;
    } catch (e) {
      debugPrint('_getOrCreatePristineBackupFile FEHLER: $e');
      return currentFile;
    }
  }

  img.Image _resizeToWorkDimensions(img.Image decoded) {
    if (decoded.width > _maxDisplayDimension ||
        decoded.height > _maxDisplayDimension) {
      final s = math.min(
        _maxDisplayDimension / decoded.width,
        _maxDisplayDimension / decoded.height,
      );
      return img.copyResize(
        decoded,
        width:  (decoded.width  * s).round(),
        height: (decoded.height * s).round(),
      );
    }
    return img.Image.from(decoded);
  }

  void _updateLowResBase() {
    if (_baseDisplayImage == null) return;
    final bw = _baseDisplayImage!.width;
    final bh = _baseDisplayImage!.height;
    if (bw > _lowResMaxDimension || bh > _lowResMaxDimension) {
      final s = math.min(_lowResMaxDimension / bw, _lowResMaxDimension / bh);
      _lowResBaseImage = img.copyResize(
        _baseDisplayImage!,
        width: math.max(1, (bw * s).round()),
        height: math.max(1, (bh * s).round()),
      );
    } else {
      _lowResBaseImage = img.Image.from(_baseDisplayImage!);
    }
  }

  Future<void> _loadImage() async {
    setState(() => _isLoading = true);
    try {
      final file = File(widget.originalPath);
      if (!await file.exists()) {
        throw FileSystemException('Datei nicht gefunden', widget.originalPath);
      }

      // 1. Permanentes Backup im Dokumentenverzeichnis sicherstellen
      final pristineFile = await _getOrCreatePristineBackupFile(file);

      // 2. Originalbild laden
      img.Image pristineWork;
      if (await pristineFile.exists()) {
        final pristineBytes = await pristineFile.readAsBytes();
        final pristineDecoded = img.decodeImage(pristineBytes);
        pristineWork = pristineDecoded != null
            ? _resizeToWorkDimensions(pristineDecoded)
            : _resizeToWorkDimensions(img.decodeImage(await file.readAsBytes())!);
      } else {
        final bytes = await file.readAsBytes();
        pristineWork = _resizeToWorkDimensions(img.decodeImage(bytes)!);
      }

      _originalBackup   = pristineWork;
      _baseDisplayImage = img.Image.from(pristineWork);
      _updateLowResBase();

      // 3. Gespeicherte Regler-Werte laden (damit die Slider korrekt positioniert sind)
      await _loadSettingsForImage();

      _cropRect = Rect.fromLTWH(
        0, 0,
        _baseDisplayImage!.width.toDouble(),
        _baseDisplayImage!.height.toDouble(),
      );

      // Zuerst schnelle Low-Res-Vorschau anzeigen, dann High-Res anfordern
      _rebuildDisplayLowRes();
      _rebuildDisplayHighResSync();
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

  Future<void> _loadSettingsForImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = '$_prefsPrefix${widget.originalPath.hashCode}';
      final str   = prefs.getString(key);
      if (str == null) return;
      final data = jsonDecode(str) as Map<String, dynamic>;
      _brightness = (data['brightness'] as num?)?.toDouble() ?? 1.0;
      _contrast   = (data['contrast']   as num?)?.toDouble() ?? 1.0;
      _saturation = (data['saturation'] as num?)?.toDouble() ?? 1.0;
      _sharpness  = (data['sharpness']  as num?)?.toDouble() ?? 1.0;
      _hasChanges = false;
    } catch (e) {
      debugPrint('_loadSettingsForImage FEHLER: $e');
    }
  }

  Future<void> _saveSettingsForImage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = '$_prefsPrefix${widget.originalPath.hashCode}';
      // Speichert die exakten Regler-Werte, damit sie beim nächsten Öffnen wieder da sind
      await prefs.setString(key, jsonEncode({
        'brightness': _brightness,
        'contrast':   _contrast,
        'saturation': _saturation,
        'sharpness':  _sharpness,
        'timestamp':  DateTime.now().toIso8601String(),
      }));
    } catch (e) {
      debugPrint('_saveSettingsForImage FEHLER: $e');
    }
  }

  void _rebuildDisplayLowRes() {
    final src = _lowResBaseImage ?? _baseDisplayImage;
    if (src == null) return;

    final out = _applyImageAdjustments(
      img.Image.from(src),
      brightness: _brightness,
      contrast:   _contrast,
      saturation: _saturation,
      sharpness:  _sharpness,
    );

    _displayBytes  = Uint8List.fromList(img.encodeJpg(out, quality: 80));
    _displayWidth  = _baseDisplayImage!.width;
    _displayHeight = _baseDisplayImage!.height;
    _isHighResMode = false;
  }

  Future<void> _rebuildDisplayLowResAsync(int gen) async {
    final src = _lowResBaseImage ?? _baseDisplayImage;
    if (src == null) return;

    final baseBytes = Uint8List.fromList(img.encodeJpg(src, quality: 85));
    final params = _PreviewParams(
      baseImageBytes: baseBytes,
      brightness:     _brightness,
      contrast:       _contrast,
      saturation:     _saturation,
      sharpness:      _sharpness,
    );

    try {
      final resultBytes = await Isolate.run(
        () => _renderPreviewInBackground(params),
      );
      if (mounted && gen == _renderGeneration && resultBytes != null) {
        setState(() {
          _displayBytes  = resultBytes;
          _displayWidth  = _baseDisplayImage!.width;
          _displayHeight = _baseDisplayImage!.height;
          _isHighResMode = false;
        });
      }
    } catch (e) {
      if (mounted && gen == _renderGeneration) {
        _rebuildDisplayLowRes();
        setState(() {});
      }
    }
  }

  void _rebuildDisplayHighResSync() {
    if (_baseDisplayImage == null) return;
    _highResTimer?.cancel();
    _renderGeneration++;

    final out = _applyImageAdjustments(
      img.Image.from(_baseDisplayImage!),
      brightness: _brightness,
      contrast:   _contrast,
      saturation: _saturation,
      sharpness:  _sharpness,
    );
    _displayBytes  = Uint8List.fromList(img.encodeJpg(out, quality: 92));
    _displayWidth  = out.width;
    _displayHeight = out.height;
    _isHighResMode = true;
  }

  Future<void> _rebuildDisplayHighResAsync() async {
    if (_baseDisplayImage == null || !mounted) return;
    final gen = ++_renderGeneration;

    try {
      final baseBytes = Uint8List.fromList(
        img.encodeJpg(_baseDisplayImage!, quality: 98),
      );
      final params = _PreviewParams(
        baseImageBytes: baseBytes,
        brightness:     _brightness,
        contrast:       _contrast,
        saturation:     _saturation,
        sharpness:      _sharpness,
      );

      final resultBytes = await Isolate.run(() => _renderPreviewInBackground(params));

      if (mounted && gen == _renderGeneration && resultBytes != null) {
        setState(() {
          _displayBytes  = resultBytes;
          _displayWidth  = _baseDisplayImage!.width;
          _displayHeight = _baseDisplayImage!.height;
          _isHighResMode = true;
        });
      }
    } catch (e) {
      debugPrint('HighRes-Preview Isolate Fallback: $e');
      if (mounted && gen == _renderGeneration) {
        _rebuildDisplayHighResSync();
        setState(() {});
      }
    }
  }

  void _scheduleDisplayUpdate() {
    _pendingUpdate = true;
    _debounceTimer?.cancel();
    _highResTimer?.cancel();
    final gen = ++_renderGeneration;

    // Sofort flüssige Low-Res-Vorschau rendern
    _rebuildDisplayLowResAsync(gen);

    _debounceTimer = Timer(_debounceDelay, () {
      if (!mounted) return;
      _pendingUpdate = false;
      _hasChanges    = true;

      // Nach 3 Sekunden Inaktivität auf High-Res wechseln
      _highResTimer = Timer(_highResDelay, () {
        if (mounted) _rebuildDisplayHighResAsync();
      });
    });
  }

  void _onBrightnessChanged(double v) { _brightness = v; _scheduleDisplayUpdate(); }
  void _onContrastChanged(double v)   { _contrast   = v; _scheduleDisplayUpdate(); }
  void _onSaturationChanged(double v) { _saturation = v; _scheduleDisplayUpdate(); }
  void _onSharpnessChanged(double v)  { _sharpness  = v; _scheduleDisplayUpdate(); }

  void _applyRotation(int angleDeg) {
    if (_baseDisplayImage == null || _isSaving) return;
    _debounceTimer?.cancel();
    _highResTimer?.cancel();
    _pendingUpdate = false;

    _baseDisplayImage = img.copyRotate(_baseDisplayImage!, angle: angleDeg);
    _updateLowResBase();
    _cropRect = Rect.fromLTWH(
      0, 0,
      _baseDisplayImage!.width.toDouble(),
      _baseDisplayImage!.height.toDouble(),
    );
    _hasChanges = true;
    _rebuildDisplayHighResSync();
    if (mounted) setState(() {});
  }

  void _rotateLeft()  => _applyRotation(90);
  void _rotateRight() => _applyRotation(-90);

  void _enterCropMode() {
    _zoomController.value = Matrix4.identity();
    _currentZoomScale = 1.0;
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
      _baseDisplayImage = img.copyCrop(
        _baseDisplayImage!,
        x: x, y: y, width: w, height: h,
      );
      _updateLowResBase();
      _hasChanges = true;
    }
    _cropRect = Rect.fromLTWH(
      0, 0,
      _baseDisplayImage!.width.toDouble(),
      _baseDisplayImage!.height.toDouble(),
    );
    _rebuildDisplayHighResSync();
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    _currentZoomScale = 1.0;
  }

  void _applyZoom(double targetScale) {
    final m = Matrix4.diagonal3Values(targetScale, targetScale, 1.0);
    _zoomController.value = m;
    _currentZoomScale = targetScale;
    setState(() {});
  }

  double _getEffectiveMargin() {
    if (_isCropMode) return _previewMargin;
    if (_currentZoomScale <= 1.0) return _previewMargin;
    final t = ((_currentZoomScale - 1.0) / 0.35).clamp(0.0, 1.0);
    return _previewMargin * (1.0 - t);
  }

  void _resetSlidersOnly() {
    _debounceTimer?.cancel();
    _highResTimer?.cancel();
    _pendingUpdate = false;
    _renderGeneration++;
    setState(() {
      _brightness = 1.0;
      _contrast   = 1.0;
      _saturation = 1.0;
      _sharpness  = 1.0;
      _hasChanges = true;
    });
    _rebuildDisplayHighResSync();
    if (mounted) setState(() {});
  }

  Future<void> _resetToOriginal() async {
    _debounceTimer?.cancel();
    _highResTimer?.cancel();
    _pendingUpdate = false;
    _renderGeneration++;

    if (_originalBackup != null) {
      _baseDisplayImage = img.Image.from(_originalBackup!);
      _updateLowResBase();
    }

    _cropRect = Rect.fromLTWH(
      0, 0,
      _baseDisplayImage!.width.toDouble(),
      _baseDisplayImage!.height.toDouble(),
    );
    _brightness = 1.0;
    _contrast   = 1.0;
    _saturation = 1.0;
    _sharpness  = 1.0;
    _rebuildDisplayHighResSync();
    _resetZoom();

    if (mounted) {
      setState(() {
        _isCropMode   = false;
        _activeHandle = null;
        _hasChanges   = true;
      });
    }
  }

  Future<void> _saveAndExit() async {
    if (_baseDisplayImage == null || _isSaving) return;
    _debounceTimer?.cancel();
    _highResTimer?.cancel();

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
        sharpness:      _sharpness,
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Bild gespeichert!')),
          );
          Navigator.pop(context, widget.originalPath);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Fehler: ${result.error}')),
          );
          setState(() => _isSaving = false);
        }
      }
    } catch (e) {
      debugPrint('_saveAndExit FEHLER: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  void _onPanStart(PointerDownEvent d) {
    if (!_isCropMode) return;
    final localInImage = Offset(
      d.localPosition.dx - _imageOffsetX,
      d.localPosition.dy - _imageOffsetY,
    );
    _activeHandle = _hitTestHandle(localInImage);
  }

  void _onPanUpdate(PointerMoveEvent d) {
    if (!_isCropMode || _activeHandle == null) return;
    final s = _renderScale > 0 ? _renderScale : 1.0;
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
    final m = _cropMarginPx().clamp(20.0, double.infinity);
    final maxL = _displayWidth.toDouble()  - m;
    final maxT = _displayHeight.toDouble() - m;
    l   = l.clamp(m, maxL);
    ri  = ri.clamp(l + 20.0, _displayWidth.toDouble());
    top = top.clamp(m, maxT);
    b   = b.clamp(top + 20.0, _displayHeight.toDouble());
    return Rect.fromLTRB(l, top, ri, b);
  }

  double _cropMarginPx() {
    final s = _renderScale > 0 ? _renderScale : 1.0;
    return (24.0 / s).clamp(20.0, double.infinity);
  }

  Future<bool> _onWillPop() async {
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
            Navigator.pop(context);
          }
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _istDunkel ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: _istDunkel ? Colors.black : Colors.white,
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
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

                                final pad = _getEffectiveMargin();
                                final scale = math.min(
                                  (constraints.maxWidth  - pad * 2) / imgW,
                                  (constraints.maxHeight - pad * 2) / imgH,
                                );
                                final fitW = imgW * scale;
                                final fitH = imgH * scale;
                                final offX = (constraints.maxWidth  - fitW) / 2;
                                final offY = (constraints.maxHeight - fitH) / 2;

                                _renderScale  = scale;
                                _imageOffsetX = offX;
                                _imageOffsetY = offY;

                                return Stack(children: [
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: _istDunkel
                                          ? Colors.black
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  if (_isCropMode)
                                    Positioned(
                                      left: offX,
                                      top: offY,
                                      width: fitW,
                                      height: fitH,
                                      child: Image.memory(
                                        _displayBytes!,
                                        fit: BoxFit.fill,
                                        gaplessPlayback: true,
                                      ),
                                    )
                                  else
                                    Positioned.fill(
                                      child: InteractiveViewer(
                                        panEnabled: true,
                                        minScale: 0.5,
                                        maxScale: 4.0,
                                        transformationController: _zoomController,
                                        child: Center(
                                          child: SizedBox(
                                            width: fitW,
                                            height: fitH,
                                            child: Image.memory(
                                              _displayBytes!,
                                              fit: BoxFit.fill,
                                              gaplessPlayback: true,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_isCropMode)
                                    Positioned.fill(
                                      child: Listener(
                                        onPointerDown:  _onPanStart,
                                        onPointerMove:  _onPanUpdate,
                                        onPointerUp:    _onPanEnd,
                                        behavior: HitTestBehavior.translucent,
                                        child: CustomPaint(
                                          painter: _CropPainter(
                                            cropRect: Rect.fromLTWH(
                                              offX + _cropRect.left   * scale,
                                              offY + _cropRect.top    * scale,
                                              _cropRect.width  * scale,
                                              _cropRect.height * scale,
                                            ),
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
              if (!_isLoading)
                _buildSheet(settings),
            ],
          ),
        ),
      ),
    );
  }

  static const double _sheetCollapsedH = 24.0;
  double _sheetExpandedH = 190.0;
  double _sheetCurrentH  = 190.0;
  bool   _sheetMeasured  = false;

  double? _dragStartY;
  double? _dragStartH;

  void _onSheetDragStart(DragStartDetails d) {
    _dragStartY = d.globalPosition.dy;
    _dragStartH = _sheetCurrentH;
  }

  void _onSheetDragUpdate(DragUpdateDetails d) {
    if (_dragStartY == null || _dragStartH == null) return;
    final delta = _dragStartY! - d.globalPosition.dy;
    final newH = (_dragStartH! + delta)
        .clamp(_sheetCollapsedH, _sheetExpandedH);
    setState(() {
      _sheetCurrentH = newH;
      _sheetVisible  = newH > _sheetCollapsedH + 10;
    });
  }

  void _onSheetDragEnd(DragEndDetails d) {
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
    final btnsActive = _sheetVisible && !_isSaving && !_isCropMode;
    // Automatische und präzise Erkennung der System-Navigationsleiste
    final mq = MediaQuery.of(context);
    final bottomPad = mq.viewPadding.bottom > 0
        ? mq.viewPadding.bottom
        : mq.padding.bottom;

    return GestureDetector(
      onVerticalDragStart:  _onSheetDragStart,
      onVerticalDragUpdate: _onSheetDragUpdate,
      onVerticalDragEnd:    _onSheetDragEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
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
            if (_sheetVisible)
              Flexible(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: MeasureSize(
                    onChange: (size) {
                      if (!_sheetMeasured) {
                        final mq2 = MediaQuery.of(context);
                        final bp  = mq2.viewPadding.bottom > 0
                            ? mq2.viewPadding.bottom
                            : mq2.padding.bottom;
                        final fullH = size.height + 20 + _sheetCollapsedH + bp;
                        setState(() {
                          _sheetExpandedH  = fullH.clamp(120.0, 320.0);
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
                              Expanded(child: _sliderCompact(
                                'sharpness', Icons.details_outlined,
                                _sharpness, _onSharpnessChanged, settings,
                                active: btnsActive,
                              )),
                            ],
                          ),
                          _divider(),
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
                                color: Colors.amber,
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
        Icon(icon, size: 12,
            color: active
                ? (_istDunkel ? Colors.white60 : Colors.grey.shade600)
                : Colors.grey.shade500),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            _t(key),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 9.5,
              color: active
                  ? (_istDunkel ? Colors.white70 : Colors.black87)
                  : Colors.grey.shade500,
            ),
          ),
        ),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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

img.Image _applyImageAdjustments(
  img.Image source, {
  required double brightness,
  required double contrast,
  required double saturation,
  required double sharpness,
}) {
  img.Image result = img.adjustColor(
    source,
    brightness: brightness,
    contrast:   contrast,
    saturation: saturation,
  );

  if ((sharpness - 1.0).abs() > 0.02) {
    if (sharpness > 1.0) {
      final amount = (sharpness - 1.0) * 0.8;
      final center = 1.0 + 4.0 * amount;
      final edge   = -amount;
      result = img.convolution(
        result,
        filter: [
          0,    edge,   0,
          edge, center, edge,
          0,    edge,   0,
        ],
      );
    } else {
      final blurAmount = (1.0 - sharpness);
      final edge = blurAmount * 0.125;
      final center = 1.0 - 4.0 * edge;
      result = img.convolution(
        result,
        filter: [
          0,    edge,   0,
          edge, center, edge,
          0,    edge,   0,
        ],
      );
    }
  }

  return result;
}

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

class _PreviewParams {
  final Uint8List baseImageBytes;
  final double    brightness;
  final double    contrast;
  final double    saturation;
  final double    sharpness;

  const _PreviewParams({
    required this.baseImageBytes,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.sharpness,
  });
}

Uint8List? _renderPreviewInBackground(_PreviewParams p) {
  try {
    final img.Image? base = img.decodeImage(p.baseImageBytes);
    if (base == null) return null;
    final out = _applyImageAdjustments(
      base,
      brightness: p.brightness,
      contrast:   p.contrast,
      saturation: p.saturation,
      sharpness:  p.sharpness,
    );
    return Uint8List.fromList(img.encodeJpg(out, quality: 92));
  } catch (_) {
    return null;
  }
}

class _SaveParams {
  final Uint8List baseImageBytes;
  final double    brightness;
  final double    contrast;
  final double    saturation;
  final double    sharpness;
  final String    originalPath;

  const _SaveParams({
    required this.baseImageBytes,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.sharpness,
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
    final out = _applyImageAdjustments(
      base,
      brightness: p.brightness,
      contrast:   p.contrast,
      saturation: p.saturation,
      sharpness:  p.sharpness,
    );
    final bytes = Uint8List.fromList(img.encodeJpg(out, quality: 95));
    File(p.originalPath).writeAsBytesSync(bytes);
    return const _SaveResult(success: true);
  } catch (e) {
    return _SaveResult(success: false, error: e.toString());
  }
}

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
  final Rect   cropRect;
  final Size   fullSize;
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

    canvas.drawRect(
      cropRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

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