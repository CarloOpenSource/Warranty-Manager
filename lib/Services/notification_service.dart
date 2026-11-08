import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'settings_provider.dart';
import 'Helpers/notification_template_helper.dart';
import '../Screens/detail_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Globaler Navigator-Key, damit wir aus der Notification heraus
  /// den Detail-Screen öffnen können.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Wenn die App noch nicht bereit ist, merken wir uns das Payload
  /// und der HomeScreen konsumiert es beim Start.
  static String? _pendingPayload;

  /// Wird von HomeScreen aufgerufen, nachdem die App geladen ist.
  static String? consumePendingPayload() {
    final p = _pendingPayload;
    _pendingPayload = null;
    return p;
  }

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone()
          .then((info) => info.identifier);
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _handleNotificationBackground,
    );

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.requestExactAlarmsPermission();

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'garantie_channel_v2',
        'Garantie Erinnerungen',
        description: 'Benachrichtigungen für ablaufende Garantien',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }

    // Prüfen, ob App per Notification-Tap gestartet wurde
    try {
      final launch =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final payload = launch?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          _pendingPayload = payload;
        }
      }
    } catch (_) {}
  }

  /// Wird aufgerufen, wenn der Nutzer auf die Notification tippt
  /// (App im Vordergrund oder Hintergrund).
  @pragma('vm:entry-point')
  static void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    final nav = navigatorKey.currentState;
    if (nav != null) {
      _navigateToDetail(nav, payload);
    } else {
      _pendingPayload = payload;
    }
  }

  /// Wird im Hintergrund-Isolate aufgerufen – hier nur cachen,
  /// die eigentliche Navigation übernimmt _handleNotificationResponse
  /// sobald die App im Vordergrund ist.
  @pragma('vm:entry-point')
  static void _handleNotificationBackground(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _pendingPayload = payload;
  }

  /// Öffnet den Detail-Screen für das zum Payload passende Gerät.
  static Future<void> _navigateToDetail(
    NavigatorState nav,
    String payload,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('gerate_liste');
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final list = decoded
          .whereType<Map>()
          .map((m) => Map<String, String>.from(
              m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))))
          .toList();

      final device = list.firstWhere(
        (d) => d['notificationId'] == payload,
        orElse: () => <String, String>{},
      );

      if (device.isEmpty) return;

      await nav.push(
        MaterialPageRoute(
          builder: (context) => DetailScreen(
            gerat: device,
            onEdit: () {},
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> planErinnerung({
    required int id,
    required String titel,
    required String text,
    required DateTime datum,
    String? payload,
  }) async {
    final scheduledDate = tz.TZDateTime.from(datum, tz.local);

    try {
      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: titel,
        body: text,
        scheduledDate: scheduledDate,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'garantie_channel_v2',
            'Garantie Erinnerungen',
            channelDescription:
                'Benachrichtigungen für ablaufende Garantien',
            importance: Importance.max,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            // Ohne BigTextStyle zeigt Android den Text nur einzeilig und
            // schneidet ihn mit "…" ab. Mit BigTextStyle lässt sich die
            // Benachrichtigung aufklappen und zeigt den kompletten Text.
            styleInformation: BigTextStyleInformation(text),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      //
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id: id);
  }

  /// Lädt die Benutzer-Vorlage aus den SharedPreferences (leer = Legacy-Format).
  Future<List<Map<String, String>>> _loadTemplate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('notif_template');
      if (raw == null || raw.isEmpty) return <Map<String, String>>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, String>>[];
      return decoded
          .whereType<Map>()
          .map((m) => m.map(
              (k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
          // Alte detailLink-Blöcke herausfiltern
          .where((p) => p['type'] != 'detailLink' &&
              p['type'] != 'screenshot' &&
              p['type'] != 'photoCount')
          .toList();
    } catch (_) {
      return <Map<String, String>>[];
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String produktName,
    required String ablaufDatumStr,
    required DateTime benachrichtigungsDatum,
    required String langCode,
    /// Optional: kompletter Geräte-Datensatz, damit alle Bausteine
    /// (Kaufdatum, Preis, Händler, Dauer, Fotoanzahl) gefüllt werden können.
    Map<String, String>? gerat,
  }) async {
    try {
      if (!benachrichtigungsDatum.isAfter(DateTime.now())) return;

      final prefs = await SharedPreferences.getInstance();
      final currencySymbol = prefs.getString('currency_symbol') ?? '€';
      final template = await _loadTemplate();
      final separator = NotificationTemplateHelper.resolveSeparator(
        prefs.getString(NotificationTemplateHelper.prefSeparatorMode),
        prefs.getString(NotificationTemplateHelper.prefSeparatorCustom),
      );

      final String titel =
          '${getText(langCode, 'notif_title')}$produktName';

      final String text = NotificationTemplateHelper.buildBody(
        langCode: langCode,
        template: template,
        produktName: produktName,
        ablaufDatumStr: ablaufDatumStr,
        gerat: gerat,
        currencySymbol: currencySymbol,
        referenceDate: benachrichtigungsDatum,
        separator: separator,
      );

      // Payload = Notification-ID → erlaubt später die eindeutige
      // Zuordnung zum Gerät beim Tippen auf die Notification.
      await planErinnerung(
        id: id,
        titel: titel,
        text: text,
        datum: benachrichtigungsDatum,
        payload: id.toString(),
      );
    } catch (e) {
      //
    }
  }
}