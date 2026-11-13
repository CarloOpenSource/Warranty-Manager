import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:garantiemanager/Translations/translations_de.dart';
import 'package:garantiemanager/Translations/translations_en.dart';
import 'package:garantiemanager/Translations/translations_fr.dart';
import 'package:garantiemanager/Translations/translations_es.dart';

const List<Map<String, String>> appCurrencies = [
  {'label_key': 'curr_eur', 'symbol': '€'},
  {'label_key': 'curr_chf', 'symbol': 'CHF'},
  {'label_key': 'curr_usd', 'symbol': '\$'},
  {'label_key': 'curr_cad', 'symbol': 'CA\$'},
  {'label_key': 'curr_aud', 'symbol': 'A\$'},
  {'label_key': 'curr_nzd', 'symbol': 'NZ\$'},
  {'label_key': 'curr_gbp', 'symbol': '£'},
  {'label_key': 'curr_mxn', 'symbol': 'MXN'},
  {'label_key': 'curr_ars', 'symbol': 'ARS'},
  {'label_key': 'curr_clp', 'symbol': 'CLP'},
  {'label_key': 'curr_cop', 'symbol': 'COP'},
  {'label_key': 'curr_pen', 'symbol': 'PEN'},
  {'label_key': 'curr_uyu', 'symbol': 'UYU'},
  {'label_key': 'curr_pyg', 'symbol': '₲'},
  {'label_key': 'curr_bob', 'symbol': 'Bs.'},
  {'label_key': 'curr_brl', 'symbol': 'R\$'},
  {'label_key': 'curr_crc', 'symbol': '₡'},
  {'label_key': 'curr_gtq', 'symbol': 'Q'},
  {'label_key': 'curr_hnl', 'symbol': 'L'},
  {'label_key': 'curr_nio', 'symbol': 'C\$'},
  {'label_key': 'curr_dop', 'symbol': 'RD\$'},
  {'label_key': 'curr_htg', 'symbol': 'G'},
  {'label_key': 'curr_cup', 'symbol': 'CUP'},
  {'label_key': 'curr_xof', 'symbol': 'XOF'},
  {'label_key': 'curr_xaf', 'symbol': 'XAF'},
  {'label_key': 'curr_mad', 'symbol': 'MAD'},
  {'label_key': 'curr_dzd', 'symbol': 'DZD'},
  {'label_key': 'curr_tnd', 'symbol': 'DT'},
  {'label_key': 'curr_kmf', 'symbol': 'CF'},
  {'label_key': 'curr_djf', 'symbol': 'Fdj'},
  {'label_key': 'curr_rwf', 'symbol': 'RF'},
  {'label_key': 'curr_bif', 'symbol': 'FBu'},
  {'label_key': 'curr_xcd', 'symbol': 'EC\$'},
  {'label_key': 'curr_xpf', 'symbol': 'XPF'},
];

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _languageCode = 'de';
  String _currencySymbol = '€';
  bool _useAmPm = false;
  String _sortOrder = 'a_z';

  // --- WISCHGESTEN (SWIPE ACTIONS) ---
  bool _useSwipeActions = false;
  String _swipeRightAction = 'edit';
  String _swipeLeftAction = 'delete';

  // --- KALENDER-EINSTELLUNGEN ---
  bool _autoAddToCalendar = false;
  bool _autoUpdateCalendar = false;
  String _preferredCalendarApp = 'system';
  int _defaultReminderMinutes = 1440;

  // >>> NEU: Notification-Template (Bausteine für den Body)
  List<Map<String, String>> _notifTemplate = [];

  // --- DESIGN-VARIABLEN ---
  Color? _primaryColor;
  Color? _tileColor;
  Color? _textColor;
  Color? _buttonColor;
  Color? _backgroundColor;
  Color? _shadowColor;
  List<Color> _customPalette = [];
  Map<String, Color> _categoryColors = {};
  List<String> _customCategories = [];

  Map<String, Map<String, int>> _screenColorOverrides = {};

  double _fontSizeScale = 1.0;
  double _tileBorderRadius = 12.0;
  double _buttonHeight = 48.0;
  double _shadowBlur = 4.0;
  String _buttonAlignment = 'center';
  String _fontFamily = 'default';

  // --- AKZENT- UND BUTTONFARBE ---
  static const int maxSavedColors = 5;
  Color? _accentColor;
  Color? _accentButtonColor;
  List<Color> _savedAccentColors = [];
  List<Color> _savedButtonColors = [
    Colors.blueAccent,
    Colors.teal,
    Colors.deepPurple,
    Colors.orange,
    Colors.redAccent
  ];
  bool _colorPickerUnlocked = false;

  // --- GETTER ---
  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  String get currencySymbol => _currencySymbol;
  bool get useAmPm => _useAmPm;
  String get sortOrder => _sortOrder;

  bool get useSwipeActions => _useSwipeActions;
  String get swipeRightAction => _swipeRightAction;
  String get swipeLeftAction => _swipeLeftAction;

  // --- KALENDER GETTER ---
  bool get autoAddToCalendar => _autoAddToCalendar;
  bool get autoUpdateCalendar => _autoUpdateCalendar;
  String get preferredCalendarApp => _preferredCalendarApp;
  int get defaultReminderMinutes => _defaultReminderMinutes;

  // >>> NEU: Getter für Notification-Template
  List<Map<String, String>> get notifTemplate =>
      List.unmodifiable(_notifTemplate);

  Color? get primaryColor => _primaryColor;
  Color? get tileColor => _tileColor;
  Color? get textColor => _textColor;
  Color? get buttonColor => _buttonColor;
  Color? get backgroundColor => _backgroundColor;
  Color? get shadowColor => _shadowColor;
  List<Color> get customPalette => _customPalette;
  Map<String, Color> get categoryColors => _categoryColors;
  List<String> get customCategories => _customCategories;
  Map<String, Map<String, int>> get screenColorOverrides => _screenColorOverrides;

  double get fontSizeScale => _fontSizeScale;
  double get tileBorderRadius => _tileBorderRadius;
  double get buttonHeight => _buttonHeight;
  double get shadowBlur => _shadowBlur;
  String get buttonAlignment => _buttonAlignment;
  String get fontFamily => _fontFamily;

  Color? get accentColor => _accentColor;
  Color? get accentButtonColor => _accentButtonColor;
  List<Color> get savedAccentColors => List.unmodifiable(_savedAccentColors);
  List<Color> get savedButtonColors => List.unmodifiable(_savedButtonColors);
  bool get colorPickerUnlocked => _colorPickerUnlocked;
  bool get hasCustomAccent => _accentColor != null;
  bool get hasCustomButtonColor => _accentButtonColor != null;

  static Color contrastColor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }

  Color appBarBackground(Brightness brightness) {
    return _accentColor ??
        (brightness == Brightness.dark ? Colors.grey.shade900 : Colors.blueAccent);
  }

  Color get appBarForeground =>
      _accentColor == null ? Colors.white : contrastColor(_accentColor!);

  Color bottomBarColor(BuildContext context) =>
      _accentColor ?? Theme.of(context).cardColor;

  Color bottomBarIconColor(BuildContext context) {
    final bar = bottomBarColor(context);
    final btn = appButtonColor;
    if ((bar.computeLuminance() - btn.computeLuminance()).abs() < 0.15) {
      return contrastColor(bar);
    }
    return btn;
  }

  SwitchThemeData buildSwitchTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final Color btn = appButtonColor;
    final Color onBtn = onAppButtonColor;
    final Color bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color offThumb = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final Color offTrack = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final Color outline = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    final bool lowContrast = (btn.computeLuminance() - bg.computeLuminance()).abs() < 0.25;

    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? onBtn : offThumb;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? btn : offTrack;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return lowContrast ? outline : Colors.transparent;
        }
        return outline;
      }),
    );
  }

  Color get appButtonColor => _accentButtonColor ?? _buttonColor ?? Colors.blueAccent;

  Color get onAppButtonColor => contrastColor(appButtonColor);

  ThemeData applyCustomColors(ThemeData base) {
    final Brightness brightness = base.brightness;

    ThemeData themed = base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: appBarBackground(brightness),
        foregroundColor: appBarForeground,
      ),
      switchTheme: buildSwitchTheme(brightness),
    );

    final activeBtnColor = _accentButtonColor ?? _buttonColor;
    if (activeBtnColor != null) {
      themed = themed.copyWith(
        primaryColor: activeBtnColor,
        colorScheme: themed.colorScheme.copyWith(
          primary: activeBtnColor,
          onPrimary: contrastColor(activeBtnColor),
        ),
      );
    }
    return themed;
  }

  SettingsProvider() {
    loadSettings();
  }

  bool _licenseAdded = false;
  void _initCustomLicenses() {
    if (_licenseAdded) return;
    _licenseAdded = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        [getText(_languageCode, 'app_title')],
        '${getText(_languageCode, 'license_summary')}\n\n${getText(_languageCode, 'license_legalese')}',
      );
    });
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final themeString = prefs.getString('theme_mode');
    if (themeString == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeString == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }

    _languageCode = prefs.getString('app_language') ?? prefs.getString('language_code') ?? 'de';
    _currencySymbol = prefs.getString('currency_symbol') ?? '€';
    _useAmPm = prefs.getBool('use_am_pm') ?? false;
    _sortOrder = prefs.getString('sort_order') ?? 'a_z';

    _useSwipeActions = prefs.getBool('use_swipe_actions') ?? false;
    _swipeRightAction = prefs.getString('swipe_right_action') ?? 'edit';
    _swipeLeftAction = prefs.getString('swipe_left_action') ?? 'delete';

    // --- KALENDER ---
    _autoAddToCalendar = prefs.getBool('auto_add_to_calendar') ?? false;
    _autoUpdateCalendar = prefs.getBool('auto_update_calendar') ?? false;
    _preferredCalendarApp = prefs.getString('preferred_calendar_app') ?? 'system';
    _defaultReminderMinutes = prefs.getInt('default_reminder_minutes') ?? 1440;

    // >>> NEU: Notification-Template laden
    _notifTemplate = [];
    try {
      final raw = prefs.getString('notif_template');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _notifTemplate = decoded
              .whereType<Map>()
              .map((m) => m.map(
                  (k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
              .toList();
        }
      }
    } catch (_) {
      _notifTemplate = [];
    }

    if (prefs.containsKey('design_primary_color')) _primaryColor = Color(prefs.getInt('design_primary_color')!);
    if (prefs.containsKey('design_tile_color')) _tileColor = Color(prefs.getInt('design_tile_color')!);
    if (prefs.containsKey('design_text_color')) _textColor = Color(prefs.getInt('design_text_color')!);
    if (prefs.containsKey('design_button_color')) _buttonColor = Color(prefs.getInt('design_button_color')!);
    if (prefs.containsKey('design_bg_color')) _backgroundColor = Color(prefs.getInt('design_bg_color')!);
    if (prefs.containsKey('design_shadow_color')) _shadowColor = Color(prefs.getInt('design_shadow_color')!);

    _fontSizeScale = prefs.getDouble('design_font_scale') ?? 1.0;
    _tileBorderRadius = prefs.getDouble('design_tile_radius') ?? 12.0;
    _buttonHeight = prefs.getDouble('design_button_height') ?? 48.0;
    _shadowBlur = prefs.getDouble('design_shadow_blur') ?? 4.0;
    _buttonAlignment = prefs.getString('design_button_align') ?? 'center';
    _fontFamily = prefs.getString('design_font_family') ?? 'default';

    if (prefs.containsKey('design_custom_palette')) {
      final List<dynamic> loaded = jsonDecode(prefs.getString('design_custom_palette')!);
      _customPalette = loaded.map((e) => Color(e as int)).toList();
    }

    if (prefs.containsKey('design_category_colors')) {
      final Map<String, dynamic> loadedMap = jsonDecode(prefs.getString('design_category_colors')!);
      _categoryColors = loadedMap.map((key, value) => MapEntry(key, Color(value as int)));
    }

    _customCategories = prefs.getStringList('design_custom_categories') ?? [];

    if (prefs.containsKey('design_screen_overrides')) {
      try {
        final Map<String, dynamic> loadedOverrides = jsonDecode(prefs.getString('design_screen_overrides')!);
        _screenColorOverrides = loadedOverrides.map((screenId, elementMap) {
          final Map<String, dynamic> inner = elementMap as Map<String, dynamic>;
          return MapEntry(screenId, inner.map((k, v) => MapEntry(k, v as int)));
        });
      } catch (_) {
        _screenColorOverrides = {};
      }
    }

    _accentColor = prefs.containsKey('accent_color') ? Color(prefs.getInt('accent_color')!) : null;
    _accentButtonColor = prefs.containsKey('accent_button_color')
        ? Color(prefs.getInt('accent_button_color')!)
        : (prefs.containsKey('button_color') ? Color(prefs.getInt('button_color')!) : null);

    _colorPickerUnlocked = prefs.getBool('accent_unlocked') ?? false;

    _savedAccentColors = [];
    if (prefs.containsKey('accent_saved_colors')) {
      try {
        final List<dynamic> loaded = jsonDecode(prefs.getString('accent_saved_colors')!);
        _savedAccentColors = loaded.map((e) => Color(e as int)).take(maxSavedColors).toList();
      } catch (_) {
        _savedAccentColors = [];
      }
    }

    final savedBtn = prefs.getStringList('saved_button_colors');
    if (savedBtn != null && savedBtn.isNotEmpty) {
      _savedButtonColors = savedBtn.map((c) => Color(int.parse(c))).toList();
    }

    _initCustomLicenses();
    notifyListeners();
  }

  // --- KALENDER SETTER ---
  Future<void> setAutoAddToCalendar(bool value) async {
    _autoAddToCalendar = value;
    if (!value) _autoUpdateCalendar = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_add_to_calendar', value);
    if (!value) await prefs.setBool('auto_update_calendar', false);
  }

  Future<void> setAutoUpdateCalendar(bool value) async {
    _autoUpdateCalendar = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_update_calendar', value);
  }

  Future<void> setPreferredCalendarApp(String app) async {
    _preferredCalendarApp = app;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_calendar_app', app);
  }

  Future<void> setDefaultReminderMinutes(int minutes) async {
    _defaultReminderMinutes = minutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_reminder_minutes', minutes);
  }

  // >>> NEU: Notification-Template Setter
  Future<void> setNotifTemplate(List<Map<String, String>> template) async {
    _notifTemplate = List.from(template);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (_notifTemplate.isEmpty) {
      await prefs.remove('notif_template');
    } else {
      await prefs.setString('notif_template', jsonEncode(_notifTemplate));
    }
  }

  // --- SETTER FÜR WISCHGESTEN ---
  Future<void> setUseSwipeActions(bool value) async {
    _useSwipeActions = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_swipe_actions', value);
  }

  Future<void> setSwipeRightAction(String action) async {
    _swipeRightAction = action;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('swipe_right_action', action);
  }

  Future<void> setSwipeLeftAction(String action) async {
    _swipeLeftAction = action;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('swipe_left_action', action);
  }

  // --- FARBVERWALTUNG & SETTER ---
  Future<void> setAccentColor(Color? color) async {
    _accentColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    color == null
        ? await prefs.remove('accent_color')
        : await prefs.setInt('accent_color', color.toARGB32());
  }

  Future<void> setAccentButtonColor(Color? color) async {
    _accentButtonColor = color;
    _buttonColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    color == null
        ? await prefs.remove('accent_button_color')
        : await prefs.setInt('accent_button_color', color.toARGB32());
  }

  Future<void> setButtonColor(Color color) async {
    await setAccentButtonColor(color);
  }

  bool isSavedColorInUse(Color color) {
    final v = color.toARGB32();
    return _accentColor?.toARGB32() == v || _accentButtonColor?.toARGB32() == v || _buttonColor?.toARGB32() == v;
  }

  Future<void> _persistSavedColors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'accent_saved_colors', jsonEncode(_savedAccentColors.map((c) => c.toARGB32()).toList()));
  }

  Future<bool> addSavedColor(Color color) async {
    if (_savedAccentColors.any((c) => c.toARGB32() == color.toARGB32())) return true;
    if (_savedAccentColors.length >= maxSavedColors) return false;
    _savedAccentColors.add(color);
    notifyListeners();
    await _persistSavedColors();
    return true;
  }

  Future<bool> removeSavedColor(int index) async {
    if (index < 0 || index >= _savedAccentColors.length) return false;
    if (isSavedColorInUse(_savedAccentColors[index])) return false;
    _savedAccentColors.removeAt(index);
    notifyListeners();
    await _persistSavedColors();
    return true;
  }

  Future<void> addAccentColor(Color color) async {
    await addSavedColor(color);
  }

  Future<void> removeAccentColor(Color color) async {
    final index = _savedAccentColors.indexWhere((c) => c.toARGB32() == color.toARGB32());
    if (index != -1) {
      await removeSavedColor(index);
    }
  }

  Future<void> addButtonColor(Color color) async {
    if (!_savedButtonColors.any((c) => c.toARGB32() == color.toARGB32())) {
      if (_savedButtonColors.length >= maxSavedColors) {
        _savedButtonColors.removeAt(0);
      }
      _savedButtonColors.add(color);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_button_colors',
          _savedButtonColors.map((c) => c.toARGB32().toString()).toList());
    }
  }

  Future<void> removeButtonColor(Color color) async {
    if (_savedButtonColors.length > 1) {
      _savedButtonColors.removeWhere((c) => c.toARGB32() == color.toARGB32());
      if (_buttonColor?.toARGB32() == color.toARGB32() || _accentButtonColor?.toARGB32() == color.toARGB32()) {
        _accentButtonColor = _savedButtonColors.first;
        _buttonColor = _savedButtonColors.first;
        await setAccentButtonColor(_accentButtonColor);
      }
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_button_colors',
          _savedButtonColors.map((c) => c.toARGB32().toString()).toList());
    }
  }

  Future<void> unlockColorPicker() async {
    if (_colorPickerUnlocked) return;
    _colorPickerUnlocked = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('accent_unlocked', true);
  }

  Future<void> setPrimaryColor(Color? color) async {
    _primaryColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    color == null ? prefs.remove('design_primary_color') : prefs.setInt('design_primary_color', color.toARGB32());
  }

  Future<void> setTileColor(Color? color) async {
    _tileColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    color == null ? prefs.remove('design_tile_color') : prefs.setInt('design_tile_color', color.toARGB32());
  }

  Future<void> setTextColor(Color? color) async {
    _textColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    color == null ? prefs.remove('design_text_color') : prefs.setInt('design_text_color', color.toARGB32());
  }

  Future<void> setBackgroundColor(Color? color) async {
    _backgroundColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    color == null ? prefs.remove('design_bg_color') : prefs.setInt('design_bg_color', color.toARGB32());
  }

  Future<void> setShadowColor(Color? color) async {
    _shadowColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    color == null ? prefs.remove('design_shadow_color') : prefs.setInt('design_shadow_color', color.toARGB32());
  }

  Future<void> addCustomColor(Color color) async {
    if (_customPalette.length < 10) {
      _customPalette.add(color);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('design_custom_palette', jsonEncode(_customPalette.map((c) => c.toARGB32()).toList()));
    }
  }

  Future<void> removeCustomColor(int index) async {
    if (index >= 0 && index < _customPalette.length) {
      _customPalette.removeAt(index);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('design_custom_palette', jsonEncode(_customPalette.map((c) => c.toARGB32()).toList()));
    }
  }

  Future<void> setCategoryColor(String categoryKey, Color? color) async {
    if (color == null) {
      _categoryColors.remove(categoryKey);
    } else {
      _categoryColors[categoryKey] = color;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('design_category_colors', jsonEncode(_categoryColors.map((k, v) => MapEntry(k, v.toARGB32()))));
  }

  Color? getCategoryColor(String categoryKey) {
    return _categoryColors[categoryKey];
  }

  Future<void> addCustomCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || _customCategories.contains(trimmed)) return;
    _customCategories.add(trimmed);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('design_custom_categories', _customCategories);
  }

  Future<void> removeCustomCategory(String name) async {
    _customCategories.remove(name);
    _categoryColors.remove(name);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('design_custom_categories', _customCategories);
    prefs.setString('design_category_colors', jsonEncode(_categoryColors.map((k, v) => MapEntry(k, v.toARGB32()))));
  }

  Future<void> setScreenColor(String screenId, String elementKey, Color? color) async {
    final screenMap = _screenColorOverrides.putIfAbsent(screenId, () => {});
    if (color == null) {
      screenMap.remove(elementKey);
      if (screenMap.isEmpty) _screenColorOverrides.remove(screenId);
    } else {
      screenMap[elementKey] = color.toARGB32();
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('design_screen_overrides', jsonEncode(_screenColorOverrides));
  }

  Color? getScreenColor(String screenId, String elementKey) {
    final value = _screenColorOverrides[screenId]?[elementKey];
    return value != null ? Color(value) : null;
  }

  Future<void> resetScreenDesign(String screenId) async {
    _screenColorOverrides.remove(screenId);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('design_screen_overrides', jsonEncode(_screenColorOverrides));
  }

  Future<bool> categoryHasEntries(String categoryName) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('gerate_liste');
    if (raw == null || raw.isEmpty) return false;
    try {
      final List<dynamic> liste = jsonDecode(raw);
      return liste.any((item) => (item as Map)['kategorie'] == categoryName);
    } catch (_) {
      return false;
    }
  }

  Future<bool> tryRemoveCustomCategory(String name) async {
    if (await categoryHasEntries(name)) return false;
    await removeCustomCategory(name);
    return true;
  }

  Future<void> setFontSizeScale(double scale) async {
    _fontSizeScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('design_font_scale', scale);
  }

  Future<void> setTileBorderRadius(double radius) async {
    _tileBorderRadius = radius;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('design_tile_radius', radius);
  }

  Future<void> setButtonHeight(double height) async {
    _buttonHeight = height;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('design_button_height', height);
  }

  Future<void> setShadowBlur(double blur) async {
    _shadowBlur = blur;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('design_shadow_blur', blur);
  }

  Future<void> setButtonAlignment(String alignment) async {
    _buttonAlignment = alignment;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('design_button_align', alignment);
  }

  Future<void> setFontFamily(String family) async {
    _fontFamily = family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('design_font_family', family);
  }

  Future<void> resetThemeToDefault() async {
    _primaryColor = null;
    _tileColor = null;
    _textColor = null;
    _buttonColor = null;
    _backgroundColor = null;
    _shadowColor = null;
    _fontSizeScale = 1.0;
    _tileBorderRadius = 12.0;
    _buttonHeight = 48.0;
    _shadowBlur = 4.0;
    _buttonAlignment = 'center';
    _fontFamily = 'default';
    _categoryColors.clear();
    _screenColorOverrides.clear();

    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    prefs.remove('design_screen_overrides');
    prefs.remove('design_primary_color');
    prefs.remove('design_tile_color');
    prefs.remove('design_text_color');
    prefs.remove('design_button_color');
    prefs.remove('design_bg_color');
    prefs.remove('design_shadow_color');
    prefs.remove('design_font_scale');
    prefs.remove('design_tile_radius');
    prefs.remove('design_button_height');
    prefs.remove('design_shadow_blur');
    prefs.remove('design_button_align');
    prefs.remove('design_font_family');
    prefs.remove('design_category_colors');
  }

  Color getEffectiveBgColor(BuildContext context, {String? screenId}) {
    if (screenId != null) {
      final override = getScreenColor(screenId, 'bg');
      if (override != null) return override;
    }
    if (_backgroundColor != null) return _backgroundColor!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFF121212) : const Color(0xFFF4F6F9);
  }

  Color getEffectiveAppBarColor(BuildContext context, {String? screenId}) {
    if (screenId != null) {
      final override = getScreenColor(screenId, 'primary');
      if (override != null) return override;
    }
    if (_primaryColor != null) return _primaryColor!;
    return getEffectiveBgColor(context, screenId: screenId);
  }

  Color getEffectiveButtonColor(BuildContext context, {String? screenId}) {
    if (screenId != null) {
      final override = getScreenColor(screenId, 'button');
      if (override != null) return override;
    }
    if (_buttonColor != null) return _buttonColor!;
    if (screenId != null) {
      final primaryOverride = getScreenColor(screenId, 'primary');
      if (primaryOverride != null) return primaryOverride;
    }
    return _primaryColor ?? Colors.blueAccent;
  }

  TextStyle getTextStyle(BuildContext context, {double baseSize = 14, FontWeight fontWeight = FontWeight.normal, Color? color, String? screenId}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color? screenOverride = screenId != null ? getScreenColor(screenId, 'text') : null;
    Color finalColor = color ?? screenOverride ?? _textColor ?? (isDark ? Colors.white : Colors.black87);

    return TextStyle(
      fontSize: baseSize * _fontSizeScale,
      fontWeight: fontWeight,
      color: finalColor,
      fontFamily: _fontFamily == 'default' ? null : _fontFamily,
    );
  }

  BoxDecoration getTileDecoration(BuildContext context, {Color? customTileColor, String? screenId}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultTile = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final screenTileOverride = screenId != null ? getScreenColor(screenId, 'tile') : null;
    final screenShadowOverride = screenId != null ? getScreenColor(screenId, 'shadow') : null;

    return BoxDecoration(
      color: customTileColor ?? screenTileOverride ?? _tileColor ?? defaultTile,
      borderRadius: BorderRadius.circular(_tileBorderRadius),
      boxShadow: [
        if (!isDark) BoxShadow(color: (screenShadowOverride ?? _shadowColor ?? Colors.black).withValues(alpha: 0.05), blurRadius: _shadowBlur, offset: const Offset(0, 2)),
      ],
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    String modeString = 'system';
    if (mode == ThemeMode.light) modeString = 'light';
    if (mode == ThemeMode.dark) modeString = 'dark';
    await prefs.setString('theme_mode', modeString);
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    _initCustomLicenses();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', code);
    await prefs.setString('language_code', code);
  }

  Future<void> setCurrency(String symbol) async {
    _currencySymbol = symbol;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency_symbol', symbol);
  }

  Future<void> setUseAmPm(bool value) async {
    _useAmPm = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_am_pm', value);
  }

  Future<void> setSortOrder(String order) async {
    _sortOrder = order;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sort_order', order);
  }

  Future<void> deleteAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final bool wasUnlocked = _colorPickerUnlocked;
    await prefs.clear();
    if (wasUnlocked) await prefs.setBool('accent_unlocked', true);
    _accentColor = null;
    _accentButtonColor = null;
    _buttonColor = null;
    _savedAccentColors = [];
    _savedButtonColors = [
      Colors.blueAccent,
      Colors.teal,
      Colors.deepPurple,
      Colors.orange,
      Colors.redAccent
    ];
    _themeMode = ThemeMode.system;
    _languageCode = 'de';
    _currencySymbol = '€';
    _useAmPm = false;
    _sortOrder = 'a_z';
    _useSwipeActions = false;
    _swipeRightAction = 'edit';
    _swipeLeftAction = 'delete';
    _autoAddToCalendar = false;
    _autoUpdateCalendar = false;
    _preferredCalendarApp = 'system';
    _defaultReminderMinutes = 1440;
    _notifTemplate = []; // >>> NEU
    await resetThemeToDefault();
    _customPalette.clear();
    _customCategories.clear();
    _initCustomLicenses();
    notifyListeners();
  }

  void showTranslatedLicensePage(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: getText(_languageCode, 'app_title'),
      applicationVersion: '1.0.0',
      applicationLegalese: getText(_languageCode, 'license_legalese'),
    );
  }
}

const Map<String, Map<String, String>> translations = {
  'de': translationsDe,
  'en': translationsEn,
  'fr': translationsFr,
  'es': translationsEs,
};

String getText(String lang, String key) {
  return translations[lang]?[key] ?? translations['de']?[key] ?? key;
}

String localizeDuration(String? durationStr, String langCode) {
  if (durationStr == null || durationStr.isEmpty) return '-';
  if (durationStr == 'Unbekannt') return getText(langCode, 'unknown');

  return durationStr
      .replaceAll('Jahre', getText(langCode, 'jahre'))
      .replaceAll('Jahr', getText(langCode, 'jahr'))
      .replaceAll('Monate', getText(langCode, 'monate'))
      .replaceAll('Wochen', getText(langCode, 'wochen'));
}

String localizeTimeOfDay(int hour, int minute, String langCode, bool useAmPm) {
  final min = minute.toString().padLeft(2, '0');
  if (useAmPm) {
    int h = hour;
    final String period = h >= 12 ? getText(langCode, 'time_pm') : getText(langCode, 'time_am');
    if (h == 0) {
      h = 12;
    } else if (h > 12) {
      h -= 12;
    }
    return '${h.toString().padLeft(2, '0')}:$min $period';
  }
  return '${hour.toString().padLeft(2, '0')}:$min${getText(langCode, 'clock')}';
}

String localizeReminderDate(DateTime dt, String langCode, bool useAmPm) {
  final t = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final j = dt.year.toString();

  final timeString = localizeTimeOfDay(dt.hour, dt.minute, langCode, useAmPm);

return '${getText(langCode, 'on_date')}$t.$m.$j${getText(langCode, 'at_time')}$timeString';
}