import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../Services/settings_provider.dart';
import '../Services/notification_service.dart';
import 'package:garantiemanager/Manual/tutorial.dart';
import 'dart:convert';
import '../Services/calender_service.dart';
import 'package:garantiemanager/Screens/edit_screen.dart';

class _SettingsTimeLocalizations extends DefaultMaterialLocalizations {
  final String lang;
  const _SettingsTimeLocalizations(this.lang);

  @override
  String get okButtonLabel => getText(lang, 'ok');
  @override
  String get cancelButtonLabel => getText(lang, 'cancel').toUpperCase();
  @override
  String get timePickerDialHelpText => getText(lang, 'time_picker_dial_help');
  @override
  String get timePickerInputHelpText => getText(lang, 'time_picker_input_help');
  @override
  String get timePickerHourLabel => getText(lang, 'time_picker_hour');
  @override
  String get timePickerMinuteLabel => getText(lang, 'time_picker_minute');
  @override
  String get dialModeButtonLabel => getText(lang, 'time_picker_dial_mode');
  @override
  String get inputTimeModeButtonLabel => getText(lang, 'time_picker_input_mode');
  @override
  String get invalidTimeLabel => getText(lang, 'time_picker_invalid');
  @override
  String get timePickerHourModeAnnouncement => getText(lang, 'time_picker_hour_announce');
  @override
  String get timePickerMinuteModeAnnouncement => getText(lang, 'time_picker_minute_announce');
  @override
  String get anteMeridiemAbbreviation => getText(lang, 'time_am');
  @override
  String get postMeridiemAbbreviation => getText(lang, 'time_pm');
}

class _SettingsTimeLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  final String lang;
  const _SettingsTimeLocalizationsDelegate(this.lang);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    return _SettingsTimeLocalizations(lang);
  }

  @override
  bool shouldReload(_SettingsTimeLocalizationsDelegate old) => old.lang != lang;
}

class AddScreen extends StatefulWidget {
  final Map<String, String>? bearbeitenGerat;
  final bool isFromTutorial;
  final List<Map<String, String>>? existingDevices;

  const AddScreen({
    super.key,
    this.bearbeitenGerat,
    this.isFromTutorial = false,
    this.existingDevices,
  });

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _woGekauftController = TextEditingController();
  final TextEditingController _preisController = TextEditingController();
  final TextEditingController _eigeneGarantieController = TextEditingController(text: '1');
  final TextEditingController _bemerkungController = TextEditingController();

  final GlobalKey _nameKey = GlobalKey();
  final GlobalKey _kaufdetailsKey = GlobalKey();
  final GlobalKey _garantieKey = GlobalKey();
  final GlobalKey _timerKey = GlobalKey();
  final GlobalKey _fotosKey = GlobalKey();
  final GlobalKey _saveKey = GlobalKey();

  DateTime _kaufDatum = DateTime.now();
  int _garantieMonate = 24;
  String _eigeneGarantieEinheit = 'Jahre';
  bool _istEigeneGarantieSelected = false;
  String _kategorie = 'electronics';

  // Version-Counter für Bilder, um Cache zu umgehen nach Bearbeitung
  final Map<String, int> _imageVersions = {};

  void _incrementImageVersion(String path) {
    setState(() {
      _imageVersions[path] = (_imageVersions[path] ?? 0) + 1;
    });
  }

  bool _erinnerungNie = false;
  DateTime? _erinnerungsDatum;
  TimeOfDay? _erinnerungsUhrzeit;

  String? _selectedWaehrung;
  bool _waehrungInitialisiert = false;

  bool _nameError = false;
  bool _woGekauftError = false;
  bool _preisError = false;
  bool _fotoError = false;
  bool _dauerError = false;

  bool _showFotoInfo = false;

  final List<String> _kategorieKeys = ['electronics', 'furniture', 'household', 'others'];

  final Map<int, String> _garantieOptionen = {
    6: '6 Monate',
    12: '1 Jahr',
    24: '2 Jahre',
    36: '3 Jahre',
    60: '5 Jahre'
  };

  List<XFile> _bonBilder = [];

  Set<String> _kachelAuswahl = {};

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _eigeneGarantieController.addListener(_updateState);
    _erinnerungsUhrzeit = TimeOfDay.now();

    if (widget.isFromTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final route = ModalRoute.of(context);
        if (route != null) {
          void handler(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              route.animation?.removeStatusListener(handler);
              if (!mounted) return;
              final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
              TutorialHelper.zeigeAddDeviceTutorial(
                context: context,
                nameKey: _nameKey,
                kaufdetailsKey: _kaufdetailsKey,
                garantieKey: _garantieKey,
                timerKey: _timerKey,
                fotosKey: _fotosKey,
                saveKey: _saveKey,
                onSaveDemo: () {
                  _nameController.text = getText(lang, 'demo_product');
                  _woGekauftController.text = getText(lang, 'demo_store');
                  _preisController.text = '149.99';
                  _speichern();
                },
              );
            }
          }
          route.animation?.addStatusListener(handler);
        }
      });
    }

    bool standardKachelGeladen = false;

    if (widget.bearbeitenGerat != null) {
      final g = widget.bearbeitenGerat!;
      _nameController.text = g['name'] ?? '';

      String rawPreis = g['preis'] ?? '';
      _preisController.text = rawPreis.replaceAll(RegExp(r'[^\d.,]'), '').trim();

      _woGekauftController.text = (g['woGekauft'] == 'Unbekannt') ? '' : (g['woGekauft'] ?? '');
      _selectedWaehrung = g['waehrung'];
      _bemerkungController.text = g['bemerkung'] ?? '';

      if (g['kategorie'] != null && _kategorieKeys.contains(g['kategorie'])) {
        _kategorie = g['kategorie']!;
      } else {
        _kategorie = _kategorieKeys.first;
      }

      if (g['kaufDatum'] != null && g['kaufDatum']!.isNotEmpty) {
        try {
          final teile = g['kaufDatum']!.split('.');
          if (teile.length == 3) {
            _kaufDatum = DateTime(int.parse(teile[2]), int.parse(teile[1]), int.parse(teile[0]));
          }
        } catch (_) {}
      }

      if (g['garantieDauer'] != null && g['garantieDauer']!.isNotEmpty) {
        final gText = g['garantieDauer']!;
        final lowerG = gText.toLowerCase();
        bool isStandard = false;

        for (var entry in _garantieOptionen.entries) {
          if (gText == entry.value) {
            _garantieMonate = entry.key;
            _istEigeneGarantieSelected = false;
            isStandard = true;
            standardKachelGeladen = true;
            break;
          }
        }

        if (!isStandard) {
          _istEigeneGarantieSelected = true;
          final numMatch = RegExp(r'\d+').firstMatch(gText);
          int rawWert = numMatch != null ? int.parse(numMatch.group(0)!) : 1;

          if (lowerG.contains('woche')) {
            if (rawWert > 0 && rawWert % 52 == 0) {
              _eigeneGarantieEinheit = 'Jahre';
              _eigeneGarantieController.text = (rawWert ~/ 52).toString();
            } else if (rawWert > 0 && rawWert % 4 == 0) {
              _eigeneGarantieEinheit = 'Monate';
              _eigeneGarantieController.text = (rawWert ~/ 4).toString();
            } else {
              _eigeneGarantieEinheit = 'Wochen';
              _eigeneGarantieController.text = rawWert.toString();
            }
          } else if (lowerG.contains('monat')) {
            if (rawWert > 0 && rawWert % 12 == 0) {
              _eigeneGarantieEinheit = 'Jahre';
              _eigeneGarantieController.text = (rawWert ~/ 12).toString();
            } else {
              _eigeneGarantieEinheit = 'Monate';
              _eigeneGarantieController.text = rawWert.toString();
            }
          } else {
            _eigeneGarantieEinheit = 'Jahre';
            _eigeneGarantieController.text = rawWert.toString();
          }
        }
      }

      if (g['erinnerung'] != null && g['erinnerung']!.isNotEmpty) {
        if (g['erinnerung'] == 'Nie') {
          _erinnerungNie = true;
        } else {
          _erinnerungNie = false;
          try {
            Map<String, dynamic> timerData = jsonDecode(g['erinnerung']!);
            if (timerData['ausloeseZeit'] != null) {
              DateTime saved = DateTime.parse(timerData['ausloeseZeit']);
              _erinnerungsDatum = DateTime(saved.year, saved.month, saved.day);
              _erinnerungsUhrzeit = TimeOfDay(hour: saved.hour, minute: saved.minute);
            }
          } catch (e) {
            //ignore
          }
        }
      }

      if (g['bildPfade'] != null && g['bildPfade']!.isNotEmpty) {
        _bonBilder = g['bildPfade']!
            .split(',')
            .where((p) => p.trim().isNotEmpty)
            .map((p) => XFile(p.trim()))
            .toList();
      }

      if (g['kachelPfade'] != null && g['kachelPfade']!.isNotEmpty) {
        final gueltigeBonPfade = _bonBilder.map((f) => f.path).toSet();
        _kachelAuswahl = g['kachelPfade']!
            .split(',')
            .where((p) => p.trim().isNotEmpty && gueltigeBonPfade.contains(p.trim()))
            .map((p) => p.trim())
            .toSet();
      }
    }

    if (standardKachelGeladen) {
      _updateReminderLimits();
    } else {
      _berechneEigeneGarantie(initial: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_waehrungInitialisiert) {
      final settings = Provider.of<SettingsProvider>(context, listen: false);
      _selectedWaehrung ??= settings.currencySymbol;
      _waehrungInitialisiert = true;
    }
  }

  void _updateState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _eigeneGarantieController.dispose();
    _nameController.dispose();
    _woGekauftController.dispose();
    _preisController.dispose();
    _bemerkungController.dispose();
    super.dispose();
  }

  void _updateReminderLimits() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ablauf = _ablaufDatum;

    if (ablauf.isBefore(today)) {
      _erinnerungNie = true;
    } else {
      if (_erinnerungNie && widget.bearbeitenGerat?['erinnerung'] != 'Nie') {
        _erinnerungNie = false;
      }

      DateTime vorbelastung = ablauf.subtract(const Duration(days: 14));
      if (vorbelastung.isBefore(today)) vorbelastung = today;

      _erinnerungsDatum = vorbelastung;
    }
  }

  void _berechneEigeneGarantie({bool initial = false}) {
    double wert = double.tryParse(_eigeneGarantieController.text.trim()) ?? 0;
    if (wert > 10000) wert = 10000;

    if (_eigeneGarantieEinheit == 'Jahre') {
      _garantieMonate = (wert * 12).round();
    } else if (_eigeneGarantieEinheit == 'Wochen') {
      _garantieMonate = (wert / 4.345).round();
    } else {
      _garantieMonate = wert.round();
    }

    if (!initial) {
      setState(() {
        _updateReminderLimits();
      });
    } else {
      _updateReminderLimits();
    }
  }

  void _zeigeFehler(String text) {
    final bool istDunkel = Theme.of(context).brightness == Brightness.dark;
    final Color hintergrund = istDunkel ? Colors.white : Colors.black;
    final Color schrift = istDunkel ? Colors.black : Colors.white;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: TextStyle(color: schrift)),
        backgroundColor: hintergrund,
      ),
    );
  }

  Future<void> _fotoAufnehmen(ImageSource source) async {
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    if (_bonBilder.length >= 4) {
      _zeigeFehler(getText(lang, 'error_max_photos'));
      return;
    }
    try {
      final XFile? gewaehltesBild = await _picker.pickImage(source: source, imageQuality: 80);
      if (gewaehltesBild == null) return;

      if (!kIsWeb && !await _istGueltigesBild(gewaehltesBild.path)) {
        final String ungueltigerPfad = gewaehltesBild.path;
        if (ungueltigerPfad.toLowerCase().contains('cache')) {
          try { await File(ungueltigerPfad).delete(); } catch (_) {}
        }
        if (mounted) {
          _zeigeFehler(getText(lang, 'error_loading_file'));
        }
        return;
      }

      String? zielPfad;
      try {
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        final String dateiName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(gewaehltesBild.path)}';
        zielPfad = path.join(appDocDir.path, dateiName);
        await gewaehltesBild.saveTo(zielPfad);
      } catch (_) {
        zielPfad = gewaehltesBild.path;
      }
      setState(() {
        _bonBilder.add(XFile(zielPfad!));
        _fotoError = false;
      });
    } catch (e) {
      //
    }
  }

  Future<void> _fotosAusGalerieWaehlen() async {
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    final int frei = 4 - _bonBilder.length;

    if (frei <= 0) {
      _zeigeFehler(getText(lang, 'error_max_photos'));
      return;
    }

    if (frei == 1) {
      await _fotoAufnehmen(ImageSource.gallery);
      return;
    }

    try {
      final List<XFile> gewaehlt = await _picker.pickMultiImage(imageQuality: 80, limit: frei);
      if (gewaehlt.isEmpty || !mounted) return;

      List<XFile> verwendet = gewaehlt;
      if (gewaehlt.length > frei) {
        verwendet = gewaehlt.sublist(0, frei);
        _zeigeFehler(getText(lang, 'error_max_photos'));
      }

      int abgelehnt = 0;
      for (final bild in verwendet) {
        if (_bonBilder.length >= 4) break;
        final XFile? gespeichert = await _bildPruefenUndSpeichern(bild);
        if (gespeichert == null) {
          abgelehnt++;
          continue;
        }
        if (!mounted) return;
        setState(() {
          _bonBilder.add(gespeichert);
          _fotoError = false;
        });
      }

      if (abgelehnt > 0 && mounted) {
        _zeigeFehler(getText(lang, 'error_loading_file'));
      }
    } catch (e) {
      //
    }
  }

  Future<XFile?> _bildPruefenUndSpeichern(XFile gewaehltesBild) async {
    if (!kIsWeb && !await _istGueltigesBild(gewaehltesBild.path)) {
      final String ungueltigerPfad = gewaehltesBild.path;
      if (ungueltigerPfad.toLowerCase().contains('cache')) {
        try { await File(ungueltigerPfad).delete(); } catch (_) {}
      }
      return null;
    }

    String? zielPfad;
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String dateiName = '${DateTime.now().millisecondsSinceEpoch}_${path.basename(gewaehltesBild.path)}';
      zielPfad = path.join(appDocDir.path, dateiName);
      await gewaehltesBild.saveTo(zielPfad);
    } catch (_) {
      zielPfad = gewaehltesBild.path;
    }
    return XFile(zielPfad);
  }

  Future<bool> _istGueltigesBild(String pfad) async {
    RandomAccessFile? raf;
    try {
      final datei = File(pfad);
      if (!await datei.exists()) return false;
      raf = await datei.open();
      final kopf = await raf.read(16);
      if (kopf.length < 12) return false;

      if (kopf[0] == 0xFF && kopf[1] == 0xD8 && kopf[2] == 0xFF) return true;
      if (kopf[0] == 0x89 && kopf[1] == 0x50 && kopf[2] == 0x4E && kopf[3] == 0x47) return true;
      if (kopf[0] == 0x47 && kopf[1] == 0x49 && kopf[2] == 0x46 && kopf[3] == 0x38) return true;
      if (kopf[0] == 0x42 && kopf[1] == 0x4D) return true;
      if (kopf[0] == 0x52 && kopf[1] == 0x49 && kopf[2] == 0x46 && kopf[3] == 0x46 &&
          kopf[8] == 0x57 && kopf[9] == 0x45 && kopf[10] == 0x42 && kopf[11] == 0x50) {
        return true;
      }
      if (kopf[4] == 0x66 && kopf[5] == 0x74 && kopf[6] == 0x79 && kopf[7] == 0x70) {
        final marke = String.fromCharCodes(kopf.sublist(8, 12));
        const bildMarken = ['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1', 'avif', 'avis'];
        return bildMarken.contains(marke);
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      try { await raf?.close(); } catch (_) {}
    }
  }

  void _toggleKachelAuswahl(String pfad) {
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    if (_kachelAuswahl.contains(pfad)) {
      setState(() => _kachelAuswahl.remove(pfad));
    } else {
      if (_kachelAuswahl.length >= 2) {
        _zeigeFehler(getText(lang, 'tile_preview_max'));
        return;
      }
      setState(() => _kachelAuswahl.add(pfad));
    }
  }

  void _zeigeBildVollbild(String bildPfad) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) {
          final bool istDunkel = Theme.of(ctx).brightness == Brightness.dark;
          final Color kreisFarbe = istDunkel ? Colors.black : Colors.white;
          final Color kreuzFarbe = istDunkel ? Colors.white : Colors.black;

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
                      child: (kIsWeb || bildPfad.startsWith('http'))
                          ? Image.network(bildPfad, fit: BoxFit.contain, key: ValueKey('${bildPfad}_${_imageVersions[bildPfad] ?? 0}'))
                          : Image.file(File(bildPfad), fit: BoxFit.contain, key: ValueKey('${bildPfad}_${_imageVersions[bildPfad] ?? 0}')),
                    ),
                  ),
                  // --- Ganz links: Schließen-Button ---
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Material(
                          color: kreisFarbe,
                          elevation: 3,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.close, size: 28, color: kreuzFarbe),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // --- Ganz rechts: Bearbeiten-Button (Stift) ---
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Material(
                          color: kreisFarbe,
                          elevation: 3,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () async {
                              if (!bildPfad.startsWith('http')) {
                                final result = await Navigator.of(ctx).push(
                                  MaterialPageRoute(
                                    builder: (ctx2) => EditScreen(
                                      imageDataPath: bildPfad,
                                      originalPath: bildPfad,
                                    ),
                                  ),
                                );
                                if (result != null && mounted) {
                                  // Version erhöhen für Cache-Busting
                                  _incrementImageVersion(bildPfad);
                                }
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(Icons.edit, size: 24, color: kreuzFarbe),
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
        },
      ),
    );
  }

  void _zeigeFotoOptionen(String lang) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: Text(getText(lang, 'camera')),
                onTap: () { Navigator.of(context).pop(); _fotoAufnehmen(ImageSource.camera); },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(getText(lang, 'gallery')),
                onTap: () { Navigator.of(context).pop(); _fotosAusGalerieWaehlen(); },
              ),
            ],
          ),
        );
      },
    );
  }

  DateTime get _ablaufDatum {
    if (_istEigeneGarantieSelected) {
      int wert = int.tryParse(_eigeneGarantieController.text.trim()) ?? 1;
      if (wert > 10000) wert = 10000;

      DateTime berechnet;
      try {
        if (_eigeneGarantieEinheit == 'Wochen') {
          berechnet = _kaufDatum.add(Duration(days: wert * 7));
        } else if (_eigeneGarantieEinheit == 'Monate') {
          int addedYears = wert ~/ 12;
          if (_kaufDatum.year + addedYears > 2099) return DateTime(2099, 12, 31);
          berechnet = DateTime(_kaufDatum.year, _kaufDatum.month + wert, _kaufDatum.day);
        } else {
          if (_kaufDatum.year + wert > 2099) return DateTime(2099, 12, 31);
          berechnet = DateTime(_kaufDatum.year + wert, _kaufDatum.month, _kaufDatum.day);
        }
      } catch (e) {
        return DateTime(2099, 12, 31);
      }

      if (berechnet.year > 2099) return DateTime(2099, 12, 31);
      return berechnet;
    }

    DateTime berechnet = DateTime(_kaufDatum.year, _kaufDatum.month + _garantieMonate, _kaufDatum.day);
    if (berechnet.year > 2099) return DateTime(2099, 12, 31);
    return berechnet;
  }

  Future<void> _erinnerungsDatumAuswaehlen() async {
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime first = today;
    DateTime last = _ablaufDatum;
    if (last.isBefore(first)) last = first;

    final DateTime initial = _erinnerungsDatum ?? _ablaufDatum.subtract(const Duration(days: 14));
    DateTime safeInitial = initial.isBefore(first) ? first : initial;
    if (safeInitial.isAfter(last)) safeInitial = last;

    final DateTime? gewaehlt = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: Locale(lang),
          delegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          child: child!,
        );
      },
    );

    if (!mounted) return;

    if (gewaehlt != null) {
      setState(() {
        _erinnerungsDatum = gewaehlt;

        if (gewaehlt.year == now.year &&
            gewaehlt.month == now.month &&
            gewaehlt.day == now.day) {

          final int jetzigeMinuten = now.hour * 60 + now.minute;
          final int aktuelleUhrzeitMinuten = (_erinnerungsUhrzeit?.hour ?? 9) * 60 + (_erinnerungsUhrzeit?.minute ?? 0);

          if (aktuelleUhrzeitMinuten <= jetzigeMinuten) {
            final futureTime = now.add(const Duration(hours: 1));
            _erinnerungsUhrzeit = TimeOfDay(hour: futureTime.hour, minute: futureTime.minute);
          }
        }
      });
    }
  }

  Future<void> _erinnerungsZeitAuswaehlen() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lang = settings.languageCode;
    final bool useAmPm = settings.useAmPm;

    TimeOfDay initialTime = _erinnerungsUhrzeit ?? const TimeOfDay(hour: 9, minute: 0);

    if (_erinnerungsDatum != null) {
      final now = DateTime.now();
      if (_erinnerungsDatum!.year == now.year &&
          _erinnerungsDatum!.month == now.month &&
          _erinnerungsDatum!.day == now.day) {
        final int eingestellteMinuten = initialTime.hour * 60 + initialTime.minute;
        final int jetzigeMinuten = now.hour * 60 + now.minute;
        if (eingestellteMinuten <= jetzigeMinuten) {
          final future = now.add(const Duration(hours: 1));
          initialTime = TimeOfDay(hour: future.hour, minute: future.minute);
        }
      }
    }

    final TimeOfDay? gewaehlt = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: Locale(lang),
          delegates: [
            _SettingsTimeLocalizationsDelegate(lang),
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: !useAmPm),
            child: child!,
          ),
        );
      },
    );

    if (!mounted) return;

    if (gewaehlt != null) {
      if (_erinnerungsDatum != null) {
        final now = DateTime.now();
        if (_erinnerungsDatum!.year == now.year &&
            _erinnerungsDatum!.month == now.month &&
            _erinnerungsDatum!.day == now.day) {

          final int gewaehlteMinuten = gewaehlt.hour * 60 + gewaehlt.minute;
          final int jetzigeMinuten = now.hour * 60 + now.minute;

          if (gewaehlteMinuten <= jetzigeMinuten) {
            _zeigeFehler(getText(lang, 'past_time_error'));
            return;
          }
        }
      }
      setState(() => _erinnerungsUhrzeit = gewaehlt);
    }
  }

  Future<void> _kaufDatumAuswaehlen() async {
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    final DateTime? gewaehlt = await showDatePicker(
      context: context,
      initialDate: _kaufDatum,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: Locale(lang),
          delegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          child: child!,
        );
      },
    );
    if (!mounted) return;
    if (gewaehlt != null) {
      setState(() {
        _kaufDatum = gewaehlt;
        _updateReminderLimits();
      });
    }
  }

  String _formatDateStr(int d, int m, int y) {
    return '${d.toString().padLeft(2, '0')}.${m.toString().padLeft(2, '0')}.$y';
  }

  String _formatUhrzeitAnzeige(TimeOfDay time, bool useAmPm, String lang) {
    return localizeTimeOfDay(time.hour, time.minute, lang, useAmPm);
  }

  List<String> _getLadenVorschlaegeList() {
    if (widget.existingDevices == null) return [];
    List<String> stores = widget.existingDevices!
        .map((e) => e['woGekauft']?.toUpperCase() ?? '')
        .where((s) => s.isNotEmpty && s != 'UNBEKANNT')
        .toSet()
        .toList();
    if (stores.length > 1) {
      stores.insert(0, '');
    }
    return stores;
  }

  Future<void> _speichern() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lang = settings.languageCode;

    setState(() {
      _nameError = false;
      _woGekauftError = false;
      _preisError = false;
      _fotoError = false;
      _dauerError = false;
    });

    bool hasError = false;
    String errorMsg = '';

    final String name = _nameController.text.trim();
    String rawPreis = _preisController.text.trim().replaceAll(',', '.');
    final String woGekauft = _woGekauftController.text.trim().toUpperCase();

    if (!widget.isFromTutorial) {
      if (name.isEmpty) {
        _nameError = true;
        hasError = true;
        errorMsg += '${getText(lang, "error_name_missing")}\n';
      } else if (widget.existingDevices != null) {
        bool exists = widget.existingDevices!.any((d) =>
            d['name']?.toLowerCase() == name.toLowerCase() &&
            d['name'] != widget.bearbeitenGerat?['name']);
        if (exists) {
          _nameError = true;
          hasError = true;
          errorMsg += '${getText(lang, "error_name_used")}\n';
        }
      }

      double? preisVal = double.tryParse(rawPreis);
      if (rawPreis.isEmpty || preisVal == null || preisVal < 1.0) {
        _preisError = true;
        hasError = true;
        errorMsg += '${getText(lang, "error_price_invalid")}\n';
      }

      if (woGekauft.isEmpty) {
        _woGekauftError = true;
        hasError = true;
        errorMsg += '${getText(lang, "error_store_missing")}\n';
      }

      if (_istEigeneGarantieSelected) {
        int wert = int.tryParse(_eigeneGarantieController.text.trim()) ?? 0;
        if (wert <= 0 || (_eigeneGarantieEinheit == 'Wochen' && wert < 1)) {
          _dauerError = true;
          hasError = true;
          errorMsg += '${getText(lang, "error_duration_invalid")}\n';
        }
      }

      if (_bonBilder.isEmpty) {
        _fotoError = true;
        hasError = true;
        errorMsg += '${getText(lang, "error_photo_missing")}\n';
      }

      if (hasError) {
        _zeigeFehler(errorMsg.trim());
        return;
      }
    }

    DateTime ablaufDatum;
    String garantieDauerText;

    if (_istEigeneGarantieSelected) {
      int wert = int.tryParse(_eigeneGarantieController.text.trim()) ?? 1;
      if (wert > 10000) wert = 10000;

      garantieDauerText = '$wert $_eigeneGarantieEinheit';

      try {
        if (_eigeneGarantieEinheit == 'Wochen') {
          ablaufDatum = _kaufDatum.add(Duration(days: wert * 7));
        } else if (_eigeneGarantieEinheit == 'Monate') {
          int addedYears = wert ~/ 12;
          if (_kaufDatum.year + addedYears > 2099) {
            ablaufDatum = DateTime(2099, 12, 31);
          } else {
            ablaufDatum = DateTime(_kaufDatum.year, _kaufDatum.month + wert, _kaufDatum.day);
          }
        } else {
          if (_kaufDatum.year + wert > 2099) {
            ablaufDatum = DateTime(2099, 12, 31);
          } else {
            ablaufDatum = DateTime(_kaufDatum.year + wert, _kaufDatum.month, _kaufDatum.day);
          }
        }
      } catch (e) {
        ablaufDatum = DateTime(2099, 12, 31);
      }
    } else {
      garantieDauerText = _garantieOptionen[_garantieMonate] ?? '2 Jahre';
      ablaufDatum = DateTime(_kaufDatum.year, _kaufDatum.month + _garantieMonate, _kaufDatum.day);
    }

    if (ablaufDatum.year > 2099) {
      ablaufDatum = DateTime(2099, 12, 31);
    }

    final String ablaufDatumStr = _formatDateStr(ablaufDatum.day, ablaufDatum.month, ablaufDatum.year);

    String erinnerungDatenStr;
    DateTime finaleErinnerung = DateTime.now();

    if (_erinnerungNie) {
      erinnerungDatenStr = 'Nie';
    } else {
      final datePart = _erinnerungsDatum ?? ablaufDatum.subtract(const Duration(days: 14));
      final timePart = _erinnerungsUhrzeit ?? TimeOfDay.now();

      finaleErinnerung = DateTime(datePart.year, datePart.month, datePart.day, timePart.hour, timePart.minute);

      Map<String, dynamic> timerData = {
        'ausloeseZeit': finaleErinnerung.toIso8601String(),
      };
      erinnerungDatenStr = jsonEncode(timerData);
    }

    int notificationId;
    if (widget.bearbeitenGerat != null && widget.bearbeitenGerat!['notificationId'] != null) {
      notificationId = int.tryParse(widget.bearbeitenGerat!['notificationId']!) ??
          DateTime.now().millisecondsSinceEpoch.remainder(100000);
    } else {
      notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    }

    if (!_erinnerungNie) {
      final notificationGerat = <String, String>{
        'name': name,
        'woGekauft': woGekauft,
        'preis': rawPreis,
        'waehrung': _selectedWaehrung ?? '€',
        'kaufDatum': _formatDateStr(_kaufDatum.day, _kaufDatum.month, _kaufDatum.year),
        'garantieDauer': garantieDauerText,
        'kategorie': _kategorie,
        'ablaufDatum': ablaufDatumStr,
        'bemerkung': _bemerkungController.text.trim(),
      };

      await NotificationService().scheduleNotification(
        id: notificationId,
        produktName: name,
        ablaufDatumStr: ablaufDatumStr,
        benachrichtigungsDatum: finaleErinnerung,
        langCode: lang,
        gerat: notificationGerat,
      );
    } else {
      await NotificationService().cancelNotification(notificationId);
    }

    String bildPfade = _bonBilder.map((b) => b.path).join(',');

    final gueltigeBonPfade = _bonBilder.map((b) => b.path).toSet();
    final String kachelPfade = _kachelAuswahl
        .where((p) => gueltigeBonPfade.contains(p))
        .join(',');

    String bemerkungText = _bemerkungController.text.trim();

    String? existingCalendarEventId = widget.bearbeitenGerat?['calendarEventId'];
    String? existingCalendarId = widget.bearbeitenGerat?['calendarId'];
    String? newCalendarEventId = existingCalendarEventId;
    String? newCalendarId = existingCalendarId;

    if (!widget.isFromTutorial &&
        settings.preferredCalendarApp != 'ics' &&
        (settings.autoAddToCalendar || settings.autoUpdateCalendar)) {
      final description =
          'Garantie bis $ablaufDatumStr\n'
          'Gekauft bei: $woGekauft\n'
          'Kategorie: ${getText(lang, _kategorie)}';

      if (existingCalendarEventId != null && existingCalendarEventId.isNotEmpty) {
        if (settings.autoUpdateCalendar) {
          final updated = await CalendarService().updateEvent(
            eventId: existingCalendarEventId,
            calendarId: existingCalendarId,
            providerId: settings.preferredCalendarApp,
            title: name,
            description: description,
            expiryDate: ablaufDatum,
            startTime: _erinnerungNie ? null : _erinnerungsUhrzeit,
            reminderMinutes: settings.defaultReminderMinutes,
          );
          if (updated != null) {
            newCalendarEventId = updated.eventId;
            newCalendarId = updated.calendarId;
          } else {
            final created = await CalendarService().addEvent(
              title: name,
              description: description,
              expiryDate: ablaufDatum,
              startTime: _erinnerungNie ? null : _erinnerungsUhrzeit,
              providerId: settings.preferredCalendarApp,
              reminderMinutes: settings.defaultReminderMinutes,
            );
            if (created != null) {
              newCalendarEventId = created.eventId;
              newCalendarId = created.calendarId;
            }
          }
        }
      } else {
        if (settings.autoAddToCalendar) {
          final created = await CalendarService().addEvent(
            title: name,
            description: description,
            expiryDate: ablaufDatum,
            startTime: _erinnerungNie ? null : _erinnerungsUhrzeit,
            providerId: settings.preferredCalendarApp,
            reminderMinutes: settings.defaultReminderMinutes,
          );
          if (created != null) {
            newCalendarEventId = created.eventId;
            newCalendarId = created.calendarId;
          }
        }
      }
    }

    if (!mounted) return;

    Navigator.pop(context, <String, String>{
      'name': name,
      'woGekauft': woGekauft,
      'preis': rawPreis,
      'waehrung': _selectedWaehrung ?? '€',
      'kaufDatum': _formatDateStr(_kaufDatum.day, _kaufDatum.month, _kaufDatum.year),
      'garantieDauer': garantieDauerText,
      'kategorie': _kategorie,
      'ablaufDatum': ablaufDatumStr,
      'erinnerung': erinnerungDatenStr,
      'bildPfade': bildPfade,
      'kachelPfade': kachelPfade,
      'notificationId': notificationId.toString(),
      'bemerkung': bemerkungText,
      'calendarEventId': newCalendarEventId ?? '',
      'calendarId': newCalendarId ?? '',
    });
  }

  Widget _sectionHeader(IconData icon, String text, SettingsProvider settings) {
    return Row(
      children: [
        Icon(icon, color: settings.appButtonColor, size: 20),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final lang = settings.languageCode;
    final useAmPm = settings.useAmPm;

    DateTime displayDate = _erinnerungsDatum ?? _ablaufDatum.subtract(const Duration(days: 14));
    TimeOfDay displayTime = _erinnerungsUhrzeit ?? TimeOfDay.now();

    final tag = displayDate.day.toString().padLeft(2, '0');
    final monat = displayDate.month.toString().padLeft(2, '0');
    final jahr = displayDate.year.toString();

    final anzeigeZeitString = _formatUhrzeitAnzeige(displayTime, useAmPm, lang);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    bool isAblaufInVergangenheit = _ablaufDatum.isBefore(today);

    final verfuegbareLaeden = _getLadenVorschlaegeList();

    return Scaffold(
      appBar: AppBar(
        title: Text(getText(lang, 'app_title')),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: AbsorbPointer(
              absorbing: TutorialHelper.isTutorialActive,
              child: SingleChildScrollView(
                physics: TutorialHelper.isTutorialActive
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildKachel(
                      context,
                      child: Column(
                        key: _nameKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _nameController,
                            inputFormatters: [LengthLimitingTextInputFormatter(15)],
                            decoration: InputDecoration(
                              labelText: getText(lang, 'product_name'),
                              prefixIcon: const Icon(Icons.devices),
                              enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: _nameError ? Colors.red : Colors.grey)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: _nameError ? Colors.red : settings.appButtonColor, width: 2)),
                            ),
                            onChanged: (_) => setState(() => _nameError = false),
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _kategorie,
                            decoration: const InputDecoration(border: OutlineInputBorder()),
                            items: _kategorieKeys
                                .map((kat) => DropdownMenuItem(value: kat, child: Text(getText(lang, kat))))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _kategorie = val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildKachel(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            key: _kaufdetailsKey,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader(Icons.shopping_bag, getText(lang, 'buy_details'), settings),
                              const SizedBox(height: 12),

                              TextField(
                                controller: _woGekauftController,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [LengthLimitingTextInputFormatter(15)],
                                decoration: InputDecoration(
                                  labelText: getText(lang, 'bought_at'),
                                  prefixIcon: const Icon(Icons.store),
                                  suffixIcon: verfuegbareLaeden.isNotEmpty
                                      ? PopupMenuButton<String>(
                                          icon: const Icon(Icons.arrow_drop_down, size: 24),
                                          position: PopupMenuPosition.under,
                                          onSelected: (String newValue) {
                                            setState(() {
                                              _woGekauftController.text = newValue;
                                              _woGekauftError = false;
                                            });
                                          },
                                          itemBuilder: (BuildContext context) {
                                            return verfuegbareLaeden.map((laden) {
                                              return PopupMenuItem<String>(
                                                value: laden,
                                                child: ConstrainedBox(
                                                  constraints: const BoxConstraints(maxWidth: 150),
                                                  child: Text(
                                                    laden.isEmpty ? getText(lang, 'select_empty') : laden,
                                                    overflow: TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                              );
                                            }).toList();
                                          },
                                        )
                                      : null,
                                  enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: _woGekauftError ? Colors.red : Colors.grey)),
                                  focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                          color: _woGekauftError ? Colors.red : settings.appButtonColor, width: 2)),
                                ),
                                onChanged: (_) => setState(() => _woGekauftError = false),
                              ),

                              const SizedBox(height: 16),

                              TextField(
                                controller: _preisController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*[,.]?\d*')),
                                  LengthLimitingTextInputFormatter(15),
                                ],
                                decoration: InputDecoration(
                                  labelText: getText(lang, 'price'),
                                  prefixIcon: const Icon(Icons.payments),
                                  suffixIcon: PopupMenuButton<String>(
                                    icon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_selectedWaehrung ?? '€',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        const Icon(Icons.arrow_drop_down, size: 20),
                                      ],
                                    ),
                                    position: PopupMenuPosition.under,
                                    onSelected: (String newValue) {
                                      setState(() => _selectedWaehrung = newValue);
                                    },
                                    itemBuilder: (BuildContext context) {
                                      return appCurrencies.map((c) {
                                        return PopupMenuItem<String>(
                                          value: c['symbol'],
                                          child: Text('${getText(lang, c['label_key']!)} (${c['symbol']})'),
                                        );
                                      }).toList();
                                    },
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: _preisError ? Colors.red : Colors.grey)),
                                  focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                          color: _preisError ? Colors.red : settings.appButtonColor, width: 2)),
                                ),
                                onChanged: (_) => setState(() => _preisError = false),
                              ),

                              const SizedBox(height: 16),

                              InkWell(
                                onTap: _kaufDatumAuswaehlen,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(4)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                          '${_kaufDatum.day.toString().padLeft(2, '0')}.${_kaufDatum.month.toString().padLeft(2, '0')}.${_kaufDatum.year}',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      Icon(Icons.calendar_today, color: settings.appButtonColor),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Column(
                            key: _garantieKey,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionHeader(Icons.timer, getText(lang, 'warranty_duration'), settings),
                              const SizedBox(height: 8),

                              Wrap(
                                spacing: 8.0,
                                children: [
                                  ..._garantieOptionen.entries.map((entry) {
                                    return ChoiceChip(
                                      label: Text(localizeDuration(entry.value, lang)),
                                      selected: !_istEigeneGarantieSelected && _garantieMonate == entry.key,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() {
                                            _istEigeneGarantieSelected = false;
                                            _garantieMonate = entry.key;
                                            _updateReminderLimits();
                                          });
                                        }
                                      },
                                    );
                                  }),
                                  ChoiceChip(
                                    label: Text(getText(lang, 'own_duration')),
                                    selected: _istEigeneGarantieSelected,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _istEigeneGarantieSelected = true;
                                          _berechneEigeneGarantie();
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),

                              if (_istEigeneGarantieSelected) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: _eigeneGarantieController,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(4)
                                        ],
                                        decoration: InputDecoration(
                                          labelText: getText(lang, 'duration'),
                                          enabledBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: _dauerError ? Colors.red : Colors.grey)),
                                          focusedBorder: OutlineInputBorder(
                                              borderSide: BorderSide(
                                                  color: _dauerError ? Colors.red : settings.appButtonColor,
                                                  width: 2)),
                                        ),
                                        onChanged: (wert) {
                                          setState(() => _dauerError = false);
                                          _berechneEigeneGarantie();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      flex: 3,
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _eigeneGarantieEinheit,
                                        decoration: InputDecoration(
                                            labelText: getText(lang, 'unit'),
                                            border: const OutlineInputBorder()),
                                        items: ['Wochen', 'Monate', 'Jahre']
                                            .map((e) => DropdownMenuItem(
                                                value: e, child: Text(getText(lang, e.toLowerCase()))))
                                            .toList(),
                                        onChanged: (neu) {
                                          if (neu != null) {
                                            setState(() {
                                              _eigeneGarantieEinheit = neu;
                                              _dauerError = false;
                                              _berechneEigeneGarantie();
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: settings.appButtonColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(
                                  '${getText(lang, 'expiry_date')}: ${_ablaufDatum.day.toString().padLeft(2, '0')}.${_ablaufDatum.month.toString().padLeft(2, '0')}.${_ablaufDatum.year}',
                                  style: TextStyle(color: settings.appButtonColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          TextField(
                            controller: _bemerkungController,
                            maxLines: 3,
                            maxLength: 500,
                            decoration: InputDecoration(
                              labelText: getText(lang, 'remarks'),
                              hintText: getText(lang, 'remarks_hint'),
                              border: const OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildKachel(
                      context,
                      child: Column(
                        key: _timerKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _sectionHeader(
                                  Icons.notifications_active, getText(lang, 'set_reminder'), settings),
                              Row(
                                children: [
                                  Text(getText(lang, 'never')),
                                  Checkbox(
                                    value: _erinnerungNie,
                                    onChanged: isAblaufInVergangenheit
                                        ? null
                                        : (val) {
                                            setState(() {
                                              _erinnerungNie = val ?? false;
                                            });
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),

                          if (!_erinnerungNie) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: _erinnerungsDatumAuswaehlen,
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade400),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('$tag.$monat.$jahr',
                                              style: const TextStyle(
                                                  fontSize: 15, fontWeight: FontWeight.w600)),
                                          Icon(Icons.calendar_month,
                                              color: settings.appButtonColor, size: 20),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: _erinnerungsZeitAuswaehlen,
                                    child: Container(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey.shade400),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(anzeigeZeitString,
                                              style: const TextStyle(
                                                  fontSize: 15, fontWeight: FontWeight.w600)),
                                          const Icon(Icons.access_time,
                                              color: Colors.orangeAccent, size: 20),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildKachel(
                      context,
                      child: Column(
                        key: _fotosKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  _sectionHeader(
                                      Icons.receipt_long, getText(lang, 'photos'), settings),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(
                                      _showFotoInfo ? Icons.info : Icons.info_outline,
                                      color: settings.appButtonColor,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      setState(() {
                                        _showFotoInfo = !_showFotoInfo;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text('${_bonBilder.length} / 4',
                                      style: const TextStyle(
                                          color: Colors.grey, fontWeight: FontWeight.bold)),
                                  if (_kachelAuswahl.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star, size: 12, color: Colors.amber),
                                          const SizedBox(width: 2),
                                          Text('${_kachelAuswahl.length}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.amber.shade800,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          if (_showFotoInfo) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: settings.appButtonColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                getText(lang, 'photo_info_text'),
                                style: TextStyle(fontSize: 13, color: settings.appButtonColor),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              getText(lang, 'tile_preview_hint'),
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          ),
                          const SizedBox(height: 12),

                          Container(
                            padding: _fotoError ? const EdgeInsets.all(8) : EdgeInsets.zero,
                            decoration: _fotoError
                                ? BoxDecoration(
                                    border: Border.all(color: Colors.red, width: 2),
                                    borderRadius: BorderRadius.circular(8))
                                : null,
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ..._bonBilder.map((bild) {
                                  final bool isPreview = _kachelAuswahl.contains(bild.path);
                                  return SizedBox(
                                    width: 100,
                                    height: 100,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: GestureDetector(
                                            onTap: () => _zeigeBildVollbild(bild.path),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 180),
                                              curve: Curves.easeOut,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: isPreview ? Colors.amber : Colors.transparent,
                                                  width: 2.5,
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(6),
                                                child: kIsWeb
                                                    ? Image.network(bild.path, fit: BoxFit.cover, key: ValueKey('${bild.path}_${_imageVersions[bild.path] ?? 0}'))
                                                    : Image.file(File(bild.path), fit: BoxFit.cover, key: ValueKey('${bild.path}_${_imageVersions[bild.path] ?? 0}')),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          left: 4,
                                          child: GestureDetector(
                                            onTap: () => _toggleKachelAuswahl(bild.path),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 180),
                                              curve: Curves.easeOut,
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: isPreview ? Colors.amber : Colors.black54,
                                                shape: BoxShape.circle,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: 0.2),
                                                    blurRadius: 3,
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                isPreview ? Icons.star : Icons.star_border,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          right: 4,
                                          child: GestureDetector(
                                            onTap: () => setState(() {
                                              _bonBilder.remove(bild);
                                              _kachelAuswahl.remove(bild.path);
                                            }),
                                            child: Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: const BoxDecoration(
                                                  color: Colors.red, shape: BoxShape.circle),
                                              child: const Icon(Icons.close,
                                                  size: 14, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                if (_bonBilder.length < 4)
                                  InkWell(
                                    onTap: () => _zeigeFotoOptionen(lang),
                                    child: Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).scaffoldBackgroundColor,
                                        border: Border.all(color: Colors.grey.shade400),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Center(
                                        child: Icon(Icons.add_a_photo,
                                            color: settings.appButtonColor, size: 24),
                                      ),
                                    ),
                                  )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        key: _saveKey,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: settings.appButtonColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(Icons.save, color: settings.onAppButtonColor),
                        onPressed: _speichern,
                        label: Text(getText(lang, 'save'),
                            style: TextStyle(fontSize: 18, color: settings.onAppButtonColor)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKachel(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}