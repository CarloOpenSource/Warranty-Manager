import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:garantiemanager/Screens/add_screen.dart';
import 'package:provider/provider.dart'; 
import 'package:garantiemanager/Services/settings_provider.dart';
import 'package:garantiemanager/Services/Helpers/smooth_animations.dart';

class TutorialHelper {

  // ── Einheitliche Overlay-Animation für alle Tutorial-Schritte ──
  static const Duration _fokusDauer = Duration(milliseconds: 600);
  static const Duration _loesDauer = Duration(milliseconds: 600);

  // Expiry-Tutorial: jeder Schritt ist ein eigenes Overlay und blendet neu ein.
  // Hier bewusst kürzer, damit die Schritte zügig aufeinander folgen.
  static const Duration _expiryFokusDauer = Duration(milliseconds: 600);
  
  static bool isTutorialActive = false;
  static bool forcePopFlag = false; 
  static VoidCallback? onTutorialAbbruch;

  /// Einheitlicher, schön gestalteter Skip-Button (Pill-Style).
  static Widget _buildSkipWidget(String lang) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            getText(lang, 'tut_skip'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.close_rounded, color: Colors.white, size: 15),
        ],
      ),
    );
  }

  static Future<void> _sperreQuerformat() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    await Future.delayed(const Duration(milliseconds: 50)); 
  }

  static Future<void> _freigebenOrientierung() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static void abbruch(BuildContext context) {
    isTutorialActive = false;
    _freigebenOrientierung();
    onTutorialAbbruch?.call();
    if (context.mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  static Future<bool> _zeigeWillkommen(BuildContext context, String lang) async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.8),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return PopScope(
          canPop: false,
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_outlined, color: Colors.white, size: 64),
                          const SizedBox(height: 20),
                          Text(
                            getText(lang, 'tut_welcome_title'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 24),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            getText(lang, 'tut_welcome_desc'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: Text(getText(lang, 'tut_welcome_start')),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 20,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            getText(lang, 'tut_skip'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.close_rounded, color: Colors.white, size: 15),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
    return result ?? false;
  }

  static Future<void> zeigeHauptTutorial({
    required BuildContext context,
    required GlobalKey filterKey,
    required GlobalKey addKey,
    required Function(Map<String, String>) onDemoGeraetErstellt,
  }) async {
    isTutorialActive = true; 
    FocusManager.instance.primaryFocus?.unfocus();

    await _sperreQuerformat(); 
    if (!context.mounted) return;
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;

    final bool tutorialStarten = await _zeigeWillkommen(context, lang);
    if (!tutorialStarten) {
      isTutorialActive = false;
      _freigebenOrientierung();
      onTutorialAbbruch?.call();
      return;
    }
    if (!context.mounted) return;

    late TutorialCoachMark tutorial;
    bool naechsterSchrittGestartet = false; 

    void starteAddScreen() async {
      if (naechsterSchrittGestartet) return; 
      naechsterSchrittGestartet = true; 
      tutorial.finish();
      // Ausblenden des Overlays abwarten, sonst überlagern sich
      // Overlay-Animation und Seitenübergang und es ruckelt.
      await Future.delayed(_loesDauer);
      if (!context.mounted) return;

      final result = await Navigator.of(context).push(
        smoothRoute(const AddScreen(isFromTutorial: true)),
      );
      if (!context.mounted) return;
      if (result != null && result is Map<String, String>) {
        onDemoGeraetErstellt(result);
      } else {
        abbruch(context);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      final messTarget = TargetFocus(
        identify: "filter_measure",
        keyTarget: filterKey,
      );

      final aktuellePosition = getTargetCurrent(
        messTarget,
        rootOverlay: false,
      );

      if (aktuellePosition == null) {
        abbruch(context);
        return;
      }

      final screenWidth = MediaQuery.of(context).size.width;
      final targetWidth = screenWidth - 32.0;
      final targetLeft = 16.0;

      final filterPosition = TargetPosition(
        Size(targetWidth, aktuellePosition.size.height),
        Offset(targetLeft, aktuellePosition.offset.dy),
      );

      final targets = <TargetFocus>[
        TargetFocus(
          identify: "filter_target",
          keyTarget: null,
          targetPosition: filterPosition,
          shape: ShapeLightFocus.RRect,
          radius: 20.0,
          paddingFocus: 4.0,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              builder: (context, controller) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      getText(lang, 'tut_search_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      getText(lang, 'tut_search_desc'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        TargetFocus(
          identify: "add_target",
          keyTarget: addKey,
          shape: ShapeLightFocus.Circle,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              builder: (context, controller) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    getText(lang, 'tut_add_title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    getText(lang, 'tut_add_desc'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ];

      tutorial = TutorialCoachMark(
        targets: targets,
        colorShadow: Colors.black,
        focusAnimationDuration: _fokusDauer,
        unFocusAnimationDuration: _loesDauer,
        opacityShadow: 0.8,
        useSafeArea: true,
        paddingFocus: 4.0,
        skipWidget: _buildSkipWidget(lang),
        alignSkip: Alignment.topRight,
        onFinish: () {
          if (!naechsterSchrittGestartet) {
            abbruch(context); 
          }
        },
        onSkip: () {
          abbruch(context);
          return true;
        },
        onClickTarget: (target) {
          if (target.identify == "add_target") {
            starteAddScreen();
          }
        },
        onClickOverlay: (target) {
          if (target.identify == "add_target") {
            starteAddScreen();
          }
        },
      );

      tutorial.show(
        context: context,
        rootOverlay: false,
      );
    });
  }

  static Future<void> zeigeAddDeviceTutorial({
    required BuildContext context,
    required GlobalKey nameKey,
    required GlobalKey kaufdetailsKey,
    required GlobalKey garantieKey,
    required GlobalKey timerKey,
    required GlobalKey fotosKey,
    required GlobalKey saveKey,
    required Function() onSaveDemo,
  }) async {
    if (!isTutorialActive) return; 
    FocusManager.instance.primaryFocus?.unfocus();

    await _sperreQuerformat(); 

    late TutorialCoachMark tutorial;
    if (!context.mounted) return;
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;

    Future<void> scrollZu(GlobalKey zielKey) async {
      final targetContext = zielKey.currentContext;
      if (targetContext != null) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 250),
          alignment: 0.08,
          curve: Curves.easeOut,
        );
      }
    }

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "name_target",
        keyTarget: nameKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Text(
              getText(lang, 'tut_name_desc'),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "kaufdetails_target",
        keyTarget: kaufdetailsKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_kauf_garantie_desc'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "garantie_target",
        keyTarget: garantieKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_kauf_garantie_desc'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "timer_target",
        keyTarget: timerKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Text(
              getText(lang, 'tut_timer_desc'),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "fotos_target",
        keyTarget: fotosKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => Text(
              getText(lang, 'tut_foto_desc'),
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "save_target",
        keyTarget: saveKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => Text(
              getText(lang, 'tut_save_desc'),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ];

    bool isProcessing = false;
    void finishProcessing() {
      Future.delayed(const Duration(milliseconds: 150), () {
        isProcessing = false;
      });
    }

    void handleNext(TargetFocus target) {
      if (isProcessing) return;
      isProcessing = true;

      if (target.identify == "name_target") {
        scrollZu(kaufdetailsKey).then((_) => finishProcessing());
      } else if (target.identify == "kaufdetails_target") {
        scrollZu(garantieKey).then((_) => finishProcessing());
      } else if (target.identify == "garantie_target") {
        scrollZu(timerKey).then((_) => finishProcessing());
      } else if (target.identify == "timer_target") {
        scrollZu(fotosKey).then((_) => finishProcessing());
      } else if (target.identify == "fotos_target") {
        scrollZu(saveKey).then((_) => finishProcessing());
      } else if (target.identify == "save_target") {
        tutorial.finish();
        Future.delayed(const Duration(milliseconds: 200), () {
          onSaveDemo();
        });
      } else {
        isProcessing = false;
      }
    }

    tutorial = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      focusAnimationDuration: _fokusDauer,
      unFocusAnimationDuration: _loesDauer,
      opacityShadow: 0.8,
      skipWidget: _buildSkipWidget(lang),
      alignSkip: Alignment.topRight,
      onFinish: () {},
      onSkip: () {
        abbruch(context);
        return true;
      },
      onClickTarget: handleNext,
      onClickOverlay: handleNext,
    );
    tutorial.show(context: context);
  }

  static Future<void> zeigeHomeKlickDetailTutorial({
    required BuildContext context,
    required GlobalKey demoDeviceKey,
    required Function() onKlickDetail,
  }) async {
    if (!isTutorialActive) return;
    FocusManager.instance.primaryFocus?.unfocus();

    await _sperreQuerformat();
    if (!context.mounted) return;
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    late TutorialCoachMark tutorial;

    bool gestartet = false;
    void proceed() {
      if (gestartet) return;
      gestartet = true;
      tutorial.finish();
      onKlickDetail();
    }
    final targets = [
      TargetFocus(
        identify: "klick_detail_target",
        keyTarget: demoDeviceKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_click_details_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  getText(lang, 'tut_click_details_desc'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    ];

    tutorial = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      focusAnimationDuration: _fokusDauer,
      unFocusAnimationDuration: _loesDauer,
      opacityShadow: 0.8,
      skipWidget: _buildSkipWidget(lang),
      alignSkip: Alignment.topRight,
      onFinish: proceed,
      onSkip: () {
        abbruch(context);
        return true; 
      },
      onClickTarget: (_) => proceed(),
      onClickOverlay: (_) => proceed(),
    );

    tutorial.show(context: context);
  }

  static Future<void> zeigeDetailTutorial({
    required BuildContext context,
    required GlobalKey downloadKey,
    required GlobalKey printKey,
    GlobalKey? infoKey,
    GlobalKey? backKey,
  }) async {
    if (!isTutorialActive) return;
    FocusManager.instance.primaryFocus?.unfocus();

    await _sperreQuerformat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      void startTutorial() {
        if (!context.mounted || !isTutorialActive) return;
        final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
        late TutorialCoachMark tutorial;

        bool isEnded = false;
        void beenden() {
          if (isEnded) return;
          isEnded = true;
          tutorial.finish();
          if (context.mounted && Navigator.canPop(context)) {
            TutorialHelper.forcePopFlag = true;
            Navigator.pop(context);
            TutorialHelper.forcePopFlag = false;
          }
        }

        final targets = <TargetFocus>[];

        if (infoKey != null) {
          targets.add(
            TargetFocus(
              identify: "info_target",
              keyTarget: infoKey,
              shape: ShapeLightFocus.RRect,
              radius: 12,
              contents: [
                TargetContent(
                  align: ContentAlign.bottom,
                  builder: (context, controller) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        getText(lang, 'tut_detail_title'),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        getText(lang, 'tut_detail_info_desc'),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        targets.addAll([
          TargetFocus(
            identify: "download_target",
            keyTarget: downloadKey,
            shape: ShapeLightFocus.Circle,
            contents: [
              TargetContent(
                align: ContentAlign.bottom,
                builder: (context, controller) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      getText(lang, 'tut_download_title'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      getText(lang, 'tut_download_desc'),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
          TargetFocus(
            identify: "print_target",
            keyTarget: printKey,
            shape: ShapeLightFocus.Circle,
            contents: [
              TargetContent(
                align: ContentAlign.bottom,
                builder: (context, controller) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      getText(lang, 'tut_print_title'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      getText(lang, 'tut_print_desc'),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]);

        if (backKey != null) {
          targets.add(
            TargetFocus(
              identify: "back_target",
              keyTarget: backKey,
              shape: ShapeLightFocus.Circle,
              contents: [
                TargetContent(
                  align: ContentAlign.bottom,
                  builder: (context, controller) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        getText(lang, 'tut_back_title'),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        getText(lang, 'tut_back_desc'),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        tutorial = TutorialCoachMark(
          targets: targets,
          colorShadow: Colors.black,
          focusAnimationDuration: _fokusDauer,
          unFocusAnimationDuration: _loesDauer,
          opacityShadow: 0.8,
          skipWidget: _buildSkipWidget(lang),
          alignSkip: Alignment.bottomRight,
          onFinish: beenden,
          onSkip: () {
            abbruch(context);
            return true;
          },
        );

        tutorial.show(context: context);
      }

      final route = ModalRoute.of(context);
      final animation = route?.animation;

      if (animation != null && animation.status != AnimationStatus.completed) {
        void handler(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            animation.removeStatusListener(handler);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              startTutorial();
            });
          }
        }
        animation.addStatusListener(handler);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          startTutorial();
        });
      }
    });
  }

  static Future<void> zeigeHomeBearbeitenLoeschenGlockeTutorial({
    required BuildContext context,
    required GlobalKey editButtonKey,
    required GlobalKey deleteButtonKey,
    required GlobalKey notificationsKey,
    required Function() onOpenExpiry,
  }) async {
    if (!isTutorialActive) return;
    FocusManager.instance.primaryFocus?.unfocus();

    await _sperreQuerformat();
    if (!context.mounted) return;
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    late TutorialCoachMark tutorial;

    bool proceedDone = false;
    void proceed() {
      if (proceedDone) return;
      proceedDone = true;
      tutorial.finish();
      onOpenExpiry();
    }

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "edit_target",
        keyTarget: editButtonKey,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_edit_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  getText(lang, 'tut_edit_desc'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          )
        ],
      ),
      TargetFocus(
        identify: "delete_target",
        keyTarget: deleteButtonKey,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_del_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  getText(lang, 'tut_del_desc'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          )
        ],
      ),
      TargetFocus(
        identify: "bell_target",
        keyTarget: notificationsKey,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_bell_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  getText(lang, 'tut_bell_desc'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          )
        ],
      ),
    ];

    void handleNext(TargetFocus target) {
      if (target.identify == "bell_target") {
        proceed();
      }
    }

    tutorial = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      focusAnimationDuration: _fokusDauer,
      unFocusAnimationDuration: _loesDauer,
      opacityShadow: 0.8,
      skipWidget: _buildSkipWidget(lang),
      alignSkip: Alignment.topRight,
      onFinish: proceed,
      onSkip: () {
        abbruch(context);
        return true; 
      },
      onClickTarget: handleNext,
      onClickOverlay: handleNext,
    );

    tutorial.show(context: context);
  }

  /// Expiry-Screen-Tutorial (sequenziell)
  ///
  /// Jeder Schritt ist ein eigenes Single-Target-Tutorial. Der nächste
  /// Schritt startet erst, wenn der aktuelle wirklich beendet ist (Tap auf
  /// Ziel, Tap aufs Overlay, Finish oder Skip). Das passiert über einen
  /// Completer statt über verkettete Callbacks und Timer.
  static Future<void> zeigeExpiryTutorial({
    required BuildContext context,
    required TabController tabController,
    required GlobalKey activeTabKey,
    required GlobalKey expiredTabKey,
    GlobalKey? eintragKey,
    GlobalKey? backKey,
  }) async {
    if (!isTutorialActive) return;
    FocusManager.instance.primaryFocus?.unfocus();

    await _sperreQuerformat();
    if (!context.mounted) return;

    // Erst starten, wenn die Seite fertig eingeblendet ist. Sonst sitzt der
    // Fokus wegen der Slide-Animation an der falschen Stelle.
    await _warteAufRouteAnimation(context);
    if (!context.mounted || !isTutorialActive) return;

    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;

    final steps = <_ExpiryTutorialStep>[
      _ExpiryTutorialStep(
        identify: "active_tab_target",
        key: activeTabKey,
        title: getText(lang, 'tut_exp_active_title'),
        desc: getText(lang, 'tut_exp_active_desc'),
        tabIndex: 0,
        isLast: false,
      ),
      if (eintragKey != null)
        _ExpiryTutorialStep(
          identify: "eintrag_target",
          key: eintragKey,
          title: getText(lang, 'tut_exp_entry_title'),
          desc: getText(lang, 'tut_exp_entry_desc'),
          tabIndex: 0,
          isLast: false,
        ),
      _ExpiryTutorialStep(
        identify: "expired_tab_target",
        key: expiredTabKey,
        title: getText(lang, 'tut_exp_expired_title'),
        desc: getText(lang, 'tut_exp_expired_desc'),
        tabIndex: 1,
        isLast: false,
      ),
      if (backKey != null)
        _ExpiryTutorialStep(
          identify: "expiry_back_target",
          key: backKey,
          title: getText(lang, 'tut_back_title'),
          desc: getText(lang, 'tut_back_desc'),
          tabIndex: null,
          isLast: true,
        ),
    ];

    for (final step in steps) {
      if (!context.mounted || !isTutorialActive) return;

      // Tab wechseln, falls der Schritt einen anderen Tab verlangt
      // Kein festes Warten: die Tab-Leiste ist immer sichtbar, der Wechsel
      // läuft parallel zur Einblendung des Overlays.
      if (step.tabIndex != null && tabController.index != step.tabIndex) {
        tabController.animateTo(step.tabIndex!);
      }

      // Warten, bis das Ziel-Widget gelayoutet ist
      await _warteAufZiel(step.key);
      if (!context.mounted || !isTutorialActive) return;

      final aktion = await _zeigeEinzelnenExpiryschritt(context, step, lang);
      if (!context.mounted) return;
      if (aktion == _Aktion.abbruch) {
        abbruch(context);
        return;
      }
    }

    if (!context.mounted) return;
    _beendeExpiryTutorial(context);
  }

  /// Wartet, bis die Einblend-Animation der aktuellen Seite fertig ist.
  static Future<void> _warteAufRouteAnimation(BuildContext context) async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      return;
    }
    final completer = Completer<void>();
    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed && !completer.isCompleted) {
        completer.complete();
      }
    }

    animation.addStatusListener(listener);
    try {
      // Sicherheitsnetz: nie länger als 1 Sekunde warten
      await completer.future.timeout(
        const Duration(milliseconds: 1000),
        onTimeout: () {},
      );
    } finally {
      animation.removeStatusListener(listener);
    }
  }

  /// Wartet kurz, bis der GlobalKey einem gerenderten Widget zugeordnet ist.
  static Future<void> _warteAufZiel(GlobalKey key, {int maxMs = 1000}) async {
    var verstrichen = 0;
    while (key.currentContext == null && verstrichen < maxMs) {
      await Future.delayed(const Duration(milliseconds: 16));
      verstrichen += 16;
    }
  }

  /// Zeigt genau einen Schritt und liefert zurück, wie er beendet wurde.
  static Future<_Aktion> _zeigeEinzelnenExpiryschritt(
    BuildContext context,
    _ExpiryTutorialStep step,
    String lang,
  ) async {
    final completer = Completer<_Aktion>();
    late TutorialCoachMark tutorial;

    void fertig(_Aktion aktion) {
      if (!completer.isCompleted) completer.complete(aktion);
    }

    tutorial = TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: step.identify,
          keyTarget: step.key,
          shape: ShapeLightFocus.RRect,
          radius: 12,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              builder: (context, controller) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step.desc,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      colorShadow: Colors.black,
      focusAnimationDuration: _expiryFokusDauer,
      unFocusAnimationDuration: _loesDauer,
      opacityShadow: 0.8,
      useSafeArea: true,
      skipWidget: _buildSkipWidget(lang),
      alignSkip: Alignment.topRight,
      onFinish: () => fertig(_Aktion.weiter),
      onClickTarget: (_) => fertig(_Aktion.weiter),
      onClickOverlay: (_) => fertig(_Aktion.weiter),
      onSkip: () {
        fertig(_Aktion.abbruch);
        return true;
      },
    );

    tutorial.show(context: context);

    final aktion = await completer.future;
    try {
      tutorial.finish();
    } catch (_) {}
    return aktion;
  }

  /// Beendet das Expiry-Tutorial und schließt den Expiry-Screen.
  static void _beendeExpiryTutorial(BuildContext context) {
    // isTutorialActive bleibt true: das gesamte Tutorial endet erst in
    // zeigeHomeSettingsUndEndeTutorial (sonst wird dessen Schluss-Dialog
    // übersprungen und main.dart bleibt im Tutorial-Zustand hängen).
    _freigebenOrientierung();
    if (context.mounted && Navigator.canPop(context)) {
      TutorialHelper.forcePopFlag = true;
      Navigator.pop(context);
      TutorialHelper.forcePopFlag = false;
    }
  }

  static Future<void> zeigeHomeSettingsUndEndeTutorial({
    required BuildContext context,
    required GlobalKey settingsKey,
    required GlobalKey hauptBildschirmKey,
    required Function() onTutorialFinished,
  }) async {
    if (!isTutorialActive) return;
    FocusManager.instance.primaryFocus?.unfocus();

    await _sperreQuerformat();
    if (!context.mounted) return;
    final lang = Provider.of<SettingsProvider>(context, listen: false).languageCode;
    late TutorialCoachMark tutorial;

    bool beendetGestartet = false;
    void beenden() {
      if (beendetGestartet) return;
      beendetGestartet = true;
      tutorial.finish();
      isTutorialActive = false;
      _freigebenOrientierung();
      onTutorialFinished();
    }

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "settings_target",
        keyTarget: settingsKey,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_set_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  getText(lang, 'tut_set_desc'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          )
        ],
      ),
      TargetFocus(
        identify: "end_target",
        keyTarget: hauptBildschirmKey,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  getText(lang, 'tut_set_end_title'), 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  getText(lang, 'tut_set_end_desc'), 
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    ];

    tutorial = TutorialCoachMark(
      targets: targets, 
      colorShadow: Colors.black,
      focusAnimationDuration: _fokusDauer,
      unFocusAnimationDuration: _loesDauer,
      opacityShadow: 0.8,
      skipWidget: _buildSkipWidget(lang),
      alignSkip: Alignment.topRight,
      onFinish: beenden,
      onSkip: () {
        abbruch(context);
        return true;
      },
    );

    tutorial.show(context: context);
  }
}

// ────────────────────────────────────────────────────────────────────────
// Datenstruktur für einen einzelnen Expiry-Tutorial-Schritt.
// Liegt am Ende der Datei, damit die Klasse nicht mit den statischen
// Methoden von TutorialHelper kollidiert.
// ────────────────────────────────────────────────────────────────────────
class _ExpiryTutorialStep {
  final String identify;
  final GlobalKey key;
  final String title;
  final String desc;
  final int? tabIndex;
  final bool isLast;

  const _ExpiryTutorialStep({
    required this.identify,
    required this.key,
    required this.title,
    required this.desc,
    required this.tabIndex,
    required this.isLast,
  });
}

enum _Aktion { weiter, abbruch }