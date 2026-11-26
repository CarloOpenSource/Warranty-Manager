import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Services/settings_provider.dart';

/// Separater Screen zur Auswahl der Standard-Währung und der bis zu 10
/// verfügbaren Währungen (für die Preis-Auswahl in add_screen).
class CurrencySelectionScreen extends StatefulWidget {
  const CurrencySelectionScreen({super.key});

  @override
  State<CurrencySelectionScreen> createState() => _CurrencySelectionScreenState();
}

class _CurrencySelectionScreenState extends State<CurrencySelectionScreen> {
  late String _standard;
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _standard = settings.currencySymbol;
    _selected = List<String>.from(settings.selectedCurrencies);
    if (!_selected.contains(_standard)) {
      _selected.add(_standard);
    }
  }

  void _toggle(String symbol, bool? val) {
    setState(() {
      if (val == true) {
        if (!_selected.contains(symbol)) {
          if (_selected.length >= 10) {
            // Standard-Währung immer behalten: ein anderes Element entfernen.
            final removable = _selected.firstWhere(
              (s) => s != _standard,
              orElse: () => '',
            );
            if (removable.isNotEmpty) {
              _selected.remove(removable);
            } else {
              return; // nur Standard vorhanden, nichts zu tun
            }
          }
          _selected.add(symbol);
        }
      } else {
        if (symbol != _standard) {
          _selected.remove(symbol);
        }
      }
    });
  }

  Future<void> _save() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.setCurrency(_standard);
    await settings.setSelectedCurrencies(_selected);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final lang = settings.languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(getText(lang, 'selected_currencies')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                getText(lang, 'currency_standard_hint'),
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
            // Standard-Währung
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: DropdownButtonFormField<String>(
                initialValue: _standard,
                decoration: InputDecoration(
                  labelText: getText(lang, 'currency'),
                  border: const OutlineInputBorder(),
                ),
                items: appCurrencies
                    .map((c) => DropdownMenuItem<String>(
                          value: c['symbol'],
                          child: Text(
                              '${getText(lang, c['label_key']!)} (${c['symbol']})'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _standard = v;
                    if (!_selected.contains(v)) {
                      _selected.add(v);
                      if (_selected.length > 10) {
                        final removable = _selected.firstWhere(
                          (s) => s != _standard,
                          orElse: () => '',
                        );
                        if (removable.isNotEmpty) _selected.remove(removable);
                      }
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                getText(lang, 'selected_currencies_desc'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: appCurrencies.length,
                itemBuilder: (context, index) {
                  final item = appCurrencies[index];
                  final symbol = item['symbol']!;
                  final isSelected = _selected.contains(symbol);
                  final isStandard = symbol == _standard;
                  return CheckboxListTile(
                    title: Text(
                        '${getText(lang, item['label_key']!)} ($symbol)'),
                    value: isSelected || isStandard,
                    onChanged: isStandard ? null : (val) => _toggle(symbol, val),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(getText(lang, 'save')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}