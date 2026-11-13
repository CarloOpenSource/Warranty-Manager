import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../Services/calender_service.dart';
import 'calendar_settings_dialog.dart';
import 'gesture_settings_screen.dart';
import 'notification_settings_screen.dart'; 
import '../Services/settings_provider.dart';
import 'color_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onRestartTutorial;
  final VoidCallback onAllDataDeleted;
  final VoidCallback onDataImported;

  const SettingsScreen({
    super.key,
    required this.onRestartTutorial,
    required this.onAllDataDeleted,
    required this.onDataImported,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  void _onVersionTap(
      BuildContext context, SettingsProvider settings, String lang) {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;

    if (_versionTapCount >= 3) {
      _versionTapCount = 0;
      if (!settings.colorPickerUnlocked) {
        settings.unlockColorPicker();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getText(lang, 'color_unlocked'))),
        );
      }
    }
  }

  Future<String> _getAppVersion() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      if (version.isNotEmpty) return version;
      return '1.0.1';
    } catch (e) {
      return '1.0.1';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final lang = settings.languageCode;

    final systemIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final isDarkMode = settings.themeMode == ThemeMode.dark ||
        (settings.themeMode == ThemeMode.system && systemIsDark);

    final is12h = settings.useAmPm;

    return Scaffold(
      appBar: AppBar(
        title: Text(getText(lang, 'settings')),
      ),
      body: SafeArea(
  top: false,
  child: Align(
    alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Tutorial neu starten ─────────────────────
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.school, color: Colors.orange),
                    title: Text(getText(lang, 'tutorial_restart')),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: widget.onRestartTutorial,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Erscheinungsbild ─────────────────────────
                Text(
                  getText(lang, 'appearance'),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: settings.appButtonColor),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      // 1. Dark Mode
                      SwitchListTile(
                        title: Text(getText(lang, 'dark_mode')),
                        subtitle: Text(getText(lang, 'dark_mode_desc')),
                        secondary: Icon(
                            isDarkMode ? Icons.dark_mode : Icons.light_mode,
                            color: Colors.indigo),
                        value: isDarkMode,
                        onChanged: (bool value) {
                          settings.setThemeMode(
                              value ? ThemeMode.dark : ThemeMode.light);
                        },
                      ),
                      const Divider(height: 1),

                      // 2. 12h / 24h
                      SwitchListTile(
                        title: Text(is12h
                            ? getText(lang, 'switch_to_24h')
                            : getText(lang, 'switch_to_12h')),
                        secondary: const Icon(Icons.access_time,
                            color: Colors.orangeAccent),
                        value: is12h,
                        onChanged: (bool value) {
                          settings.setUseAmPm(value);
                        },
                      ),
                      const Divider(height: 1),

                      // 3. Sortierung
                      ListTile(
                        leading:
                            const Icon(Icons.sort, color: Colors.deepPurple),
                        title: Text(getText(lang, 'sort_by')),
                        trailing: Text(
                          _getSortName(lang, settings.sortOrder),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onTap: () {
                          _zeigeSortierungsAuswahl(context, settings);
                        },
                      ),
                      const Divider(height: 1),

                      // 4. Sprache
                      ListTile(
                        leading: Icon(Icons.language,
                            color: settings.appButtonColor),
                        title: Text(getText(lang, 'language')),
                        trailing: Text(_getLanguageName(lang),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) {
                              return SafeArea(
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding:
                                            const EdgeInsets.all(16.0),
                                        child: Text(
                                          getText(lang, 'select_language'),
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const Divider(height: 1),
                                      ListTile(
                                          title: const Text('Deutsch'),
                                          onTap: () {
                                            settings.setLanguage('de');
                                            Navigator.pop(context);
                                          }),
                                      ListTile(
                                          title: const Text('English'),
                                          onTap: () {
                                            settings.setLanguage('en');
                                            Navigator.pop(context);
                                          }),
                                      ListTile(
                                          title: const Text('Français'),
                                          onTap: () {
                                            settings.setLanguage('fr');
                                            Navigator.pop(context);
                                          }),
                                      ListTile(
                                          title: const Text('Español'),
                                          onTap: () {
                                            settings.setLanguage('es');
                                            Navigator.pop(context);
                                          }),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const Divider(height: 1),

                      // 5. Währung
                      ListTile(
                        leading:
                            const Icon(Icons.attach_money, color: Colors.green),
                        title: Text(getText(lang, 'currency')),
                        trailing: Text(
                          settings.currencySymbol,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        onTap: () {
                          _zeigeWaehrungsAuswahl(context, settings);
                        },
                      ),
                      const Divider(height: 1),

                      // 6. Wischgesten
                      ListTile(
                        leading: const Icon(Icons.swipe, color: Colors.teal),
                        title: Text(getText(lang, 'swipe_actions')),
                        subtitle: Text(getText(lang, 'swipe_actions_desc')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const GestureSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),

                      // 7. Kalender-Einstellungen
                      ListTile(
                        leading: Icon(Icons.calendar_month,
                            color: settings.appButtonColor),
                        title: Text(getText(lang, 'calendar_settings')),
                        subtitle:
                            Text(getText(lang, 'calendar_settings_desc')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const CalendarSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),

                      // >>> NEU: Benachrichtigungen
                      ListTile(
                        leading: Icon(Icons.notifications_active,
                            color: settings.appButtonColor),
                        title: Text(getText(lang, 'notif_settings')),
                        subtitle:
                            Text(getText(lang, 'notif_settings_desc')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const NotificationSettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Farb-Einstellungen (nur wenn freigeschaltet) ──
                if (settings.colorPickerUnlocked) ...[
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading:
                          Icon(Icons.palette, color: settings.appButtonColor),
                      title: Text(getText(lang, 'color_settings')),
                      subtitle: Text(getText(lang, 'color_settings_desc')),
                      trailing:
                          const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) =>
                                  const ColorSettingsScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Datenverwaltung ──────────────────────────
                Text(
                  getText(lang, 'data_management'),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: settings.appButtonColor),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      ListTile(
                        leading:
                            const Icon(Icons.upload_file, color: Colors.teal),
                        title: Text(getText(lang, 'export_data')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          _exportieren(context, lang);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.download_for_offline,
                            color: Colors.amber),
                        title: Text(getText(lang, 'import_data')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          _importieren(context, settings, lang);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.delete_forever,
                            color: Colors.redAccent),
                        title: Text(
                          getText(lang, 'delete_all_data'),
                          style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios,
                            size: 16, color: Colors.redAccent),
                        onTap: () {
                          _alleDatenLoeschen(context, settings, lang);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Info ─────────────────────────────────────
                Text(
                  getText(lang, 'info'),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: settings.appButtonColor),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline,
                            color: settings.appButtonColor),
                        title: Text(getText(lang, 'app_version')),
                        onTap: () => _onVersionTap(context, settings, lang),
                        trailing: FutureBuilder<String>(
                          future: _getAppVersion(),
                          builder: (context, snapshot) {
                            final versionText = snapshot.hasData ? 'v${snapshot.data}' : getText(lang, 'loading');
                            return Text(
                              versionText,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.security,
                            color: Colors.deepOrange),
                        title: Text(getText(lang, 'privacy_policy')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          _zeigeDatenschutzerklaerung(context, lang);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.gavel, color: Colors.purple),
                        title: Text(getText(lang, 'imprint')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          _zeigeImpressum(context, lang);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.code, color: Colors.grey),
                        title: Text(getText(lang, 'licenses')),
                        trailing:
                            const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () async {
                          final version = await _getAppVersion();
                          if (!context.mounted) return;

                          showLicensePage(
                            context: context,
                            applicationName: getText(lang, 'app_title'),
                            applicationVersion: 'v$version',
                            applicationIcon: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Image.asset('assets/logo.png',
                                  width: 64, height: 64),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    )
    );
  }

  void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Future<void> _exportieren(BuildContext context, String lang) async {
    final wahl = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(getText(lang, 'export_data')),
          content: Text(getText(lang, 'export_method_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'share'),
              child: Text(getText(lang, 'export_share')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: Text(getText(lang, 'export_save')),
            ),
          ],
        );
      },
    );

    if (wahl == null) return;

    if (!context.mounted) return;
    _showLoading(context);
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();

      final stagingDir = Directory('${tempDir.path}/WarrantyManager_Staging');
      if (stagingDir.existsSync()) {
        stagingDir.deleteSync(recursive: true);
      }
      stagingDir.createSync();

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final prefsMap = <String, dynamic>{};
      for (String key in prefs.getKeys()) {
        prefsMap[key] = prefs.get(key);
      }
      final prefsFile = File('${stagingDir.path}/prefs_backup.json');
      await prefsFile.writeAsString(jsonEncode(prefsMap));

      if (docDir.existsSync()) {
        for (var entity in docDir.listSync(recursive: false)) {
          if (entity is File) {
            final fileName = entity.path.split(Platform.pathSeparator).last;
            if (fileName.isNotEmpty) {
              entity.copySync('${stagingDir.path}/$fileName');
            }
          }
        }
      }

      final zipPath = '${tempDir.path}/WarrantyManager_Backup.zip';

      await Future(() {
        var encoder = ZipFileEncoder();
        encoder.create(zipPath);
        encoder.addDirectorySync(stagingDir, includeDirName: false);
        encoder.closeSync();
      });

      if (!context.mounted) return;
      Navigator.pop(context);

      if (wahl == 'save') {
        final bytes = File(zipPath).readAsBytesSync();
        final saveResult = await FilePicker.saveFile(
          dialogTitle: getText(lang, 'backup_save_title'),
          fileName: 'WarrantyManager_Backup.zip',
          bytes: bytes,
        );

        if (saveResult != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(getText(lang, 'export_success'))),
          );
        }
      } else {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile(zipPath)],
            text: getText(lang, 'backup_share_text'),
          ),
        );

        if (result.status == ShareResultStatus.success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(getText(lang, 'export_success'))),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(getText(lang, 'export_error')),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  static const List<String> _knownPrefKeys = [
    'gerate_liste',
    'is_first_start',
    'app_language',
    'currency_symbol',
    'sort_order',
    'theme_mode',
    'use_am_pm',
    'accent_color',
    'accent_button_color',
    'accent_saved_colors',
    'accent_unlocked',
    'use_swipe_actions',
    'swipe_right_action',
    'swipe_left_action',
    'auto_add_to_calendar',
    'auto_update_calendar',
    'preferred_calendar_app',
    'default_reminder_minutes',
    'notif_template', // >>> NEU
  ];

  Future<void> _importieren(
      BuildContext context, SettingsProvider settings, String lang) async {
    final wahl = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(getText(lang, 'import_data')),
          content: Text(getText(lang, 'import_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(getText(lang, 'cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(getText(lang, 'import_select_file')),
            ),
          ],
        );
      },
    );

    if (wahl != true) return;

    List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (files.isNotEmpty && context.mounted) {
      _showLoading(context);
      await Future.delayed(const Duration(milliseconds: 50));

      try {
        final Uint8List bytes = await files.single.readAsBytes();

        final tempDir = await getTemporaryDirectory();
        final extractPath = Directory('${tempDir.path}/extracted_backup');

        if (extractPath.existsSync()) {
          extractPath.deleteSync(recursive: true);
        }
        extractPath.createSync();

        bool zipReadable = true;
        int unreadableFiles = 0;

        await Future(() {
          Archive archive;
          try {
            archive = ZipDecoder().decodeBytes(bytes);
          } catch (_) {
            zipReadable = false;
            return;
          }

          for (final file in archive) {
            try {
              final filename = file.name;
              if (file.isFile) {
                final data = file.content as List<int>;
                final cleanName =
                    filename.replaceAll('\\', '/').split('/').last;
                if (cleanName.isNotEmpty) {
                  final outFile = File('${extractPath.path}/$cleanName');
                  outFile.createSync(recursive: true);
                  outFile.writeAsBytesSync(data);
                }
              }
            } catch (_) {
              unreadableFiles++;
            }
          }
        });

        if (!zipReadable) {
          throw const FormatException('zip not readable');
        }

        final docDir = await getApplicationDocumentsDirectory();
        final prefsFile = File('${extractPath.path}/prefs_backup.json');

        Map<String, dynamic>? prefsMap;
        if (prefsFile.existsSync()) {
          try {
            final decoded = jsonDecode(prefsFile.readAsStringSync());
            if (decoded is Map) {
              prefsMap = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {
            prefsMap = null;
          }
        }

        final bool kompatibel =
            prefsMap != null && prefsMap.keys.any(_knownPrefKeys.contains);

        if (!kompatibel) {
          try {
            extractPath.deleteSync(recursive: true);
          } catch (_) {}
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(getText(lang, 'import_error_incompatible')),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          return;
        }

        final Map<String, dynamic> backup = prefsMap;

        int skippedEntries = 0;
        int missingImages = 0;
        bool listUnreadable = false;
        String? neueListeJson;

        if (backup.containsKey('gerate_liste')) {
          try {
            final rawListe = backup['gerate_liste'];
            if (rawListe is! String) throw const FormatException('list');
            final decodedListe = jsonDecode(rawListe);
            if (decodedListe is! List) throw const FormatException('list');

            final List<Map<String, dynamic>> gueltige = [];
            for (final g in decodedListe) {
              final bool gueltig = g is Map &&
                  g.values.every((v) => v is String) &&
                  (g['name']?.toString().trim().isNotEmpty ?? false);

              if (!gueltig) {
                skippedEntries++;
                continue;
              }

              final entry = Map<String, dynamic>.from(g);

// Pfad-Felder remappen (bildPfade + kachelPfade)
String remapDateiname(String p) {
  String fileName = p.trim();
  if (fileName.contains('/')) {
    fileName = fileName.split('/').last;
  }
  if (fileName.contains('\\')) {
    fileName = fileName.split('\\').last;
  }
  if (fileName.isNotEmpty &&
      !File('${extractPath.path}/$fileName').existsSync() &&
      !File('${docDir.path}/$fileName').existsSync()) {
    missingImages++;
  }
  return fileName;
}

for (final field in ['bildPfade', 'kachelPfade']) {
  final pfade = entry[field]?.toString() ?? '';
  if (pfade.isEmpty) continue;

  final teile = pfade.split(',');
  final neuePfade = teile.map((p) {
    final fileName = remapDateiname(p);
    return '${docDir.path}/$fileName';
  }).join(',');

  entry[field] = neuePfade;
}

// Zugeschnittene Foto-Kopien (bildBearbeitungen) remappen: sowohl der
// Original-Pfad (Schlüssel) als auch der Pfad der bearbeiteten Kopie
// (Wert 'edited') müssen auf Dateien im neuen App-Dokumentenordner zeigen.
final rohBearbeitungen = entry['bildBearbeitungen']?.toString() ?? '';
if (rohBearbeitungen.isNotEmpty) {
  try {
    final decodedBearbeitungen = jsonDecode(rohBearbeitungen);
    if (decodedBearbeitungen is Map) {
      final neueBearbeitungen = <String, dynamic>{};
      decodedBearbeitungen.forEach((key, value) {
        final neuerOriginalName = remapDateiname(key.toString());
        if (neuerOriginalName.isEmpty) return;
        final neuerOriginalPfad = '${docDir.path}/$neuerOriginalName';

        if (value is Map) {
          final altEdited = value['edited']?.toString() ?? '';
          String neuerEditedPfad = '';
          if (altEdited.isNotEmpty) {
            final neuerEditedName = remapDateiname(altEdited);
            if (neuerEditedName.isNotEmpty) {
              neuerEditedPfad = '${docDir.path}/$neuerEditedName';
            }
          }
          neueBearbeitungen[neuerOriginalPfad] = {
            'edited': neuerEditedPfad,
            'count': value['count']?.toString() ?? '0',
          };
        }
      });
      entry['bildBearbeitungen'] =
          neueBearbeitungen.isEmpty ? '' : jsonEncode(neueBearbeitungen);
    } else {
      entry['bildBearbeitungen'] = '';
    }
  } catch (_) {
    entry['bildBearbeitungen'] = '';
  }
}

gueltige.add(entry);
            }

            if (gueltige.isEmpty && skippedEntries > 0) {
              listUnreadable = true;
            } else {
              neueListeJson = jsonEncode(gueltige);
            }
          } catch (_) {
            listUnreadable = true;
            neueListeJson = null;
          }
        }

        final prefs = await SharedPreferences.getInstance();
        final bool wasUnlocked = prefs.getBool('accent_unlocked') ?? false;
        final String? bisherigeListe = prefs.getString('gerate_liste');
        await prefs.clear();

        for (final key in backup.keys) {
          final value = backup[key];

          if (key == 'gerate_liste') {
            if (neueListeJson != null) {
              await prefs.setString(key, neueListeJson);
            }
          } else {
            if (value is bool) {
              await prefs.setBool(key, value);
            } else if (value is int) {
              await prefs.setInt(key, value);
            } else if (value is double) {
              await prefs.setDouble(key, value);
            } else if (value is String) {
              await prefs.setString(key, value);
            } else if (value is List) {
              await prefs.setStringList(
                  key, value.map((e) => e.toString()).toList());
            }
          }
        }

        if (listUnreadable && bisherigeListe != null) {
          await prefs.setString('gerate_liste', bisherigeListe);
        }

        int copyFailures = 0;
        await Future(() {
          final extractedDir = Directory(extractPath.path);
          for (final entity in extractedDir.listSync(recursive: true)) {
            if (entity is File && !entity.path.endsWith('prefs_backup.json')) {
              final filename = entity.path.split(Platform.pathSeparator).last;
              if (filename.isNotEmpty) {
                try {
                  final targetFile = File('${docDir.path}/$filename');
                  entity.copySync(targetFile.path);
                } catch (_) {
                  copyFailures++;
                }
              }
            }
          }
        });

        if (wasUnlocked) {
          final p = await SharedPreferences.getInstance();
          await p.setBool('accent_unlocked', true);
        }

        try {
          final providers = await CalendarService().getAvailableProviders();
          final importedApp = prefs.getString('preferred_calendar_app');
          final available = providers.any((p) => p.id == importedApp);
          if (!available && importedApp != 'ics' && importedApp != null) {
            if (providers.isNotEmpty) {
              await prefs.setString(
                  'preferred_calendar_app', providers.first.id);
            } else {
              await prefs.setString('preferred_calendar_app', 'ics');
              await prefs.setBool('auto_add_to_calendar', false);
              await prefs.setBool('auto_update_calendar', false);
            }
          }
        } catch (_) {
          await prefs.setString('preferred_calendar_app', 'ics');
          await prefs.setBool('auto_add_to_calendar', false);
          await prefs.setBool('auto_update_calendar', false);
        }

        await settings.loadSettings();

        try {
          extractPath.deleteSync(recursive: true);
        } catch (_) {}

        final int fileProblems = unreadableFiles + copyFailures;
        final bool teilweise = listUnreadable ||
            skippedEntries > 0 ||
            missingImages > 0 ||
            fileProblems > 0;

        if (context.mounted) {
          Navigator.pop(context);

          if (teilweise) {
            final meldung = StringBuffer(getText(lang, 'import_partial'));
            if (listUnreadable) {
              meldung.write('\n• ${getText(lang, 'import_partial_list')}');
            } else if (skippedEntries > 0) {
              meldung.write(
                  '\n• ${getText(lang, 'import_partial_entries')}$skippedEntries');
            }
            if (missingImages > 0) {
              meldung.write(
                  '\n• ${getText(lang, 'import_partial_images')}$missingImages');
            }
            if (fileProblems > 0) {
              meldung.write(
                  '\n• ${getText(lang, 'import_partial_files')}$fileProblems');
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(meldung.toString()),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 10),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(getText(lang, 'import_success'))),
            );
          }
          widget.onDataImported();
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(getText(lang, 'import_error')),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _alleDatenLoeschen(
      BuildContext context, SettingsProvider settings, String lang) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(getText(lang, 'delete_all_title')),
          content: Text(
            getText(lang, 'delete_all_desc'),
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(getText(lang, 'cancel')),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                await settings.deleteAllData();

                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('gerate_liste');
                await prefs.setBool('is_first_start', true);

                try {
                  final docDir = await getApplicationDocumentsDirectory();
                  if (docDir.existsSync()) {
                    for (var entity in docDir.listSync()) {
                      if (entity is File) {
                        entity.deleteSync();
                      } else if (entity is Directory) {
                        entity.deleteSync(recursive: true);
                      }
                    }
                  }
                } catch (e) {
                  // ignorieren
                }
                await settings.loadSettings();
                if (context.mounted) {
                  widget.onAllDataDeleted();
                }
              },
              child: Text(
                getText(lang, 'delete_all_confirm'),
                style: const TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _zeigeImpressum(BuildContext context, String lang) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(getText(lang, 'imprint_title')),
          content: SingleChildScrollView(
            child: Text(
              getText(lang, 'imprint_text'),
              style: const TextStyle(height: 1.4),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(getText(lang, 'ok')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _zeigeDatenschutzerklaerung(
      BuildContext context, String lang) async {
    bool isOnline = false;

    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        isOnline = true;
      }
    } on SocketException catch (_) {
      isOnline = false;
    } catch (_) {
      isOnline = false;
    }

    if (isOnline) {
      final Uri url = Uri.parse(
          'https://sites.google.com/view/privacy-policy-warrantymanager/home');

      try {
        final launched = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {
        // Offline-Fallback
      }
    }

    String assetPath;
    switch (lang) {
      case 'en':
        assetPath = 'assets/DSVG_ENG.txt';
        break;
      case 'fr':
        assetPath = 'assets/DSVG_FR.txt';
        break;
      case 'es':
        assetPath = 'assets/DSVG_ES.txt';
        break;
      case 'de':
      default:
        assetPath = 'assets/DSVG_DE.txt';
        break;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(getText(lang, 'privacy_policy_title')),
          content: SizedBox(
            width: double.maxFinite,
            child: FutureBuilder<String>(
              future:
                  DefaultAssetBundle.of(dialogContext).loadString(assetPath),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(getText(lang, 'error_loading_file'));
                }
                return SingleChildScrollView(
                  child: Text(
                    snapshot.data ?? '',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(getText(lang, 'ok')),
            ),
          ],
        );
      },
    );
  }

  void _zeigeSortierungsAuswahl(
      BuildContext context, SettingsProvider settings) {
    final lang = settings.languageCode;
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(getText(lang, 'sort_a_z')),
                trailing: settings.sortOrder == 'a_z'
                    ? Icon(Icons.check, color: settings.appButtonColor)
                    : null,
                onTap: () {
                  settings.setSortOrder('a_z');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(getText(lang, 'sort_z_a')),
                trailing: settings.sortOrder == 'z_a'
                    ? Icon(Icons.check, color: settings.appButtonColor)
                    : null,
                onTap: () {
                  settings.setSortOrder('z_a');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(getText(lang, 'sort_newest')),
                trailing: settings.sortOrder == 'newest'
                    ? Icon(Icons.check, color: settings.appButtonColor)
                    : null,
                onTap: () {
                  settings.setSortOrder('newest');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(getText(lang, 'sort_oldest')),
                trailing: settings.sortOrder == 'oldest'
                    ? Icon(Icons.check, color: settings.appButtonColor)
                    : null,
                onTap: () {
                  settings.setSortOrder('oldest');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(getText(lang, 'sort_expiry')),
                trailing: settings.sortOrder == 'expiry_asc'
                    ? Icon(Icons.check, color: settings.appButtonColor)
                    : null,
                onTap: () {
                  settings.setSortOrder('expiry_asc');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _zeigeWaehrungsAuswahl(
      BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    getText(settings.languageCode, 'currency'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: appCurrencies.length,
                    itemBuilder: (context, index) {
                      final item = appCurrencies[index];
                      final isSelected =
                          settings.currencySymbol == item['symbol'];

                      return ListTile(
                        title: Text(
                            '${getText(settings.languageCode, item['label_key']!)} (${item['symbol']})'),
                        trailing: isSelected
                            ? Icon(Icons.check,
                                color: settings.appButtonColor)
                            : Text(item['symbol']!,
                                style: const TextStyle(color: Colors.grey)),
                        onTap: () {
                          settings.setCurrency(item['symbol']!);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _getSortName(String lang, String order) {
    switch (order) {
      case 'z_a':
        return getText(lang, 'sort_z_a');
      case 'newest':
        return getText(lang, 'sort_newest');
      case 'oldest':
        return getText(lang, 'sort_oldest');
      case 'expiry_asc':
        return getText(lang, 'sort_expiry');
      case 'a_z':
      default:
        return getText(lang, 'sort_a_z');
    }
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'fr':
        return 'Français';
      case 'es':
        return 'Español';
      case 'de':
      default:
        return 'Deutsch';
    }
  }
}