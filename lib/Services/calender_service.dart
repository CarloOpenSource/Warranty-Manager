import 'dart:io';
import 'package:device_calendar/device_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/material.dart' show TimeOfDay;

class CreatedEvent {
  final String eventId;
  final String calendarId;
  const CreatedEvent(this.eventId, this.calendarId);
}

class CalendarProviderInfo {
  final String id;
  final String displayName;
  final String accountName;
  const CalendarProviderInfo({
    required this.id,
    required this.displayName,
    required this.accountName,
  });
}

class CalendarTestResult {
  final bool success;
  final String details;
  const CalendarTestResult(this.success, this.details);
}

class CalendarService {
  CalendarService._();
  static final CalendarService _instance = CalendarService._();
  factory CalendarService() => _instance;

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();
  bool _tzInitialized = false;

  void _ensureTz() {
    if (!_tzInitialized) {
      tzdata.initializeTimeZones();
      _tzInitialized = true;
    }
  }

  DateTime? parseEntryExpiry(String? ablaufStr) {
    if (ablaufStr == null || ablaufStr.isEmpty) return null;
    final parts = ablaufStr.split('.');
    if (parts.length != 3) return null;
    try {
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _ensurePermission() async {
    try {
      final has = await _plugin.hasPermissions();
      if (has.data == true) return true;
      final req = await _plugin.requestPermissions();
      if (req.data == true) return true;

      await Future.delayed(const Duration(milliseconds: 300));
      final recheck = await _plugin.hasPermissions();
      return recheck.data == true;
    } catch (e) {
      return false;
    }
  }

  Future<List<Calendar>> _retrieveWritableCalendars() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final result = await _plugin.retrieveCalendars();
        final calendars = (result.data ?? <Calendar>[])
            .where((c) => c.isReadOnly != true)
            .toList();
        if (calendars.isNotEmpty) return calendars;
      } catch (e) {
        //
      }
      if (attempt < 3) {
        await Future.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    return const <Calendar>[];
  }

  String? _detectProviderId(Calendar cal) {
    final type = (cal.accountType ?? '').toLowerCase().trim();
    final accountName = (cal.accountName ?? '').toLowerCase().trim();
    final calName = (cal.name ?? '').toLowerCase().trim();
    final combo = '$type|$accountName|$calName';

    if (type.contains('google') ||
        type.contains('gmail') ||
        type.contains('com.google') ||
        accountName.contains('@gmail.com') ||
        accountName.contains('@google') ||
        accountName.contains('google') ||
        calName.contains('google')) {
      return 'google';
    }

    if (combo.contains('outlook') ||
        combo.contains('microsoft') ||
        combo.contains('office365') ||
        combo.contains('hotmail') ||
        combo.contains('live.com') ||
        combo.contains('exchange') ||
        type.contains('eas') ||
        accountName.endsWith('@hotmail.com') ||
        accountName.endsWith('@outlook.com') ||
        accountName.endsWith('@live.com')) {
      return 'outlook';
    }

    if (type.contains('samsung') ||
        type.contains('com.sec') ||
        type.contains('sec.android') ||
        type.contains('vnd.sec') ||
        type.contains('com.samsung') ||
        type.contains('osp.app.signin') ||
        type.contains('knox') ||
        accountName.contains('samsung') ||
        accountName.contains('galaxy') ||
        accountName.contains('@samsung.com') ||
        calName.contains('samsung') ||
        calName.contains('galaxy') ||
        calName.contains('my calendar') ||
        calName.contains('mein kalender') ||
        calName.contains('mon calendrier') ||
        calName.contains('mi calendario') ||
        calName.contains('il mio calendario') ||
        calName.contains('meu calendário') ||
        calName.contains('mijn agenda')) {
      return 'samsung';
    }

    if (type == 'local' ||
        type.isEmpty ||
        type.contains('phone') ||
        type.contains('aosp') ||
        type.contains('sim') ||
        calName.contains('phone') ||
        calName.contains('local') ||
        calName.contains('gerät') ||
        calName.contains('kalender') ||
        calName.contains('calendar') ||
        calName.contains('calendrier') ||
        calName.contains('calendario') ||
        calName.contains('agenda')) {
      return 'system';
    }

    if (accountName.contains('@')) {
      if (accountName.contains('gmail') || accountName.contains('google')) {
        return 'google';
      }
      if (accountName.contains('outlook') ||
          accountName.contains('hotmail') ||
          accountName.contains('live.com') ||
          accountName.contains('microsoft')) {
        return 'outlook';
      }
    }

    return null;
  }

  String _displayName(String id) {
    switch (id) {
      case 'google':
        return 'Google Calendar';
      case 'samsung':
        return 'Samsung Calendar';
      case 'outlook':
        return 'Outlook Calendar';
      case 'system':
        return 'System Calendar';
      default:
        return id;
    }
  }

  Future<List<CalendarProviderInfo>> getAvailableProviders() async {
    final providers = <CalendarProviderInfo>[];
    try {
      if (!await _ensurePermission()) return providers;
      final List<Calendar> calendars = await _retrieveWritableCalendars();
      final seen = <String>{};

      for (final cal in calendars) {
        final id = _detectProviderId(cal);
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        providers.add(CalendarProviderInfo(
          id: id,
          displayName: _displayName(id),
          accountName: cal.accountName ?? '',
        ));
      }

      if (providers.length == 1 &&
          providers.first.id == 'system' &&
          calendars.isNotEmpty) {
        final firstCal = calendars.first;
        final firstCalName = (firstCal.name ?? '').toLowerCase();
        final firstAccName = (firstCal.accountName ?? '').toLowerCase();
        final firstType = (firstCal.accountType ?? '').toLowerCase();

        final isSamsungDevice = firstCalName.contains('my calendar') ||
            firstCalName.contains('mein kalender') ||
            firstCalName.contains('mon calendrier') ||
            firstCalName.contains('mi calendario') ||
            firstCalName.contains('il mio calendario') ||
            firstCalName.contains('meu calendário') ||
            firstCalName.contains('mijn agenda') ||
            firstCalName.contains('samsung') ||
            firstCalName.contains('galaxy') ||
            firstAccName.contains('samsung') ||
            firstAccName.contains('galaxy') ||
            firstType.contains('osp') ||
            firstType.contains('sec') ||
            firstType.contains('knox') ||
            firstType.isEmpty;

        if (isSamsungDevice) {
          providers.clear();
          providers.add(CalendarProviderInfo(
            id: 'samsung',
            displayName: _displayName('samsung'),
            accountName: firstCal.accountName ?? 'Samsung',
          ));
        }
      }

      if (providers.isEmpty && calendars.isNotEmpty) {
        providers.add(CalendarProviderInfo(
          id: 'system',
          displayName: _displayName('system'),
          accountName: calendars.first.accountName ?? 'Local',
        ));
      }

      final hasSpecific = providers.any((p) => p.id != 'system');
      if (hasSpecific) {
        providers.removeWhere((p) => p.id == 'system');
      }

    } catch (e) {
      //
    }
    return providers;
  }

  Future<List<Calendar>> _findBestCalendars(String providerId) async {
    final ordered = <Calendar>[];
    try {
      if (!await _ensurePermission()) return ordered;
      final List<Calendar> calendars = (await _retrieveWritableCalendars())
          .where((c) => c.id != null)
          .toList();

      for (final cal in calendars) {
        if (_detectProviderId(cal) == providerId) {
          ordered.add(cal);
        }
      }

      if (ordered.isEmpty &&
          (providerId == 'system' || providerId == 'samsung')) {
        for (final cal in calendars) {
          final det = _detectProviderId(cal);
          if (det == 'samsung' || det == 'system' || det == null) {
            ordered.add(cal);
          }
        }
      }

      if (ordered.isEmpty && calendars.isNotEmpty) {
        ordered.addAll(calendars);
      }
    } catch (e) {
      //
    }
    return ordered;
  }

  Future<CreatedEvent?> addEvent({
    required String title,
    required String description,
    required DateTime expiryDate,
    TimeOfDay? startTime,
    required String providerId,
    int reminderMinutes = 60,
  }) async {
    _ensureTz();
    try {
      final calendars = await _findBestCalendars(providerId);

      for (final calendar in calendars) {
        if (calendar.id == null) continue;
        try {
          final int hour = startTime?.hour ?? 9;
          final int minute = startTime?.minute ?? 0;
          final start = DateTime(
              expiryDate.year, expiryDate.month, expiryDate.day, hour, minute);
          final end = start.add(const Duration(minutes: 30));

          final event = Event(
            calendar.id!,
            title: title,
            description: description,
            start: tz.TZDateTime.from(start, tz.local),
            end: tz.TZDateTime.from(end, tz.local),
            reminders: [Reminder(minutes: reminderMinutes)],
            allDay: startTime == null,
          );

          final res = await _plugin.createOrUpdateEvent(event);
          if (res?.isSuccess == true && res?.data != null) {
            return CreatedEvent(res!.data!, calendar.id!);
          }
        } catch (e) {
          //
        }
      }
    } catch (e) {
      //
    }
    return null;
  }

  Future<CreatedEvent?> updateEvent({
    required String eventId,
    required String title,
    required String description,
    required DateTime expiryDate,
    TimeOfDay? startTime,
    String? calendarId,
    String? providerId,
    int reminderMinutes = 60,
  }) async {
    _ensureTz();
    try {
      if (!await _ensurePermission()) return null;

      final List<Calendar> allCals = (await _retrieveWritableCalendars())
          .where((Calendar c) => c.id != null)
          .toList();

      final List<Calendar> ordered = <Calendar>[];
      if (calendarId != null && calendarId.isNotEmpty) {
        ordered.addAll(allCals.where((c) => c.id == calendarId));
      }
      if (providerId != null) {
        for (final c in allCals) {
          if (!ordered.any((o) => o.id == c.id) &&
              (_detectProviderId(c) == providerId ||
               ((providerId == 'samsung' || providerId == 'system') &&
                (_detectProviderId(c) == 'samsung' ||
                 _detectProviderId(c) == 'system' ||
                 _detectProviderId(c) == null)))) {
            ordered.add(c);
          }
        }
      }
      for (final c in allCals) {
        if (!ordered.any((o) => o.id == c.id)) {
          ordered.add(c);
        }
      }

      final int hour = startTime?.hour ?? 9;
      final int minute = startTime?.minute ?? 0;
      final start = DateTime(
          expiryDate.year, expiryDate.month, expiryDate.day, hour, minute);
      final end = start.add(const Duration(minutes: 30));

      for (final Calendar cal in ordered) {
        if (cal.id == null) continue;

        bool mayExist = false;
        try {
          final check = await _plugin.retrieveEvents(
            cal.id!,
            RetrieveEventsParams(eventIds: [eventId]),
          );
          mayExist = check.data?.isNotEmpty == true;
        } catch (e) {
          mayExist = cal.id == calendarId ||
              _detectProviderId(cal) == providerId ||
              ((providerId == 'samsung' || providerId == 'system') &&
               (_detectProviderId(cal) == 'samsung' ||
                _detectProviderId(cal) == 'system' ||
                _detectProviderId(cal) == null));
        }

        if (!mayExist) continue;

        try {
          final event = Event(
            cal.id!,
            eventId: eventId,
            title: title,
            description: description,
            start: tz.TZDateTime.from(start, tz.local),
            end: tz.TZDateTime.from(end, tz.local),
            reminders: [Reminder(minutes: reminderMinutes)],
            allDay: startTime == null,
          );

          final res = await _plugin.createOrUpdateEvent(event);
          if (res?.isSuccess == true && res?.data != null) {
            return CreatedEvent(res!.data!, cal.id!);
          }
        } catch (e) {
          //
        }
      }
    } catch (e) {
      //
    }
    return null;
  }

  Future<bool> deleteEvent({
    required String eventId,
    required String providerId,
    String? calendarId,
  }) async {
    try {
      if (!await _ensurePermission()) return false;

      final List<Calendar> allCals = (await _retrieveWritableCalendars())
          .where((c) => c.id != null)
          .toList();

      final List<Calendar> ordered = <Calendar>[];
      if (calendarId != null && calendarId.isNotEmpty) {
        ordered.addAll(allCals.where((c) => c.id == calendarId));
      }
      for (final c in allCals) {
        if (!ordered.any((o) => o.id == c.id)) {
          ordered.add(c);
        }
      }

      for (final cal in ordered) {
        if (cal.id == null) continue;
        try {
          bool exists = false;
          try {
            final check = await _plugin.retrieveEvents(
              cal.id!,
              RetrieveEventsParams(eventIds: [eventId]),
            );
            exists = check.data?.isNotEmpty == true;
          } catch (_) {
            exists = cal.id == calendarId;
          }
          if (!exists) continue;

          final res = await _plugin.deleteEvent(cal.id!, eventId);
          if (res.isSuccess == true) {
            return true;
          }
        } catch (e) {
          //
        }
      }
    } catch (e) {
      //
    }
    return false;
  }

  // ── ICS-Methoden (unverändert) ─────────────────────────────────
  String buildIcsContent({
    required String title,
    required String description,
    required DateTime expiryDate,
    required int reminderMinutes,
    String? uid,
  }) {
    final uidVal = (uid == null || uid.isEmpty)
        ? '${DateTime.now().millisecondsSinceEpoch}@garantiemanager'
        : uid;
    final start =
        DateTime(expiryDate.year, expiryDate.month, expiryDate.day, 9, 0);
    final end = start.add(const Duration(minutes: 30));

    return 'BEGIN:VCALENDAR\r\n'
        'VERSION:2.0\r\n'
        'PRODID:-//CarloOpenSource//Warranty Manager//EN\r\n'
        'CALSCALE:GREGORIAN\r\n'
        'METHOD:PUBLISH\r\n'
        'BEGIN:VEVENT\r\n'
        'UID:$uidVal\r\n'
        'DTSTAMP:${_icsDate(DateTime.now().toUtc())}\r\n'
        'DTSTART:${_icsDate(start)}\r\n'
        'DTEND:${_icsDate(end)}\r\n'
        'SUMMARY:${_escapeIcs(title)}\r\n'
        'DESCRIPTION:${_escapeIcs(description)}\r\n'
        'BEGIN:VALARM\r\n'
        'TRIGGER:-PT${reminderMinutes}M\r\n'
        'ACTION:DISPLAY\r\n'
        'DESCRIPTION:${_escapeIcs(title)}\r\n'
        'END:VALARM\r\n'
        'END:VEVENT\r\n'
        'END:VCALENDAR\r\n';
  }

  String buildIcsForEntries({
    required List<Map<String, String>> entries,
    required int reminderMinutes,
  }) {
    final buffer = StringBuffer();
    buffer.write('BEGIN:VCALENDAR\r\n');
    buffer.write('VERSION:2.0\r\n');
    buffer.write('PRODID:-//CarloOpenSource//Warranty Manager//EN\r\n');
    buffer.write('CALSCALE:GREGORIAN\r\n');
    buffer.write('METHOD:PUBLISH\r\n');

    for (final entry in entries) {
      final name = (entry['name'] ?? 'Unbekannt').trim();
      if (name.isEmpty) continue;
      final expiry = parseEntryExpiry(entry['ablaufDatum']);
      if (expiry == null) continue;

      final start = DateTime(expiry.year, expiry.month, expiry.day, 9, 0);
      final end = start.add(const Duration(minutes: 30));
      final uidBase = '${name.hashCode}-${entry['ablaufDatum'] ?? ''}'
          .replaceAll(' ', '')
          .replaceAll('.', '');

      final descParts = <String>[];
      descParts.add('Garantie läuft ab am ${entry['ablaufDatum']}');
      if ((entry['woGekauft'] ?? '').isNotEmpty &&
          entry['woGekauft'] != 'Unbekannt') {
        descParts.add('Gekauft bei: ${entry['woGekauft']}');
      }
      if ((entry['bemerkung'] ?? '').trim().isNotEmpty) {
        descParts.add('Bemerkung: ${entry['bemerkung']}');
      }

      buffer.write('BEGIN:VEVENT\r\n');
      buffer.write('UID:$uidBase@garantiemanager\r\n');
      buffer.write('DTSTAMP:${_icsDate(DateTime.now().toUtc())}\r\n');
      buffer.write('DTSTART:${_icsDate(start)}\r\n');
      buffer.write('DTEND:${_icsDate(end)}\r\n');
      buffer.write('SUMMARY:${_escapeIcs('Garantie: $name')}\r\n');
      buffer.write('DESCRIPTION:${_escapeIcs(descParts.join('\\n'))}\r\n');
      buffer.write('BEGIN:VALARM\r\n');
      buffer.write('TRIGGER:-PT${reminderMinutes}M\r\n');
      buffer.write('ACTION:DISPLAY\r\n');
      buffer.write('DESCRIPTION:${_escapeIcs('Garantie: $name')}\r\n');
      buffer.write('END:VALARM\r\n');
      buffer.write('END:VEVENT\r\n');
    }

    buffer.write('END:VCALENDAR\r\n');
    return buffer.toString();
  }

  String _escapeIcs(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '');

  String _icsDate(DateTime dt) {
    final u = dt.toUtc();
    return '${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}'
        'T'
        '${u.hour.toString().padLeft(2, '0')}'
        '${u.minute.toString().padLeft(2, '0')}'
        '${u.second.toString().padLeft(2, '0')}Z';
  }

  Future<void> shareIcsFile({
    required String icsContent,
    required String fileName,
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(icsContent);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar')],
        subject: subject ?? fileName,
      ),
    );
  }

  Future<CalendarTestResult> testProvider(String providerId) async {
    _ensureTz();
    final log = <String>[];

    try {
      final hasPermissionBefore = (await _plugin.hasPermissions()).data == true;
      log.add('Permission before request: $hasPermissionBefore');

      if (!await _ensurePermission()) {
        log.add('❌ No calendar permission (even after retry).');
        return CalendarTestResult(false, log.join('\n'));
      }
      log.add('✅ Permission granted.');

      final List<Calendar> rawCalendars = await _retrieveWritableCalendars();
      log.add('Writable calendars found: ${rawCalendars.length}');
      for (final c in rawCalendars) {
        log.add('  • id=${c.id} name="${c.name}" '
            'accountType="${c.accountType}" accountName="${c.accountName}" '
            'detected="${_detectProviderId(c) ?? 'unknown'}"');
      }

      final List<Calendar> calendars =
          rawCalendars.where((c) => c.id != null).toList();

      if (calendars.isEmpty) {
        log.add('❌ No writable calendars returned by the device. '
            'Check: Settings → Apps → Warranty Manager → Permissions → '
            '"Calendar" set to "Allow".');
        return CalendarTestResult(false, log.join('\n'));
      }

      final matching = <Calendar>[];
      final crossFallback = <Calendar>[];
      final others = <Calendar>[];

      for (final cal in calendars) {
        final det = _detectProviderId(cal);
        if (det == providerId) {
          matching.add(cal);
        } else if ((providerId == 'samsung' || providerId == 'system') &&
            (det == 'samsung' || det == 'system' || det == null)) {
          crossFallback.add(cal);
        } else {
          others.add(cal);
        }
      }

      final ordered = [...matching, ...crossFallback, ...others];

      for (final cal in ordered) {
        if (cal.id == null) continue;
        try {
          final now = DateTime.now().add(const Duration(minutes: 5));
          final test = Event(
            cal.id!,
            title: 'Warranty Manager Test',
            description: 'Test entry — can be deleted.',
            start: tz.TZDateTime.from(now, tz.local),
            end: tz.TZDateTime.from(
                now.add(const Duration(minutes: 10)), tz.local),
          );

          final res = await _plugin.createOrUpdateEvent(test);

          if (res?.isSuccess == true && res?.data != null) {
            log.add('✅ Write test succeeded → '
                'calId=${cal.id} name="${cal.name}"');
            return CalendarTestResult(true, log.join('\n'));
          }
          final errs = res?.errors
                  .map((e) => '${e.errorCode}: ${e.errorMessage}')
                  .join(' | ') ??
              '';
          log.add('✗ Write failed → calId=${cal.id} name="${cal.name}" '
              'errors=$errs');
        } catch (e) {
          log.add('✗ Write exception → calId=${cal.id} name="${cal.name}" '
              'error=$e');
        }
      }
    } catch (e) {
      log.add('❌ Outer exception → $e');
    }
    return CalendarTestResult(false, log.join('\n'));
  }
}