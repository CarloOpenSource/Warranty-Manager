import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../Services/notification_service.dart';
import '../Services/settings_provider.dart';
import 'calendar_settings_dialog.dart';
import 'package:garantiemanager/Manual/tutorial.dart';
import 'detail_screen.dart';
import '../Services/calender_service.dart';   
import 'dart:convert';

class ExpiryScreen extends StatefulWidget {
  final List<Map<String, String>> gerateListe;
  final bool isFromTutorial;

  const ExpiryScreen({
    super.key,
    required this.gerateListe,
    this.isFromTutorial = false,
  });

  @override
  State<ExpiryScreen> createState() => _ExpiryScreenState();
}

// NEU: SingleTickerProviderStateMixin, damit der TabController
// programmatisch (aus dem Tutorial) gesteuert werden kann.
class _ExpiryScreenState extends State<ExpiryScreen>
    with SingleTickerProviderStateMixin {
  late List<Map<String, String>> _alleGerate;
  late List<Map<String, String>> _nichtAbgelaufenListe;
  late List<Map<String, String>> _abgelaufeneListe;

  late TabController _tabController;

  // Globale Keys für das Tutorial
  final GlobalKey _activeTabKey = GlobalKey();
  final GlobalKey _expiredTabKey = GlobalKey();
  final GlobalKey _backKey = GlobalKey();
  final GlobalKey _eintragKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _alleGerate = List.from(widget.gerateListe);
    _sortierUndTrennListen();

    if (widget.isFromTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TutorialHelper.zeigeExpiryTutorial(
          context: context,
          tabController: _tabController,
          activeTabKey: _activeTabKey,
          expiredTabKey: _expiredTabKey,
          eintragKey: _eintragKey,
          backKey: _backKey,
        );
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime _getSortDate(Map<String, String> gerat) {
    final erinnerung = gerat['erinnerung'];

    if (erinnerung != null && erinnerung != 'Nie' && erinnerung.isNotEmpty) {
      try {
        final decoded = jsonDecode(erinnerung);
        if (decoded is Map && decoded['ausloeseZeit'] != null) {
          return DateTime.parse(decoded['ausloeseZeit']);
        }
      } catch (_) {
        try {
          return DateTime.parse(erinnerung);
        } catch (_) {}
      }
    }

    final ablauf = _parseDatum(gerat['ablaufDatum']);
    if (ablauf != null) {
      return DateTime(ablauf.year, ablauf.month, ablauf.day, 23, 59, 59);
    }

    return DateTime(2999, 12, 31);
  }

  void _sortierUndTrennListen() {
    final jetzt = DateTime.now();
    final today = DateTime(jetzt.year, jetzt.month, jetzt.day);

    final aktiv = <Map<String, String>>[];
    final abgelaufen = <Map<String, String>>[];

    for (var gerat in _alleGerate) {
      final ablaufDate = _parseDatum(gerat['ablaufDatum']);
      if (ablaufDate != null) {
        if (ablaufDate.isBefore(today)) {
          abgelaufen.add(gerat);
        } else {
          aktiv.add(gerat);
        }
      }
    }

    aktiv.sort((a, b) => _getSortDate(a).compareTo(_getSortDate(b)));
    abgelaufen.sort((a, b) => _getSortDate(b).compareTo(_getSortDate(a)));

    _nichtAbgelaufenListe = aktiv;
    _abgelaufeneListe = abgelaufen;
  }

  DateTime? _parseDatum(String? datumStr) {
    if (datumStr == null || datumStr.isEmpty) return null;
    try {
      final teile = datumStr.split('.');
      if (teile.length == 3) {
        return DateTime(
          int.parse(teile[2]),
          int.parse(teile[1]),
          int.parse(teile[0]),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> _geratLoeschen(Map<String, String> gerat, String lang) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(getText(lang, 'delete_device_title')),
        content: Text(getText(lang, 'delete_device_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(getText(lang, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(getText(lang, 'delete')),
          ),
        ],
      ),
    );

    if (bestaetigt == true) {
      if (gerat['notificationId'] != null) {
        final int? id = int.tryParse(gerat['notificationId']!);
        if (id != null) {
          await NotificationService().cancelNotification(id);
        }
      }

      try {
        final calendarEventId = gerat['calendarEventId'];
        if (calendarEventId != null &&
            calendarEventId.isNotEmpty &&
            settings.preferredCalendarApp != 'ics') {
          await CalendarService().deleteEvent(
            eventId: calendarEventId,
            providerId: settings.preferredCalendarApp,
          );
        }
      } catch (_) {
        // ignorieren
      }

      if (!mounted) return;

      setState(() {
        _alleGerate.remove(gerat);
        _sortierUndTrennListen();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${gerat['name']}${getText(lang, 'deleted_success')}')),
      );
    }
  }

  String _getFuzzyDuration(int days, String lang) {
    if (days == 0) return getText(lang, 'today');

    if (days >= 365) {
      double value = days / 365.0;
      int floorVal = value.floor();
      double remainder = value - floorVal;

      String unitSingular = getText(lang, 'year_singular');
      String unitPlural = getText(lang, 'years_plural');

      if (remainder < 0.1) {
        return '$floorVal ${floorVal == 1 ? unitSingular : unitPlural}';
      } else if (remainder <= 0.5) {
        return '> $floorVal ${floorVal == 1 ? unitSingular : unitPlural}';
      } else {
        int ceilVal = floorVal + 1;
        return '< $ceilVal ${ceilVal == 1 ? unitSingular : unitPlural}';
      }
    } else if (days >= 30) {
      double value = days / 30.0;
      int floorVal = value.floor();
      double remainder = value - floorVal;

      String unitSingular = getText(lang, 'month_singular');
      String unitPlural = getText(lang, 'months_plural');

      if (remainder < 0.1) {
        return '$floorVal ${floorVal == 1 ? unitSingular : unitPlural}';
      } else if (remainder <= 0.5) {
        return '> $floorVal ${floorVal == 1 ? unitSingular : unitPlural}';
      } else {
        int ceilVal = floorVal + 1;
        return '< $ceilVal ${ceilVal == 1 ? unitSingular : unitPlural}';
      }
    } else if (days >= 7) {
      double value = days / 7.0;
      int floorVal = value.floor();
      double remainder = value - floorVal;

      String unitSingular = getText(lang, 'week_singular');
      String unitPlural = getText(lang, 'weeks_plural');

      if (remainder < 0.1) {
        return '$floorVal ${floorVal == 1 ? unitSingular : unitPlural}';
      } else if (remainder <= 0.5) {
        return '> $floorVal ${floorVal == 1 ? unitSingular : unitPlural}';
      } else {
        int ceilVal = floorVal + 1;
        return '< $ceilVal ${ceilVal == 1 ? unitSingular : unitPlural}';
      }
    } else {
      String unit = days == 1 ? getText(lang, 'day_singular') : getText(lang, 'days_plural');
      return '$days $unit';
    }
  }

  Widget _buildListe(List<Map<String, String>> liste, String lang, {required bool isAbgelaufen}) {
    if (liste.isEmpty) {
      return Center(
        child: Text(
          getText(lang, 'no_reminders'),
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 96.0),
      itemCount: liste.length,
      itemBuilder: (context, index) {
        final gerat = liste[index];
        final ablaufDate = _parseDatum(gerat['ablaufDatum']);
        final jetzt = DateTime.now();

        Color statusFarbe = Colors.green;
        String statusText = '';

        if (ablaufDate != null) {
          final verbleibendeTage = ablaufDate.difference(jetzt).inDays;

          if (isAbgelaufen) {
            statusFarbe = Colors.red;
            final tagePositiv = verbleibendeTage.abs();

            if (tagePositiv == 0) {
              statusText = getText(lang, 'expired_today');
            } else {
              final fuzzyText = _getFuzzyDuration(tagePositiv, lang);
              statusText = '${getText(lang, 'expired_since')}$fuzzyText${getText(lang, 'expired_suffix')}';
            }
          } else {
            if (verbleibendeTage <= 30) {
              statusFarbe = Colors.redAccent;
            } else if (verbleibendeTage <= 90) {
              statusFarbe = Colors.orangeAccent;
            } else {
              statusFarbe = Colors.green;
            }

            if (verbleibendeTage == 0) {
              statusText = getText(lang, 'expires_today');
            } else {
              final fuzzyText = _getFuzzyDuration(verbleibendeTage, lang);
              statusText = '${getText(lang, 'days_left')}$fuzzyText';
            }
          }
        }

        return Card(
          // WICHTIGER FIX:
          // Der `_eintragKey` darf NUR auf der aktiven Liste liegen.
          // Vorher bekam auch die abgelaufene Liste den gleichen Key –
          // nach einem Tab-Wechsel waren beide Karten gleichzeitig im Tree
          // → GlobalKey-Kollision → Tutorial verlor die Ziel-Position und
          // blieb hängen.
          key: (index == 0 && widget.isFromTutorial && !isAbgelaufen)
              ? _eintragKey
              : null,
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: statusFarbe.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          color: Theme.of(context).cardColor,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DetailScreen(gerat: gerat),
                ),
              );
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: statusFarbe.withValues(alpha: 0.15),
                child: Icon(
                  isAbgelaufen || (statusFarbe == Colors.redAccent)
                      ? Icons.warning_amber_rounded
                      : Icons.calendar_month,
                  color: statusFarbe,
                ),
              ),
              title: Text(
                gerat['name'] ?? getText(lang, 'unknown'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('${getText(lang, 'expiry_date')}: ${gerat['ablaufDatum']}'),
                  Text(
                    statusText,
                    style: TextStyle(color: statusFarbe, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _geratLoeschen(gerat, lang),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final lang = settings.languageCode;

    // KEIN DefaultTabController mehr – wir nutzen den expliziten
    // _tabController, damit das Tutorial die Tabs umschalten kann.
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _alleGerate);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(getText(lang, 'expiry_title')),
          leading: IconButton(
            key: _backKey,
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context, _alleGerate);
            },
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: settings.hasCustomAccent ? settings.appBarForeground : settings.appButtonColor,
            labelColor: settings.hasCustomAccent ? settings.appBarForeground : null,
            unselectedLabelColor:
                settings.hasCustomAccent ? settings.appBarForeground.withValues(alpha: 0.7) : null,
            tabs: [
              Tab(
                key: _activeTabKey,
                icon: const Icon(Icons.check_circle_outline),
                text: getText(lang, 'active'),
              ),
              Tab(
                key: _expiredTabKey,
                icon: const Icon(Icons.history),
                text: getText(lang, 'expired_cat'),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: AbsorbPointer(
            absorbing: TutorialHelper.isTutorialActive,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListe(_nichtAbgelaufenListe, lang, isAbgelaufen: false),
                _buildListe(_abgelaufeneListe, lang, isAbgelaufen: true),
              ],
            ),
          ),
        ),
        floatingActionButton: SafeArea(
          top: false,
          child: FloatingActionButton(
            backgroundColor: settings.appButtonColor,
            foregroundColor: settings.onAppButtonColor,
            tooltip: getText(lang, 'calendar_settings'),
            onPressed: widget.isFromTutorial
                ? () {}
                : () => showCalendarSettingsDialog(context),
            child: const Icon(Icons.calendar_month),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
}