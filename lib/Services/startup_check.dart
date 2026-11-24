import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'settings_provider.dart';

/// Prüft beim App-Start, ob alle erwarteten Asset-Dateien vorhanden sind.
/// Dart-Dateien (Screens usw.) werden beim Build geprüft und können zur
/// Laufzeit nicht fehlen – darum werden hier die Assets geprüft.
/// Weitere Pflichtdateien (z. B. vom Splash-Screen) einfach unten eintragen.
class StartupCheck {
  static const List<String> requiredAssets = [
    'assets/logo.png',
    'assets/DSVG_DE.txt',
    'assets/DSVG_ENG.txt',
    'assets/DSVG_FR.txt',
    'assets/DSVG_ES.txt',
  ];

  static Future<List<String>> findMissingFiles() async {
    final List<String> missing = [];
    for (final path in requiredAssets) {
      try {
        await rootBundle.load(path);
      } catch (_) {
        missing.add(path);
      }
    }
    return missing;
  }
}

/// Fehlerscreen: Dark Mode = weisser Hintergrund + schwarze Schrift,
/// heller Modus = schwarzer Hintergrund + weisse Schrift.
class StartupErrorScreen extends StatefulWidget {
  final List<String> missingFiles;
  final Widget Function() nextScreenBuilder;

  const StartupErrorScreen({
    super.key,
    required this.missingFiles,
    required this.nextScreenBuilder,
  });

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _stillMissing = false;
  bool _checking = false;
  late List<String> _missing;

  @override
  void initState() {
    super.initState();
    _missing = List.from(widget.missingFiles);
  }

  Future<void> _erneutPruefen() async {
    setState(() => _checking = true);
    final result = await StartupCheck.findMissingFiles();
    if (!mounted) return;
    if (result.isEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => widget.nextScreenBuilder()),
      );
    } else {
      setState(() {
        _missing = result;
        _stillMissing = true;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? Colors.white : Colors.black;
    final Color fg = isDark ? Colors.black : Colors.white;

    String lang = 'de';
    try {
      lang = Provider.of<SettingsProvider>(context).languageCode;
    } catch (_) {}

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 72, color: fg),
                  const SizedBox(height: 16),
                  Text(
                    getText(lang, 'startup_error_title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    getText(lang, 'startup_error_desc'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      getText(lang, 'startup_missing_files'),
                      style: TextStyle(color: fg, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final f in _missing)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $f', style: TextStyle(color: fg, fontSize: 14)),
                      ),
                    ),
                  if (_stillMissing) ...[
                    const SizedBox(height: 12),
                    Text(
                      getText(lang, 'startup_still_missing'),
                      style: TextStyle(color: fg, fontWeight: FontWeight.bold),
                    ),
                  ],
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: fg,
                      side: BorderSide(color: fg, width: 1.5),
                      minimumSize: const Size(200, 48),
                    ),
                    onPressed: _checking ? null : _erneutPruefen,
                    icon: const Icon(Icons.refresh),
                    label: Text(getText(lang, 'startup_retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}