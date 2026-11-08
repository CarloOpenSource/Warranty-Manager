import 'package:flutter/material.dart';
import '../settings_provider.dart';

/// Zentrale Logik zum Rendern von Notification-Bausteinen.
/// Wird sowohl für die Live-Vorschau in den Einstellungen als auch
/// für die tatsächliche Notification verwendet, damit beides identisch ist.
class NotificationTemplateHelper {
  static const String typeName = 'name';
  static const String typeBuyDate = 'buyDate';
  static const String typeExpiryDate = 'expiryDate';
  static const String typeDaysLeft = 'daysLeft';
  static const String typeStore = 'store';
  static const String typePrice = 'price';
  static const String typeDuration = 'duration';
  static const String typeCategory = 'category';
  static const String typeRemarks = 'remarks';
  // typePhotoCount wurde entfernt – Fotoanzahl wird nicht mehr in der
  // Benachrichtigung angezeigt.
  // typeDetailLink wurde entfernt – beim Tippen auf die Notification
  // wird direkt der Detail-Screen geöffnet.
  // typeScreenshot wurde entfernt – kein "Screenshot-Hinweis" mehr.
  static const String typeCustom = 'custom';

  // ── Format-Optionen (nur für daysLeft + duration) ──
  static const String formatAuto = 'auto';
  static const String formatDays = 'days';
  static const String formatWeeks = 'weeks';
  static const String formatMonths = 'months';
  static const String formatYears = 'years';

  static const List<String> formatOptions = [
    formatAuto,
    formatDays,
    formatWeeks,
    formatMonths,
    formatYears,
  ];

  /// Bausteine, die nur einmal hinzugefügt werden dürfen.
  static const List<String> singleUseTypes = [
    typeName,
    typeBuyDate,
    typeExpiryDate,
    typeDaysLeft,
    typeStore,
    typePrice,
    typeDuration,
    typeCategory,
    typeRemarks,
  ];

  /// Maximale Anzahl eigener Textbausteine (typeCustom) pro Vorlage.
  static const int maxCustomParts = 5;

  /// Zählt, wie viele eigene Textbausteine in der Vorlage vorhanden sind.
  static int countCustomParts(List<Map<String, String>> parts) {
    return parts.where((p) => p['type'] == typeCustom).length;
  }

  // ── Trennzeichen zwischen den Bausteinen ──
  static const String separatorDot = 'dot';
  static const String separatorComma = 'comma';
  static const String separatorCustom = 'custom';

  /// Maximale Länge eines eigenen Trennzeichens (in Zeichen).
  static const int maxSeparatorLength = 20;

  /// Standard-Trennzeichen (Punkt mit Leerzeichen).
  static const String defaultSeparator = ' • ';

  /// SharedPreferences-Schlüssel der Trennzeichen-Einstellung.
  static const String prefSeparatorMode = 'notif_separator_mode';
  static const String prefSeparatorCustom = 'notif_separator_custom';

  /// Maximale Textlänge, die Android pro Benachrichtigung zulässt.
  /// Alles darüber hinaus schneidet das System ab.
  static const int maxNotificationChars = 5120;

  /// Ermittelt das tatsächlich verwendete Trennzeichen aus Modus und
  /// eigenem Text. Ungültige oder leere Werte ergeben das Standard-Trennzeichen.
  static String resolveSeparator(String? mode, String? customText) {
    switch (mode) {
      case separatorComma:
        return ', ';
      case separatorCustom:
        if (customText == null || customText.isEmpty) return defaultSeparator;
        final chars = customText.characters;
        return chars.length > maxSeparatorLength
            ? chars.take(maxSeparatorLength).toString()
            : customText;
      case separatorDot:
      default:
        return defaultSeparator;
    }
  }

  // ── Zusätzliche Texte (Trennzeichen + Längen-Warnung) ──
  static const Map<String, Map<String, String>> _extraTexts = {
    'de': {
      'sep_title': 'Trennzeichen',
      'sep_desc': 'Wird zwischen den Bausteinen der Benachrichtigung eingefügt.',
      'sep_dot': 'Punkt',
      'sep_comma': 'Komma',
      'sep_custom_label': 'Eigenes Trennzeichen',
      'sep_custom_helper': 'Leerzeichen zählen mit',
      'notif_too_long':
          'Achtung: Die Benachrichtigung ist sehr lang ({count} Zeichen). Android zeigt höchstens {max} Zeichen an, möglicherweise wird sie nicht vollständig angezeigt.',
    },
    'en': {
      'sep_title': 'Separator',
      'sep_desc': 'Inserted between the parts of the notification.',
      'sep_dot': 'Dot',
      'sep_comma': 'Comma',
      'sep_custom_label': 'Custom separator',
      'sep_custom_helper': 'Spaces are counted',
      'notif_too_long':
          'Warning: The notification is very long ({count} characters). Android shows at most {max} characters, so it may not be displayed completely.',
    },
    'fr': {
      'sep_title': 'Séparateur',
      'sep_desc': 'Inséré entre les éléments de la notification.',
      'sep_dot': 'Point',
      'sep_comma': 'Virgule',
      'sep_custom_label': 'Séparateur personnalisé',
      'sep_custom_helper': 'Les espaces sont comptés',
      'notif_too_long':
          "Attention : la notification est très longue ({count} caractères). Android affiche au maximum {max} caractères, elle risque donc de ne pas s'afficher en entier.",
    },
    'es': {
      'sep_title': 'Separador',
      'sep_desc': 'Se inserta entre los elementos de la notificación.',
      'sep_dot': 'Punto',
      'sep_comma': 'Coma',
      'sep_custom_label': 'Separador personalizado',
      'sep_custom_helper': 'Los espacios cuentan',
      'notif_too_long':
          'Atención: la notificación es muy larga ({count} caracteres). Android muestra como máximo {max} caracteres, por lo que puede que no se muestre completa.',
    },
  };

  /// Liefert einen der zusätzlichen Texte in der gewünschten Sprache
  /// (Fallback: Englisch).
  static String extraText(String langCode, String key) {
    return _extraTexts[langCode]?[key] ?? _extraTexts['en']?[key] ?? key;
  }

  /// Alle verfügbaren Baustein-Typen (inkl. custom).
  static const List<String> availableTypes = [
    typeName,
    typeBuyDate,
    typeExpiryDate,
    typeDaysLeft,
    typeStore,
    typePrice,
    typeDuration,
    typeCategory,
    typeRemarks,
    typeCustom,
  ];

  // ── Optionen pro Baustein-Typ ──

  /// Ob der Baustein überhaupt irgendeine Einstellung zum Anpassen bietet.
  /// Wenn false → der Baustein kann nur gelöscht und sortiert werden,
  /// aber NICHT über den Konfigurationsdialog bearbeitet werden.
  static bool hasAnySettings(String type) {
    return hasLabelOption(type) ||
        hasFormatOption(type) ||
        type == typeCustom;
  }

  static bool hasLabelOption(String type) {
    switch (type) {
      case typeName:
      case typeStore:
      case typePrice:
      case typeCustom:
      // Legacy-Typen (sollten durch _loadTemplate bereits entfernt sein,
      // aber defensiv behandeln):
      case 'screenshot':
      case 'detailLink':
      case 'photoCount':
        return false;
      default:
        return true;
    }
  }

  static bool hasFormatOption(String type) {
    return type == typeDaysLeft || type == typeDuration;
  }

  /// Standardfarbe pro Baustein-Typ (wird nur noch für die
  /// Icon-Darstellung in der Bausteinliste genutzt).
  static Color colorForType(String type) {
    switch (type) {
      case typeName:
        return Colors.blue;
      case typeBuyDate:
        return Colors.green;
      case typeExpiryDate:
        return Colors.orange;
      case typeDaysLeft:
        return Colors.purple;
      case typeStore:
        return Colors.teal;
      case typePrice:
        return Colors.amber.shade700;
      case typeDuration:
        return Colors.indigo;
      case typeCategory:
        return Colors.cyan.shade700;
      case typeRemarks:
        return Colors.pink.shade400;
      case typeCustom:
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  static String getLabelKeyForType(String type) {
    switch (type) {
      case typeName:
        return 'product_name';
      case typeBuyDate:
        return 'buy_date';
      case typeExpiryDate:
        return 'expiry';
      case typeDaysLeft:
        return 'notif_part_days_left';
      case typeStore:
        return 'bought_at';
      case typePrice:
        return 'price';
      case typeDuration:
        return 'warranty_duration';
      case typeCategory:
        return 'category';
      case typeRemarks:
        return 'remarks';
      case typeCustom:
        return 'notif_part_custom';
      default:
        return 'unknown';
    }
  }

  static String getFormatLabelKey(String format) {
    switch (format) {
      case formatDays:
        return 'notif_format_days';
      case formatWeeks:
        return 'notif_format_weeks';
      case formatMonths:
        return 'notif_format_months';
      case formatYears:
        return 'notif_format_years';
      case formatAuto:
      default:
        return 'notif_format_auto';
    }
  }

  /// Erzeugt einen neuen Baustein mit sinnvollen Standardwerten.
  static Map<String, String> createPart(String type, {String? customText}) {
    final part = <String, String>{'type': type};
    if (hasLabelOption(type)) part['showLabel'] = 'true';
    if (hasFormatOption(type)) part['format'] = formatAuto;
    if (type == typeCustom && customText != null) part['text'] = customText;
    return part;
  }

  static bool getShowLabel(Map<String, String> part) {
    return part['showLabel'] != 'false';
  }

  static String getFormat(Map<String, String> part) {
    return part['format'] ?? formatAuto;
  }

  static List<Map<String, String>> defaultTemplate() {
    return [
      createPart(typeName),
      createPart(typeExpiryDate),
      createPart(typeDaysLeft),
    ];
  }

  static DateTime? parseDateStr(String? s) {
    if (s == null || s.isEmpty) return null;
    final p = s.split('.');
    if (p.length == 3) {
      try {
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _formatDurationValue({
    required String langCode,
    required int totalDays,
    required String format,
  }) {
    int value;
    String singularKey;
    String pluralKey;

    switch (format) {
      case formatDays:
        value = totalDays;
        singularKey = 'day_singular';
        pluralKey = 'days_plural';
        break;
      case formatWeeks:
        value = (totalDays / 7).round();
        singularKey = 'week_singular';
        pluralKey = 'weeks_plural';
        break;
      case formatMonths:
        value = (totalDays / 30.44).round();
        singularKey = 'month_singular';
        pluralKey = 'months_plural';
        break;
      case formatYears:
        value = (totalDays / 365.25).round();
        singularKey = 'year_singular';
        pluralKey = 'years_plural';
        break;
      case formatAuto:
      default:
        final roundedYears = (totalDays / 365.25).round();
        if (roundedYears >= 1 &&
            (totalDays - roundedYears * 365.25).abs() <= 20) {
          value = roundedYears;
          singularKey = 'year_singular';
          pluralKey = 'years_plural';
        } else {
          final months = (totalDays / 30.44).round();
          if (months >= 1) {
            value = months;
            singularKey = 'month_singular';
            pluralKey = 'months_plural';
          } else if (totalDays >= 7) {
            value = totalDays ~/ 7;
            singularKey = 'week_singular';
            pluralKey = 'weeks_plural';
          } else {
            value = totalDays;
            singularKey = 'day_singular';
            pluralKey = 'days_plural';
          }
        }
    }

    if (value < 1) value = 1;
    final unit = value == 1
        ? getText(langCode, singularKey)
        : getText(langCode, pluralKey);
    return '$value $unit';
  }

  static String _renderDaysLeft({
    required String langCode,
    required Map<String, String>? gerat,
    required DateTime? referenceDate,
    required bool showLabel,
    required String format,
  }) {
    final expiry = parseDateStr(gerat?['ablaufDatum']);
    if (expiry == null) return '';

    final ref = referenceDate ?? DateTime.now();
    final refDay = DateTime(ref.year, ref.month, ref.day);
    final days = expiry.difference(refDay).inDays;

    if (days == 0) return getText(langCode, 'expires_today');

    if (days > 0) {
      final text = _formatDurationValue(
        langCode: langCode,
        totalDays: days,
        format: format,
      );
      return showLabel ? '${getText(langCode, 'days_left')}$text' : text;
    }

    final absDays = days.abs();
    if (showLabel) {
      final unit = absDays == 1
          ? getText(langCode, 'expired_day_singular')
          : getText(langCode, 'expired_day_plural');
      return '${getText(langCode, 'expired_since')}$absDays$unit';
    }
    final unit = absDays == 1
        ? getText(langCode, 'day_singular')
        : getText(langCode, 'days_plural');
    return '$absDays $unit';
  }

  static String _renderDuration({
    required String langCode,
    required Map<String, String>? gerat,
    required bool showLabel,
    required String format,
  }) {
    final buy = parseDateStr(gerat?['kaufDatum']);
    final expiry = parseDateStr(gerat?['ablaufDatum']);
    if (buy == null || expiry == null) return '';
    final totalDays = expiry.difference(buy).inDays;
    if (totalDays <= 0) return '';

    final text = _formatDurationValue(
      langCode: langCode,
      totalDays: totalDays,
      format: format,
    );
    return showLabel
        ? '${getText(langCode, 'warranty_duration')}: $text'
        : text;
  }

  /// Rendert einen einzelnen Baustein in Text.
  static String renderPart({
    required String langCode,
    required Map<String, String> part,
    required Map<String, String>? gerat,
    required String currencySymbol,
    required DateTime? referenceDate,
  }) {
    final type = part['type'] ?? '';
    final showLabel = getShowLabel(part);
    final format = getFormat(part);

    switch (type) {
      case typeName:
        final n = gerat?['name'] ?? '';
        return n.isEmpty ? getText(langCode, 'unknown') : n;
      case typeBuyDate:
        final d = gerat?['kaufDatum'] ?? '';
        if (d.isEmpty) return '';
        return showLabel ? '${getText(langCode, 'buy_date')}: $d' : d;
      case typeExpiryDate:
        final d = gerat?['ablaufDatum'] ?? '';
        if (d.isEmpty) return '';
        return showLabel ? '${getText(langCode, 'expiry')}: $d' : d;
      case typeDaysLeft:
        return _renderDaysLeft(
          langCode: langCode,
          gerat: gerat,
          referenceDate: referenceDate,
          showLabel: showLabel,
          format: format,
        );
      case typeStore:
        final s = gerat?['woGekauft'] ?? '';
        if (s.isEmpty || s == 'Unbekannt') {
          return '${getText(langCode, 'bought_at')}: ${getText(langCode, 'unknown')}';
        }
        return '${getText(langCode, 'bought_at')}: $s';
      case typePrice:
        final p = gerat?['preis'] ?? '';
        if (p.isEmpty || p == 'Unbekannt') return '';
        final w = gerat?['waehrung'] ?? currencySymbol;
        return '$p $w';
      case typeDuration:
        return _renderDuration(
          langCode: langCode,
          gerat: gerat,
          showLabel: showLabel,
          format: format,
        );
      case typeCategory:
        final c = gerat?['kategorie'] ?? '';
        if (c.isEmpty) return '';
        final catName = getText(langCode, c);
        return showLabel
            ? '${getText(langCode, 'category')}: $catName'
            : catName;
      case typeRemarks:
        final r = gerat?['bemerkung'] ?? '';
        if (r.isEmpty) return '';
        return showLabel ? '${getText(langCode, 'remarks')}: $r' : r;
      case typeCustom:
        return part['text'] ?? '';
      // Legacy-Typen liefern leeren Text (defensiv).
      case 'detailLink':
      case 'screenshot':
      case 'photoCount':
      default:
        return '';
    }
  }

  static String buildBody({
    required String langCode,
    required List<Map<String, String>> template,
    required String produktName,
    required String ablaufDatumStr,
    required Map<String, String>? gerat,
    required String currencySymbol,
    required DateTime? referenceDate,
    String separator = defaultSeparator,
  }) {
    if (template.isEmpty) {
      return '${getText(langCode, 'notif_body')}$ablaufDatumStr${getText(langCode, 'notif_body_end')}';
    }

    final effective = <String, String>{};
    if (gerat != null) effective.addAll(gerat);
    if ((effective['name'] ?? '').isEmpty) {
      effective['name'] = produktName;
    }
    if ((effective['ablaufDatum'] ?? '').isEmpty) {
      effective['ablaufDatum'] = ablaufDatumStr;
    }

    final buffer = StringBuffer();
    bool first = true;
    for (final part in template) {
      // Legacy-Blöcke komplett überspringen
      final t = part['type'] ?? '';
      if (t == 'detailLink' || t == 'screenshot' || t == 'photoCount') {
        continue;
      }

      final text = renderPart(
        langCode: langCode,
        part: part,
        gerat: effective,
        currencySymbol: currencySymbol,
        referenceDate: referenceDate,
      );
      if (text.isEmpty) continue;
      if (!first) buffer.write(separator);
      buffer.write(text);
      first = false;
    }
    return buffer.toString();
  }
}