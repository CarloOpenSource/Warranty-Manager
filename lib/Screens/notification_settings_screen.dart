import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../Services/Helpers/notification_template_helper.dart';
import '../Services/settings_provider.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  List<Map<String, String>> _parts = [];
  bool _loaded = false;

  // ── Trennzeichen zwischen den Bausteinen ──
  String _separatorMode = NotificationTemplateHelper.separatorDot;
  String _customSeparator = '';
  final TextEditingController _customSepController = TextEditingController();

  String get _separator => NotificationTemplateHelper.resolveSeparator(
      _separatorMode, _customSeparator);

  DateTime get _dummyNotifDate => DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTemplate());
  }

  @override
  void dispose() {
    _customSepController.dispose();
    super.dispose();
  }

  // ── Dummy-Gerät für die Vorschau ──
  Map<String, String> _buildDummyGerat(SettingsProvider settings) {
    final lang = settings.languageCode;
    final now = DateTime.now();
    final expiry = now.add(const Duration(days: 365));
    final buy = now.subtract(const Duration(days: 365));

    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return {
      'name': getText(lang, 'notif_sample_name'),
      'kaufDatum': fmt(buy),
      'ablaufDatum': fmt(expiry),
      'woGekauft': getText(lang, 'notif_sample_store'),
      'preis': '1199',
      'waehrung': '€',
      'kategorie': 'electronics',
      'bemerkung': getText(lang, 'notif_sample_remarks'),
      'bildPfade': 'a.jpg,b.jpg,c.jpg',
    };
  }

  // ── Template laden ──
  // Entfernt alte detailLink-/screenshot-/photoCount-Blöcke
  // und color-Felder.
  Future<void> _loadTemplate() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final originalTemplate = settings.notifTemplate;

    final cleaned = originalTemplate
        .where((p) =>
            p['type'] != 'detailLink' &&
            p['type'] != 'screenshot' &&
            p['type'] != 'photoCount')
        .map<Map<String, String>>((p) {
          final clean = Map<String, String>.from(p);
          clean.remove('color');
          return clean;
        })
        .toList();

    final List<Map<String, String>> finalParts = cleaned.isEmpty
        ? List<Map<String, String>>.from(
            NotificationTemplateHelper.defaultTemplate())
        : List<Map<String, String>>.from(cleaned);

    // Trennzeichen-Einstellung laden
    String sepMode = NotificationTemplateHelper.separatorDot;
    String sepCustom = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      sepMode = prefs.getString(NotificationTemplateHelper.prefSeparatorMode) ??
          sepMode;
      sepCustom =
          prefs.getString(NotificationTemplateHelper.prefSeparatorCustom) ?? '';
    } catch (_) {}
    if (sepMode != NotificationTemplateHelper.separatorDot &&
        sepMode != NotificationTemplateHelper.separatorComma &&
        sepMode != NotificationTemplateHelper.separatorCustom) {
      sepMode = NotificationTemplateHelper.separatorDot;
    }
    if (!mounted) return;

    setState(() {
      _parts = finalParts;
      _separatorMode = sepMode;
      _customSeparator = sepCustom;
      _customSepController.text = sepCustom;
      _loaded = true;
    });

    // Wenn etwas gefiltert wurde oder ursprünglich leer war,
    // bereinigte Version zurückspeichern.
    if (cleaned.length != originalTemplate.length || cleaned.isEmpty) {
      await settings.setNotifTemplate(finalParts);
    }
  }

  Future<void> _saveTemplate() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    await settings.setNotifTemplate(_parts);
  }

  // ── Trennzeichen speichern / ändern ──
  Future<void> _saveSeparator() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          NotificationTemplateHelper.prefSeparatorMode, _separatorMode);
      await prefs.setString(
          NotificationTemplateHelper.prefSeparatorCustom, _customSeparator);
    } catch (_) {}
  }

  void _setSeparatorMode(String mode) {
    if (_separatorMode == mode) return;
    setState(() => _separatorMode = mode);
    _saveSeparator();
  }

  void _onCustomSeparatorChanged(String value) {
    setState(() => _customSeparator = value);
    _saveSeparator();
  }

  // ── Baustein-Operationen ──
  void _addPart(String type, {String? customText}) {
    // Sicherheitsnetz: Limit für eigene Textbausteine nie überschreiten.
    if (type == NotificationTemplateHelper.typeCustom &&
        NotificationTemplateHelper.countCustomParts(_parts) >=
            NotificationTemplateHelper.maxCustomParts) {
      return;
    }
    setState(() {
      _parts.add(NotificationTemplateHelper.createPart(type,
          customText: customText));
    });
    _saveTemplate();
  }

  void _removePart(int index) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lang = settings.languageCode;

    if (_parts[index]['type'] == NotificationTemplateHelper.typeName) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(getText(lang, 'notif_part_mandatory_hint')),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _parts.removeAt(index));
    _saveTemplate();
  }

  void _reorderItem(int oldIndex, int newIndex) {
    setState(() {
      final item = _parts.removeAt(oldIndex);
      _parts.insert(newIndex, item);
    });
    _saveTemplate();
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _parts.removeAt(index);
      _parts.insert(index - 1, item);
    });
    _saveTemplate();
  }

  void _moveDown(int index) {
    if (index >= _parts.length - 1) return;
    setState(() {
      final item = _parts.removeAt(index);
      _parts.insert(index + 1, item);
    });
    _saveTemplate();
  }

  // ── Bottom Sheet: Baustein hinzufügen ──
  Future<void> _showAddPartSheet() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lang = settings.languageCode;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    getText(lang, 'notif_add_part'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                ...NotificationTemplateHelper.availableTypes.map((type) {
                  final alreadyAdded = _parts.any((p) => p['type'] == type);
                  final isCustom =
                      type == NotificationTemplateHelper.typeCustom;
                  final customCount =
                      NotificationTemplateHelper.countCustomParts(_parts);
                  final maxCustom = NotificationTemplateHelper.maxCustomParts;
                  // Eigene Texte: gesperrt, sobald das Maximum erreicht ist.
                  // Alle anderen Bausteine: gesperrt, wenn schon vorhanden.
                  final disabled =
                      isCustom ? customCount >= maxCustom : alreadyAdded;
                  final typeColor =
                      NotificationTemplateHelper.colorForType(type);

                  return ListTile(
                    enabled: !disabled,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: disabled
                            ? Colors.grey.withValues(alpha: 0.12)
                            : typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _iconForType(type),
                        color: disabled ? Colors.grey : typeColor,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      getText(lang,
                          NotificationTemplateHelper.getLabelKeyForType(type)),
                      style:
                          TextStyle(color: disabled ? Colors.grey : null),
                    ),
                    subtitle: isCustom
                        ? Text(
                            disabled
                                ? '${getText(lang, 'notif_part_already_added')} ($customCount/$maxCustom)'
                                : '$customCount/$maxCustom',
                            style: const TextStyle(fontSize: 12),
                          )
                        : (disabled
                            ? Text(
                                getText(lang, 'notif_part_already_added'),
                                style: const TextStyle(fontSize: 12),
                              )
                            : null),
                    onTap: disabled
                        ? null
                        : () async {
                            Navigator.pop(sheetContext);
                            if (isCustom) {
                              await _addCustomText();
                            } else {
                              _addPart(type);
                            }
                          },
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Dialog: Eigener Text ──
  Future<void> _addCustomText() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lang = settings.languageCode;
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(getText(lang, 'notif_part_custom')),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            maxLength: 120,
            decoration: InputDecoration(
              hintText: getText(lang, 'notif_custom_text_hint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(getText(lang, 'cancel')),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(getText(lang, 'save')),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      _addPart(NotificationTemplateHelper.typeCustom, customText: result);
    }
  }

  // ── Konfigurations-Dialog für einen Baustein ──
  Future<void> _openConfigDialog(int index) async {
    final lang =
        Provider.of<SettingsProvider>(context, listen: false).languageCode;
    final part = _parts[index];
    final type = part['type'] ?? '';

    final canLabel = NotificationTemplateHelper.hasLabelOption(type);
    final canFormat = NotificationTemplateHelper.hasFormatOption(type);
    final isCustom = type == NotificationTemplateHelper.typeCustom;

    bool showLabel = NotificationTemplateHelper.getShowLabel(part);
    String format = NotificationTemplateHelper.getFormat(part);
    final textController = TextEditingController(text: part['text'] ?? '');

    final typeColor = NotificationTemplateHelper.colorForType(type);

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Titel ──
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: typeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _iconForType(type),
                                color: typeColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              getText(lang, 'notif_part_settings'),
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // ── Label-Toggle ──
                      if (canLabel)
                        SwitchListTile(
                          title: Text(getText(lang, 'notif_show_label')),
                          subtitle: Text(
                              getText(lang, 'notif_show_label_desc')),
                          value: showLabel,
                          onChanged: (v) =>
                              setSheetState(() => showLabel = v),
                        ),

                      // ── Format-Dropdown ──
                      if (canFormat)
                        ListTile(
                          title: Text(getText(lang, 'notif_format')),
                          trailing: DropdownButton<String>(
                            value: format,
                            onChanged: (v) {
                              if (v != null) {
                                setSheetState(() => format = v);
                              }
                            },
                            items: NotificationTemplateHelper.formatOptions
                                .map((f) {
                              return DropdownMenuItem(
                                value: f,
                                child: Text(getText(
                                  lang,
                                  NotificationTemplateHelper
                                      .getFormatLabelKey(f),
                                )),
                              );
                            }).toList(),
                          ),
                        ),

                      // ── Custom-Text ──
                      if (isCustom)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: textController,
                            maxLines: 3,
                            maxLength: 120,
                            decoration: InputDecoration(
                              labelText:
                                  getText(lang, 'notif_part_custom'),
                              hintText: getText(
                                  lang, 'notif_custom_text_hint'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),

                      // ── Aktions-Buttons ──
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.pop(sheetContext),
                                child: Text(getText(lang, 'cancel')),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  final updated =
                                      Map<String, String>.from(part);
                                  if (canLabel) {
                                    updated['showLabel'] =
                                        showLabel ? 'true' : 'false';
                                  }
                                  if (canFormat) {
                                    updated['format'] = format;
                                  }
                                  if (isCustom) {
                                    updated['text'] =
                                        textController.text.trim();
                                  }
                                  // Farb-Einträge werden nicht mehr gespeichert
                                  updated.remove('color');
                                  Navigator.pop(sheetContext, updated);
                                },
                                child: Text(getText(lang, 'save')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() => _parts[index] = result);
      _saveTemplate();
    }
  }

  // ── Vorlage zurücksetzen ──
  Future<void> _resetToDefault() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final lang = settings.languageCode;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(getText(lang, 'notif_reset_title')),
          content: Text(getText(lang, 'notif_reset_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(getText(lang, 'cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(getText(lang, 'notif_reset_default')),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      final List<Map<String, String>> defaultParts =
          List<Map<String, String>>.from(
              NotificationTemplateHelper.defaultTemplate());
      setState(() {
        _parts = defaultParts;
        _separatorMode = NotificationTemplateHelper.separatorDot;
        _customSeparator = '';
        _customSepController.text = '';
      });
      await _saveTemplate();
      await _saveSeparator();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(getText(lang, 'notif_saved'))),
        );
      }
    }
  }

  // ── Icon pro Baustein-Typ ──
  IconData _iconForType(String type) {
    switch (type) {
      case NotificationTemplateHelper.typeName:
        return Icons.label_important;
      case NotificationTemplateHelper.typeBuyDate:
        return Icons.shopping_bag;
      case NotificationTemplateHelper.typeExpiryDate:
        return Icons.event_busy;
      case NotificationTemplateHelper.typeDaysLeft:
        return Icons.hourglass_bottom;
      case NotificationTemplateHelper.typeStore:
        return Icons.storefront;
      case NotificationTemplateHelper.typePrice:
        return Icons.attach_money;
      case NotificationTemplateHelper.typeDuration:
        return Icons.timer;
      case NotificationTemplateHelper.typeCategory:
        return Icons.category;
      case NotificationTemplateHelper.typeRemarks:
        return Icons.notes;
      case NotificationTemplateHelper.typeCustom:
        return Icons.text_fields;
      default:
        return Icons.circle;
    }
  }

  // ── Vorschautext für einen einzelnen Baustein (Listenzeile) ──
  String _renderPartPreview(
    SettingsProvider settings,
    String lang,
    Map<String, String> part,
  ) {
    final dummy = _buildDummyGerat(settings);
    final rendered = NotificationTemplateHelper.renderPart(
      langCode: lang,
      part: part,
      gerat: dummy,
      currencySymbol: settings.currencySymbol,
      referenceDate: _dummyNotifDate,
    );
    return rendered.isEmpty ? '—' : rendered;
  }

  // ── TextSpans für die Vorschau-Karte (einheitliche Textfarbe) ──
  List<TextSpan> _buildPreviewSpans(SettingsProvider settings, String lang) {
    final dummy = _buildDummyGerat(settings);
    final spans = <TextSpan>[];
    bool first = true;

    final baseColor =
        Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87;

    for (final part in _parts) {
      final text = NotificationTemplateHelper.renderPart(
        langCode: lang,
        part: part,
        gerat: dummy,
        currencySymbol: settings.currencySymbol,
        referenceDate: _dummyNotifDate,
      );
      if (text.isEmpty) continue;

      if (!first) {
        spans.add(TextSpan(
          text: _separator,
          style: TextStyle(
              color: Colors.grey[400], fontSize: 13, height: 1.4),
        ));
      }

      spans.add(TextSpan(
        text: text,
        style: TextStyle(color: baseColor, fontSize: 13, height: 1.4),
      ));
      first = false;
    }

    // Fallback wenn keine Bausteine gerendert werden
    if (spans.isEmpty) {
      final dummy2 = _buildDummyGerat(settings);
      final fallback =
          '${getText(lang, 'notif_body')}${dummy2['ablaufDatum']}${getText(lang, 'notif_body_end')}';
      spans.add(TextSpan(
        text: fallback,
        style: TextStyle(
            color: Colors.grey[600], fontSize: 13, height: 1.4),
      ));
    }

    return spans;
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final lang = settings.languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Text(getText(lang, 'notif_settings')),
      ),
      body: SafeArea(
  top: false,
  child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Vorschau ──
                      _buildSectionTitle(
                          getText(lang, 'notif_preview'), settings),
                      const SizedBox(height: 8),
                      _buildNotificationPreview(settings, lang),
                      _buildLengthWarning(settings, lang),
                      const SizedBox(height: 24),

                      // ── Bausteine-Header ──
                      Row(
                        children: [
                          _buildSectionTitle(
                              getText(lang, 'notif_template_parts'),
                              settings),
                          const SizedBox(width: 8),
                          AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeOut,
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
  decoration: BoxDecoration(
    color: settings.appButtonColor.withValues(alpha: 0.15),
    borderRadius: BorderRadius.circular(10),
  ),
  child: AnimatedSwitcher(
    duration: const Duration(milliseconds: 150),
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    child: Text(
      '${_parts.length}',
      key: ValueKey(_parts.length),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: settings.appButtonColor,
      ),
    ),
  ),
),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        getText(lang, 'notif_template_hint'),
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),

                      // ── Baustein-Liste ──
                      if (_parts.isEmpty)
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                getText(lang, 'notif_template_empty_hint'),
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ),
                        )
                      else
                        ReorderableListView(
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          onReorderItem: _reorderItem,
                          children: List.generate(_parts.length,
                              (index) {
                            final part = _parts[index];
                            final type = part['type'] ?? '';
                            final isMandatory = type ==
                                NotificationTemplateHelper.typeName;
                            final hasSettings =
                                NotificationTemplateHelper.hasAnySettings(
                                    type);
                            final label = getText(
                                lang,
                                NotificationTemplateHelper
                                    .getLabelKeyForType(type));
                            final customText = part['text'] ?? '';

                            final previewText =
                                _renderPartPreview(settings, lang, part);
                            final typeColor =
                                NotificationTemplateHelper.colorForType(
                                    type);

                            return Container(
                              key: ValueKey('part_$index'),
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius:
                                    BorderRadius.circular(10),
                                border: Border(
                                  left: BorderSide(
                                      color: typeColor, width: 4),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.03),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              // Eigenes Material, damit ListTile-Hintergrund und
                              // Tipp-Effekt nicht vom farbigen Container verdeckt werden.
                              child: Material(
                                type: MaterialType.transparency,
                                borderRadius: BorderRadius.circular(10),
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                contentPadding: const EdgeInsets.only(
                                    left: 10,
                                    right: 4,
                                    top: 4,
                                    bottom: 4),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(
                                        alpha: 0.14),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _iconForType(type),
                                    color: typeColor,
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  type ==
                                          NotificationTemplateHelper
                                              .typeCustom
                                      ? '$label: "$customText"'
                                      : label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.left,
                                ),
                                subtitle: SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    previewText,
                                    textAlign: TextAlign.left,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: typeColor.withValues(
                                          alpha: 0.8),
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // Nur Bausteine MIT Einstellungen sind
                                // antippbar. Sonst Hinweis-Snackbar.
                                onTap: hasSettings
                                    ? () => _openConfigDialog(index)
                                    : () {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(getText(
                                                lang, 'notif_no_options')),
                                            duration: const Duration(
                                                seconds: 2),
                                          ),
                                        );
                                      },
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity:
                                          VisualDensity.compact,
                                      tooltip: getText(
                                          lang, 'notif_move_up'),
                                      icon: Icon(
                                        Icons.arrow_upward,
                                        size: 20,
                                        color: index > 0
                                            ? settings.appButtonColor
                                            : Colors.grey.shade400,
                                      ),
                                      onPressed: index > 0
                                          ? () => _moveUp(index)
                                          : null,
                                    ),
                                    IconButton(
                                      visualDensity:
                                          VisualDensity.compact,
                                      tooltip: getText(
                                          lang, 'notif_move_down'),
                                      icon: Icon(
                                        Icons.arrow_downward,
                                        size: 20,
                                        color:
                                            index < _parts.length - 1
                                                ? settings
                                                    .appButtonColor
                                                : Colors.grey.shade400,
                                      ),
                                      onPressed:
                                          index < _parts.length - 1
                                              ? () => _moveDown(index)
                                              : null,
                                    ),
                                    if (isMandatory)
                                      Tooltip(
                                        message: getText(lang,
                                            'notif_part_mandatory_hint'),
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 6),
                                          child: Icon(
                                            Icons.lock,
                                            size: 18,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      )
                                    else
                                      IconButton(
                                        visualDensity:
                                            VisualDensity.compact,
                                        tooltip:
                                            getText(lang, 'delete'),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                          size: 20,
                                        ),
                                        onPressed: () =>
                                            _removePart(index),
                                      ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 8),
                                        child: Icon(
                                          Icons.drag_handle,
                                          size: 22,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ),
                            );
                          }),
                        ),

                      const SizedBox(height: 10),

                      // ── Baustein hinzufügen ──
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showAddPartSheet,
                          icon: Icon(Icons.add,
                              color: settings.appButtonColor),
                          label: Text(
                            getText(lang, 'notif_add_part'),
                            style: TextStyle(
                                color: settings.appButtonColor,
                                fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            side:
                                BorderSide(color: settings.appButtonColor),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Trennzeichen ──
                      _buildSectionTitle(
                          getText(lang, 'notif_sep_title'),
                          settings),
                      const SizedBox(height: 6),
                      Text(
                        getText(lang, 'notif_sep_desc'),
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      _buildSeparatorSelector(settings, lang),

                      const SizedBox(height: 24),

                      // ── Reset ──
                      Center(
                        child: TextButton.icon(
                          onPressed: _resetToDefault,
                          icon: const Icon(Icons.restart_alt,
                              color: Colors.grey),
                          label: Text(
                            getText(lang, 'notif_reset_default'),
                            style: const TextStyle(color: Colors.grey),
                          ),
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

  // ── Trennzeichen-Auswahl (Punkt / Komma / eigener Text) ──
  Widget _buildSeparatorSelector(SettingsProvider settings, String lang) {
    final options = <String, String>{
      NotificationTemplateHelper.separatorDot:
          '${getText(lang, 'notif_sep_dot')} (•)',
      NotificationTemplateHelper.separatorComma:
          '${getText(lang, 'notif_sep_comma')} (,)',
      NotificationTemplateHelper.separatorCustom:
          getText(lang, 'notif_part_custom'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((entry) {
            return ChoiceChip(
              label: Text(entry.value),
              selected: _separatorMode == entry.key,
              selectedColor: settings.appButtonColor.withValues(alpha: 0.2),
              onSelected: (_) => _setSeparatorMode(entry.key),
            );
          }).toList(),
        ),
        if (_separatorMode == NotificationTemplateHelper.separatorCustom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customSepController,
            maxLength: NotificationTemplateHelper.maxSeparatorLength,
            onChanged: _onCustomSeparatorChanged,
            decoration: InputDecoration(
              labelText: getText(lang, 'notif_sep_custom_label'),
              helperText: getText(lang, 'notif_sep_custom_helper'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  // ── Warnung, wenn die Benachrichtigung zu lang wird ──
  Widget _buildLengthWarning(SettingsProvider settings, String lang) {
    final dummy = _buildDummyGerat(settings);
    final length = NotificationTemplateHelper.buildBody(
      langCode: lang,
      template: _parts,
      produktName: dummy['name'] ?? '',
      ablaufDatumStr: dummy['ablaufDatum'] ?? '',
      gerat: dummy,
      currencySymbol: settings.currencySymbol,
      referenceDate: _dummyNotifDate,
      separator: _separator,
    ).length;

    if (length < NotificationTemplateHelper.maxNotificationChars) {
      return const SizedBox.shrink();
    }

    final message =
        getText(lang, 'notif_too_long')
            .replaceAll('{count}', '$length')
            .replaceAll('{max}',
                '${NotificationTemplateHelper.maxNotificationChars}');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Abschnittstitel ──
  Widget _buildSectionTitle(String text, SettingsProvider settings) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: settings.appButtonColor,
      ),
    );
  }

  // ── Benachrichtigungs-Vorschaukarte ──
  Widget _buildNotificationPreview(SettingsProvider settings, String lang) {
    final dummy = _buildDummyGerat(settings);
    final String title =
        '${getText(lang, 'notif_title')}${dummy['name']}';
    final spans = _buildPreviewSpans(settings, lang);

    // Lint-Fix: Interpolation statt Konkatenation mit '+'.
    final partsJoined = _parts
        .map((p) =>
            '${p['type']}${p['showLabel']}${p['format']}${p['text']}')
        .join('|');
    final previewKey = '$partsJoined#$_separator';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: settings.appButtonColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: settings.appButtonColor.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── App-Leiste ──
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: settings.appButtonColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.shield,
                    size: 14, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Text(
                getText(lang, 'app_title'),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                getText(lang, 'notif_preview_now'),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Benachrichtigungs-Titel ──
          Text(
            title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 4),

          // ── Body: einheitliche Textfarbe, linksbündig ──
          AnimatedSwitcher(
  duration: const Duration(milliseconds: 180),
  transitionBuilder: (child, animation) =>
      FadeTransition(opacity: animation, child: child),
  child: SizedBox(
    key: ValueKey(previewKey),
    width: double.infinity,
    child: RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.left,
      textScaler: MediaQuery.textScalerOf(context),
    ),
  ),
),
        ],
      ),
    );
  }
}