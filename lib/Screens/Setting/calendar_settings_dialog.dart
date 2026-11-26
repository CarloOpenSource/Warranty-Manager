import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Services/calender_service.dart';
import '../../Services/settings_provider.dart';

Future<void> showCalendarSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _CalendarSettingsContent(isDialog: true),
  );
}

class CalendarSettingsScreen extends StatelessWidget {
  const CalendarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CalendarSettingsContent(isDialog: false);
  }
}

class _CalendarSettingsContent extends StatefulWidget {
  final bool isDialog;
  const _CalendarSettingsContent({required this.isDialog});

  @override
  State<_CalendarSettingsContent> createState() =>
      _CalendarSettingsContentState();
}

class _CalendarSettingsContentState extends State<_CalendarSettingsContent> {
  bool _loading = true;
  bool _busy = false;
  List<CalendarProviderInfo> _providers = [];
  bool _didAutoSelect = false;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    final providers = await CalendarService().getAvailableProviders();
    if (!mounted) return;

    setState(() {
      _providers = providers;
      _loading = false;
    });

    // Auto-Selektion: Nur wenn kein gültiger Anbieter gespeichert ist
    if (!_didAutoSelect && mounted) {
      _didAutoSelect = true;
      final settings = context.read<SettingsProvider>();
      final current = settings.preferredCalendarApp;
      final currentIsIcs = current == 'ics';
      final currentValid = providers.any((p) => p.id == current);

      // Wenn kein gültiger Provider gespeichert ist (und nicht ICS),
      // automatisch den ersten verfügbaren nehmen
      if (!currentValid && !currentIsIcs && providers.isNotEmpty) {
        await settings.setPreferredCalendarApp(providers.first.id);
      }
      // Wenn kein Provider vorhanden und kein ICS gesetzt → auf ICS setzen
      else if (!currentValid && !currentIsIcs && providers.isEmpty) {
        await settings.setPreferredCalendarApp('ics');
        await settings.setAutoAddToCalendar(false);
        await settings.setAutoUpdateCalendar(false);
      }
    }
  }

  String _appName(String app, String lang) {
    switch (app) {
      case 'google':
        return getText(lang, 'calendar_app_google');
      case 'samsung':
        return getText(lang, 'calendar_app_samsung');
      case 'outlook':
        return getText(lang, 'calendar_app_outlook');
      case 'ics':
        return getText(lang, 'calendar_app_ics');
      case 'system':
      default:
        return getText(lang, 'calendar_app_system');
    }
  }

  String _reminderName(int minutes, String lang) {
    if (minutes <= 15) return getText(lang, 'reminder_time_15min');
    if (minutes <= 60) return getText(lang, 'reminder_time_1hour');
    if (minutes <= 1440) return getText(lang, 'reminder_time_1day');
    if (minutes <= 4320) return getText(lang, 'reminder_time_3days');
    return getText(lang, 'reminder_time_1week');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final lang = settings.languageCode;
        final selected = settings.preferredCalendarApp;
        final isIcs = selected == 'ics';
        final hasRealProvider =
            !isIcs && _providers.any((p) => p.id == selected);
        final canAutoSync = hasRealProvider;

        final Widget bodyContent = _loading
            ? const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: _buildMainColumn(
                  settings,
                  lang,
                  selected,
                  isIcs,
                  hasRealProvider,
                  canAutoSync,
                ),
              );

        if (widget.isDialog) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.calendar_month, color: settings.appButtonColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    getText(lang, 'calendar_settings'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: bodyContent,
            ),
            actions: [
              if (!_loading && hasRealProvider)
                TextButton.icon(
                  onPressed:
                      _busy ? null : () => _testProvider(settings, lang),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(getText(lang, 'calendar_test_button')),
                ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: Text(getText(lang, 'ok')),
              ),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(getText(lang, 'calendar_settings')),
            actions: [
              if (!_loading && hasRealProvider)
                IconButton(
                  tooltip: getText(lang, 'calendar_test_button'),
                  onPressed:
                      _busy ? null : () => _testProvider(settings, lang),
                  icon: const Icon(Icons.play_arrow),
                ),
            ],
          ),
          body: SafeArea(
  top: false,
  child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
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
                  child: _loading
                      ? const SizedBox(
                          height: 140,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _buildMainColumn(
                          settings,
                          lang,
                          selected,
                          isIcs,
                          hasRealProvider,
                          canAutoSync,
                        ),
                ),
              ),
            ),
          ),
        )
        );
      },
    );
  }

  Widget _buildMainColumn(
    SettingsProvider settings,
    String lang,
    String selected,
    bool isIcs,
    bool hasRealProvider,
    bool canAutoSync,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          getText(lang, 'calendar_settings_desc'),
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 12),

        _buildStatusBanner(lang, settings, selected, isIcs),
        const SizedBox(height: 12),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            Icons.add_task,
            color: canAutoSync ? settings.appButtonColor : Colors.grey,
          ),
          title: Text(
            getText(lang, 'auto_add_to_calendar'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            canAutoSync
                ? getText(lang, 'auto_add_to_calendar_desc')
                : getText(lang, 'auto_add_disabled_hint'),
            style: const TextStyle(fontSize: 12),
          ),
          value: canAutoSync && settings.autoAddToCalendar,
          onChanged:
              canAutoSync ? (v) => settings.setAutoAddToCalendar(v) : null,
        ),
        const Divider(height: 1),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            Icons.sync,
            color: canAutoSync ? settings.appButtonColor : Colors.grey,
          ),
          title: Text(
            getText(lang, 'auto_update_calendar'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            canAutoSync
                ? getText(lang, 'auto_update_calendar_desc')
                : getText(lang, 'auto_update_disabled_hint'),
            style: const TextStyle(fontSize: 12),
          ),
          value: canAutoSync && settings.autoUpdateCalendar,
          onChanged:
              canAutoSync ? (v) => settings.setAutoUpdateCalendar(v) : null,
        ),
        const Divider(height: 1),

        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.apps, color: settings.appButtonColor),
          title: Text(
            getText(lang, 'preferred_calendar_app'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _appName(selected, lang),
            style: TextStyle(
              fontSize: 12,
              color: settings.appButtonColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: const Icon(Icons.arrow_drop_down),
          onTap: _busy ? null : () => _showProviderPicker(settings, lang),
        ),
        const Divider(height: 1),

        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.notifications_active_outlined,
            color: settings.appButtonColor,
          ),
          title: Text(
            getText(lang, 'default_reminder_time'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _reminderName(settings.defaultReminderMinutes, lang),
            style: TextStyle(
              fontSize: 12,
              color: settings.appButtonColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: const Icon(Icons.arrow_drop_down),
          onTap: _busy ? null : () => _showReminderPicker(settings, lang),
        ),
        const Divider(height: 1),

        const SizedBox(height: 8),
        _buildIcsDownloadTile(settings, lang),
        const SizedBox(height: 8),

        if (hasRealProvider) _buildSyncAllTile(settings, lang),
      ],
    );
  }

  Widget _buildIcsDownloadTile(SettingsProvider settings, String lang) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _busy ? null : () => _downloadAllIcs(settings, lang),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.file_download_outlined, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    getText(lang, 'calendar_app_ics'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    getText(lang, 'calendar_ics_hint'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncAllTile(SettingsProvider settings, String lang) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _busy ? null : () => _syncAllEntries(settings, lang),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: settings.appButtonColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: settings.appButtonColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.sync, color: settings.appButtonColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  getText(lang, 'sync_all_now'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: settings.appButtonColor,
                ),
              ),
            ),
            if (_busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: settings.appButtonColor,
                ),
              )
            else
              Icon(Icons.chevron_right, color: settings.appButtonColor),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(
      String lang, SettingsProvider settings, String selected, bool isIcs) {
    if (_providers.isEmpty) {
      return _banner(
        color: Colors.orange,
        icon: Icons.info_outline,
        text: getText(lang, 'calendar_no_provider_desc'),
      );
    }

    if (!isIcs && !_providers.any((p) => p.id == selected)) {
      return _banner(
        color: Colors.redAccent,
        icon: Icons.error_outline,
        text: getText(lang, 'calendar_selected_unavailable'),
      );
    }

    if (isIcs) {
      return _banner(
        color: Colors.orange,
        icon: Icons.warning_amber_rounded,
        text: getText(lang, 'calendar_ics_hint_long'),
      );
    }

    return _banner(
      color: Colors.green,
      icon: Icons.check_circle_outline,
      text: '${getText(lang, 'calendar_detected_providers')}: '
          '${_providers.map((p) => _appName(p.id, lang)).join(', ')}',
    );
  }

  Widget _banner({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  Provider-Picker
  //  FIX: ICS-Option immer sichtbar (nicht nur wenn providers.isEmpty
  //       oder selected == 'ics'). Jeder Nutzer soll immer alle
  //       Optionen sehen können.
  // ────────────────────────────────────────────────────────────
  void _showProviderPicker(SettingsProvider settings, String lang) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(getText(lang, 'preferred_calendar_app')),
        children: [
          // ── Erkannte Kalender-Apps ────────────────────────────────────────
          if (_providers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                getText(lang, 'calendar_no_provider'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            )
          else
            for (final p in _providers)
              SimpleDialogOption(
                onPressed: () async {
                  await settings.setPreferredCalendarApp(p.id);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _appName(p.id, lang),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (settings.preferredCalendarApp == p.id)
                      Icon(Icons.check, color: settings.appButtonColor),
                  ],
                ),
              ),

          // ── ICS-Option: immer sichtbar ────────────────────────────────────
          const Divider(),
          SimpleDialogOption(
            onPressed: () => _confirmIcs(ctx, settings, lang),
            child: Row(
              children: [
                const Icon(Icons.file_download_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    getText(lang, 'calendar_app_ics'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (settings.preferredCalendarApp == 'ics')
                  Icon(Icons.check, color: settings.appButtonColor),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              getText(lang, 'calendar_ics_hint'),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmIcs(
      BuildContext ctx, SettingsProvider settings, String lang) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(getText(lang, 'calendar_ics_confirm_title')),
        content: Text(getText(lang, 'calendar_ics_confirm_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(getText(lang, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(getText(lang, 'ok')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await settings.setPreferredCalendarApp('ics');
      await settings.setAutoAddToCalendar(false);
      await settings.setAutoUpdateCalendar(false);
      if (ctx.mounted) Navigator.pop(ctx);
    }
  }

  void _showReminderPicker(SettingsProvider settings, String lang) {
    const options = <int>[15, 60, 1440, 4320, 10080];
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(getText(lang, 'default_reminder_time')),
        children: [
          for (final v in options)
            SimpleDialogOption(
              onPressed: () async {
                await settings.setDefaultReminderMinutes(v);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(_reminderName(v, lang),
                        style: const TextStyle(fontSize: 14)),
                  ),
                  if (settings.defaultReminderMinutes == v)
                    Icon(Icons.check, color: settings.appButtonColor),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _testProvider(SettingsProvider settings, String lang) async {
    setState(() => _busy = true);
    final result =
        await CalendarService().testProvider(settings.preferredCalendarApp);
    if (!mounted) return;
    setState(() => _busy = false);

    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(
          result.success ? Icons.check_circle : Icons.error_outline,
          color: result.success ? Colors.green : Colors.redAccent,
          size: 40,
        ),
        title: Text(
          getText(
              lang,
              result.success
                  ? 'calendar_test_success'
                  : 'calendar_test_failed'),
          textAlign: TextAlign.center,
        ),
        // Technisches Protokoll, damit man ohne logcat sieht, WAS genau
        // auf dem Gerät erkannt wurde und woran das Schreiben scheitert.
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              result.details,
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace', height: 1.4),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result.details));
              if (c.mounted) {
                ScaffoldMessenger.of(c).showSnackBar(
                  SnackBar(content: Text(getText(lang, 'copied_to_clipboard'))),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(getText(lang, 'copy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(getText(lang, 'ok')),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  ICS-Download (Teilen / Speichern)
  // ────────────────────────────────────────────────────────────
  Future<void> _downloadAllIcs(SettingsProvider settings, String lang) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('gerate_liste');

    if (raw == null || raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(getText(lang, 'no_devices')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    List<Map<String, String>> entries;
    try {
      final List<dynamic> liste = jsonDecode(raw);
      entries =
          liste.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(getText(lang, 'import_error')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(getText(lang, 'no_devices')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    final wahl = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getText(lang, 'calendar_app_ics')),
        content: Text(getText(lang, 'export_method_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'share'),
            child: Text(getText(lang, 'export_share')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(getText(lang, 'export_save')),
          ),
        ],
      ),
    );

    if (wahl == null) return;

    try {
      final ics = CalendarService().buildIcsForEntries(
        entries: entries,
        reminderMinutes: settings.defaultReminderMinutes,
      );

      if (wahl == 'save') {
        final bytes = Uint8List.fromList(utf8.encode(ics));
        final saveResult = await FilePicker.saveFile(
          dialogTitle: getText(lang, 'backup_save_title'),
          fileName: 'WarrantyManager_Warranties.ics',
          bytes: bytes,
        );
        if (saveResult != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(getText(lang, 'export_success'))),
          );
        }
      } else {
        await CalendarService().shareIcsFile(
          icsContent: ics,
          fileName: 'WarrantyManager_Warranties.ics',
          subject: 'Warranty Manager – Garantien',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${getText(lang, 'ics_export_failed')}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ────────────────────────────────────────────────────────────
  //  Alle Einträge synchronisieren
  // ────────────────────────────────────────────────────────────
  Future<void> _syncAllEntries(SettingsProvider settings, String lang) async {
    setState(() => _busy = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('gerate_liste');
      if (raw == null || raw.isEmpty) {
        setState(() => _busy = false);
        return;
      }

      final List<dynamic> decoded = jsonDecode(raw);
      final List<Map<String, String>> entries =
          decoded.map((e) => Map<String, String>.from(e as Map)).toList();

      final providerId = settings.preferredCalendarApp;
      final service = CalendarService();
      int synced = 0;
      int failed = 0;

      for (final entry in entries) {
        final name = (entry['name'] ?? '').trim();
        if (name.isEmpty) continue;

        final expiry = service.parseEntryExpiry(entry['ablaufDatum']);
        if (expiry == null) continue;

        final description = 'Garantie bis ${entry['ablaufDatum']}\n'
            'Gekauft bei: ${entry['woGekauft'] ?? '-'}';

        final existingId = entry['calendarEventId'];
        final existingCalId = entry['calendarId'];

        TimeOfDay? startTime;
        final erinnerung = entry['erinnerung'];
        if (erinnerung != null &&
            erinnerung != 'Nie' &&
            erinnerung.isNotEmpty) {
          try {
            final decodedE = jsonDecode(erinnerung);
            if (decodedE is Map && decodedE['ausloeseZeit'] != null) {
              final dt = DateTime.parse(decodedE['ausloeseZeit']);
              startTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
            }
          } catch (_) {}
        }

        if (existingId != null && existingId.isNotEmpty) {
          final updated = await service.updateEvent(
            eventId: existingId,
            calendarId: existingCalId,
            providerId: providerId,
            title: name,
            description: description,
            expiryDate: expiry,
            startTime: startTime,
            reminderMinutes: settings.defaultReminderMinutes,
          );
          if (updated != null) {
            entry['calendarEventId'] = updated.eventId;
            entry['calendarId'] = updated.calendarId;
            synced++;
            continue;
          }
        }

        final created = await service.addEvent(
          title: name,
          description: description,
          expiryDate: expiry,
          startTime: startTime,
          providerId: providerId,
          reminderMinutes: settings.defaultReminderMinutes,
        );
        if (created != null) {
          entry['calendarEventId'] = created.eventId;
          entry['calendarId'] = created.calendarId;
          synced++;
        } else {
          failed++;
        }
      }

      await prefs.setString('gerate_liste', jsonEncode(entries));

      if (!mounted) return;
      setState(() => _busy = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failed > 0
      ? '${getText(lang, 'sync_result_partial_prefix')} $synced, '
          '${getText(lang, 'sync_result_partial_failed')} $failed'
      : '${getText(lang, 'sync_result_success_prefix')} $synced '
          '${getText(lang, 'sync_result_success_suffix')}',
          ),
          backgroundColor:
              failed > 0 ? Colors.orange.shade800 : Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${getText(lang, 'sync_failed')}: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}