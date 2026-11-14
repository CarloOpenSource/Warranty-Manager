import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../Services/settings_provider.dart';
import 'package:garantiemanager/Manual/tutorial.dart';
import 'package:garantiemanager/Screens/edit_screen.dart';

class DetailScreen extends StatefulWidget {
  final Map<String, String> gerat;
  final VoidCallback? onEdit;
  final bool isFromTutorial;

  const DetailScreen({
    super.key,
    required this.gerat,
    this.onEdit,
    this.isFromTutorial = false,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final GlobalKey _infoKey = GlobalKey();
  final GlobalKey _downloadKey = GlobalKey();
  final GlobalKey _printKey = GlobalKey();
  final GlobalKey _backKey = GlobalKey();

  // Version-Counter für Bilder, um Cache zu umgehen nach Bearbeitung
  final Map<String, int> _imageVersions = {};

  void _incrementImageVersion(String path) {
    setState(() {
      _imageVersions[path] = (_imageVersions[path] ?? 0) + 1;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.gerat['isDemo'] == 'true' || widget.isFromTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        TutorialHelper.zeigeDetailTutorial(
          context: context,
          downloadKey: _downloadKey,
          printKey: _printKey,
          infoKey: _infoKey,
          backKey: _backKey,
        );
      });
    }
  }

  void _zeigeBildVollbild(BuildContext context, String bildPfad) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) {
          final bool istDunkel = Theme.of(ctx).brightness == Brightness.dark;
          final Color kreisFarbe = istDunkel ? Colors.black : Colors.white;
          final Color kreuzFarbe = istDunkel ? Colors.white : Colors.black;

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: istDunkel ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: Scaffold(
              backgroundColor: istDunkel ? Colors.black : Colors.white,
              body: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: bildPfad.startsWith('http')
                          ? Image.network(bildPfad, fit: BoxFit.contain, key: ValueKey('${bildPfad}_${_imageVersions[bildPfad] ?? 0}'))
                          : Image.file(File(bildPfad), fit: BoxFit.contain, key: ValueKey('${bildPfad}_${_imageVersions[bildPfad] ?? 0}')),
                    ),
                  ),
                  // --- Ganz links: Schließen-Button ---
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Material(
                          color: kreisFarbe,
                          elevation: 3,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.close, size: 28, color: kreuzFarbe),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // --- Ganz rechts: Bearbeiten-Button (Stift) ---
                  Positioned(
                    top: 0,
                    right: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Material(
                          color: kreisFarbe,
                          elevation: 3,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () async {
                              if (!bildPfad.startsWith('http')) {
                                final file = File(bildPfad);
                                if (!file.existsSync()) {
                                  debugPrint('Datei existiert nicht: $bildPfad');
                                  return;
                                }
                                debugPrint('Öffne EditScreen für: $bildPfad');
                                final result = await Navigator.of(ctx).push(
                                  MaterialPageRoute(
                                    builder: (ctx2) => EditScreen(
                                      imageDataPath: bildPfad,
                                      originalPath: bildPfad,
                                    ),
                                  ),
                                );
                                if (result != null && mounted) {
                                  // Version erhöhen für Cache-Busting
                                  _incrementImageVersion(bildPfad);
                                }
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(Icons.edit, size: 24, color: kreuzFarbe),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<pw.Document> _erstellePdf(List<String> pfade, String wWaehrung, String lang, bool useAmPm) async {
    final fontRegular = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    List<pw.ImageProvider> pdfBilder = [];
    for (String pfad in pfade) {
      try {
        if (pfad.trim().isEmpty) continue;

        if (pfad.startsWith('http')) {
          final netImage = await networkImage(pfad);
          pdfBilder.add(netImage);
        } else if (File(pfad).existsSync()) {
          final bytes = await File(pfad).readAsBytes();
          pdfBilder.add(pw.MemoryImage(bytes));
        }
      } catch (e) {
        //
      }
    }

    final String bemerkungText = (widget.gerat['bemerkung'] != null && widget.gerat['bemerkung']!.trim().isNotEmpty)
        ? widget.gerat['bemerkung']!
        : '-';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    widget.gerat['name'] ?? getText(lang, 'unknown'),
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                  ),
                  pw.Text(getText(lang, 'app_title'), style: const pw.TextStyle(color: PdfColors.grey600)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildPdfRow('${getText(lang, 'product_name')}:', widget.gerat['name'] ?? '-'),
                  _buildPdfRow('${getText(lang, 'category')}:', getText(lang, widget.gerat['kategorie'] ?? 'others')),
                  _buildPdfRow('${getText(lang, 'buy_date')}:', widget.gerat['kaufDatum'] ?? '-'),
                  _buildPdfRow('${getText(lang, 'bought_at')}:', widget.gerat['woGekauft'] == 'Unbekannt' ? getText(lang, 'unknown') : (widget.gerat['woGekauft'] ?? '-')),
                  _buildPdfRow('${getText(lang, 'price')}:', widget.gerat['preis'] == 'Unbekannt' ? getText(lang, 'unknown') : '${widget.gerat['preis']} $wWaehrung'),
                  _buildPdfRow('${getText(lang, 'warranty_duration')}:', localizeDuration(widget.gerat['garantieDauer'], lang)),
                  _buildPdfRow('${getText(lang, 'expiry_date')}:', widget.gerat['ablaufDatum'] ?? '-'),
                  _buildPdfRow('${getText(lang, 'reminder')}:', _getErinnerungsText(lang, useAmPm)),
                  _buildPdfRow('${getText(lang, 'remarks')}:', bemerkungText),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            if (pdfBilder.isNotEmpty) ...[
              pw.Text('${getText(lang, 'photos')}:', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Wrap(
                spacing: 16,
                runSpacing: 16,
                children: pdfBilder.map((img) => pw.Container(
                  width: 220,
                  height: 300,
                  child: pw.Image(img, fit: pw.BoxFit.contain)
                )).toList(),
              ),
            ],
          ];
        },
      ),
    );
    return pdf;
  }

  Future<void> _druckenDetails(BuildContext context, List<String> pfade, String wWaehrung, String lang, bool useAmPm) async {
    final pdf = await _erstellePdf(pfade, wWaehrung, lang, useAmPm);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Garantie_${widget.gerat['name'] ?? 'Gerat'}.pdf',
    );
  }

  Future<void> _downloadPdf(BuildContext context, List<String> pfade, String wWaehrung, String lang, bool useAmPm) async {
    final pdf = await _erstellePdf(pfade, wWaehrung, lang, useAmPm);
    final pdfBytes = await pdf.save();
    await Printing.sharePdf(bytes: pdfBytes, filename: 'Garantie_${widget.gerat['name'] ?? 'Gerat'}.pdf');
  }

  pw.Widget _buildPdfRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 140, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  String _getErinnerungsText(String lang, bool useAmPm) {
    final rawData = widget.gerat['erinnerung'];
    if (rawData == null || rawData == 'Nie') return getText(lang, 'never');

    DateTime? datum;
    try {
      final decoded = jsonDecode(rawData);
      if (decoded['ausloeseZeit'] != null) {
        datum = DateTime.parse(decoded['ausloeseZeit']);
      }
    } catch (e) {
      try {
        datum = DateTime.parse(rawData);
      } catch (_) {
        return rawData;
      }
    }

    if (datum != null) {
      final tag = datum.day.toString().padLeft(2, '0');
      final monat = datum.month.toString().padLeft(2, '0');
      final jahr = datum.year.toString();
      final minute = datum.minute.toString().padLeft(2, '0');

      if (useAmPm) {
        int hour12 = datum.hour % 12;
        if (hour12 == 0) hour12 = 12;
        final amPm = datum.hour >= 12 ? 'PM' : 'AM';
        final stunde = hour12.toString().padLeft(2, '0');
        return '$tag.$monat.$jahr, $stunde:$minute $amPm';
      } else {
        final stunde = datum.hour.toString().padLeft(2, '0');
        return '$tag.$monat.$jahr, $stunde:$minute';
      }
    }

    return getText(lang, 'unknown');
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final lang = settings.languageCode;
    final useAmPm = settings.useAmPm;

    final currency = widget.gerat['waehrung'] ?? settings.currencySymbol;

    final String? bildPfadeText = widget.gerat['bildPfade'];
    final List<String> pfade = (bildPfadeText != null && bildPfadeText.isNotEmpty) ? bildPfadeText.split(',') : [];

    String preisAnzeige = widget.gerat['preis'] ?? getText(lang, 'unknown');
    if (preisAnzeige != getText(lang, 'unknown') && preisAnzeige != 'Unbekannt') {
      preisAnzeige = '$preisAnzeige $currency';
    } else {
      preisAnzeige = getText(lang, 'unknown');
    }

    String woGekauftAnzeige = widget.gerat['woGekauft'] == 'Unbekannt' ? getText(lang, 'unknown') : (widget.gerat['woGekauft'] ?? '-');
    String bemerkungAnzeige = (widget.gerat['bemerkung'] != null && widget.gerat['bemerkung']!.trim().isNotEmpty) ? widget.gerat['bemerkung']! : '-';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarColor = settings.hasCustomAccent
        ? settings.accentColor!
        : (settings.primaryColor ?? (isDark ? const Color(0xFF1E1E1E) : Colors.blueAccent));
    final appBarFg = settings.hasCustomAccent ? settings.appBarForeground : Colors.white;

    return PopScope(
      canPop: !TutorialHelper.isTutorialActive || TutorialHelper.forcePopFlag,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        backgroundColor: settings.getEffectiveBgColor(context),
        appBar: AppBar(
          backgroundColor: appBarColor,
          iconTheme: IconThemeData(color: appBarFg),
          actionsIconTheme: IconThemeData(color: appBarFg),
          leading: IconButton(
            key: _backKey,
            icon: Icon(Icons.arrow_back, color: appBarFg),
            onPressed: () {
              if (TutorialHelper.isTutorialActive) return;
              Navigator.pop(context);
            },
          ),
          title: Text(
            getText(lang, 'details'),
          ),
          actions: [
            if (widget.onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onEdit?.call();
                },
              ),
            IconButton(
              key: _downloadKey,
              icon: const Icon(Icons.download),
              onPressed: () => _downloadPdf(context, pfade, currency, lang, useAmPm),
            ),
            IconButton(
              key: _printKey,
              icon: const Icon(Icons.print),
              onPressed: () => _druckenDetails(context, pfade, currency, lang, useAmPm),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: AbsorbPointer(
                absorbing: TutorialHelper.isTutorialActive,
                child: SingleChildScrollView(
                  physics: TutorialHelper.isTutorialActive ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        key: _infoKey,
                        child: Column(
                          children: [
                            _buildDetailKachel(
                              context,
                              settings,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.devices, color: settings.primaryColor ?? settings.appButtonColor, size: 28),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          widget.gerat['name'] ?? getText(lang, 'unknown'),
                                          style: settings.getTextStyle(context, baseSize: 20, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  _buildInfoRow(context, settings, icon: Icons.category, label: getText(lang, 'category'), value: getText(lang, widget.gerat['kategorie'] ?? 'others')),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailKachel(
                              context,
                              settings,
                              child: Column(
                                children: [
                                  _buildInfoRow(context, settings, icon: Icons.calendar_today, label: getText(lang, 'buy_date'), value: widget.gerat['kaufDatum'] ?? '-'),
                                  const SizedBox(height: 10),
                                  _buildInfoRow(context, settings, icon: Icons.store, label: getText(lang, 'bought_at'), value: woGekauftAnzeige),
                                  const SizedBox(height: 10),
                                  _buildInfoRow(context, settings, icon: Icons.payments, label: getText(lang, 'price'), value: preisAnzeige),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailKachel(
                              context,
                              settings,
                              child: Column(
                                children: [
                                  _buildInfoRow(context, settings, icon: Icons.timer, label: getText(lang, 'duration'), value: localizeDuration(widget.gerat['garantieDauer'], lang)),
                                  const SizedBox(height: 10),
                                  _buildInfoRow(context, settings, icon: Icons.event_available, label: getText(lang, 'expiry'), value: widget.gerat['ablaufDatum'] ?? '-', valueColor: Colors.redAccent),
                                  const SizedBox(height: 10),
                                  _buildInfoRow(context, settings, icon: Icons.notifications_active, label: getText(lang, 'reminder'), value: _getErinnerungsText(lang, useAmPm)),
                                  const SizedBox(height: 10),
                                  _buildInfoRow(context, settings, icon: Icons.notes, label: getText(lang, 'remarks'), value: bemerkungAnzeige),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailKachel(
                              context,
                              settings,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(getText(lang, 'photos'), style: settings.getTextStyle(context, baseSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  pfade.isEmpty
                                      ? Text(getText(lang, 'no_devices'), style: settings.getTextStyle(context, color: Colors.grey))
                                      : GridView.builder(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                            maxCrossAxisExtent: 150,
                                            crossAxisSpacing: 8,
                                            mainAxisSpacing: 8,
                                          ),
                                          itemCount: pfade.length,
                                          itemBuilder: (context, index) {
                                            final pfad = pfade[index];
                                            return GestureDetector(
                                              onTap: () => _zeigeBildVollbild(context, pfad),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: pfad.startsWith('http')
                                                    ? Image.network(pfad, fit: BoxFit.cover, key: ValueKey('${pfad}_${_imageVersions[pfad] ?? 0}'))
                                                    : Image.file(File(pfad), fit: BoxFit.cover, key: ValueKey('${pfad}_${_imageVersions[pfad] ?? 0}')),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailKachel(BuildContext context, SettingsProvider settings, {Key? key, required Widget child}) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: settings.getTileDecoration(context),
      child: child,
    );
  }

  Widget _buildInfoRow(BuildContext context, SettingsProvider settings, {required IconData icon, required String label, required String value, Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 10),
        Text('$label: ', style: settings.getTextStyle(context, fontWeight: FontWeight.bold, baseSize: 15)),
        Expanded(
          child: Text(
            value,
            softWrap: true,
            style: settings.getTextStyle(
              context,
              baseSize: 15,
              color: valueColor,
              fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}