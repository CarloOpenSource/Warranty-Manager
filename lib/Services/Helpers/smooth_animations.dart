import 'package:material_ui/material_ui.dart';

// ── Feineinstellungen für alle Seitenübergänge ───────────────────────────
const Duration _vorwaertsDauer = Duration(milliseconds: 300);
const Duration _rueckwaertsDauer = Duration(milliseconds: 240);
const Curve _vorwaertsKurve = Curves.fastOutSlowIn;
const Curve _rueckwaertsKurve = Curves.easeInCubic;

/// Einheitlicher, flüssiger Seitenübergang.
///
/// - Die neue Seite gleitet sanft von rechts herein und blendet dabei ein.
/// - Die alte Seite schiebt sich minimal nach links und wird leicht abgedunkelt.
/// - Jede Seite liegt in einer eigenen RepaintBoundary. Während des Übergangs
///   wird dadurch nur die bewegte Ebene neu gezeichnet, nicht der ganze Baum.
/// - Nur Transform und Opacity, daher GPU-freundlich.
Route<T> smoothRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    opaque: true,
    pageBuilder: (_, _, _) => page,
    transitionDuration: _vorwaertsDauer,
    reverseTransitionDuration: _rueckwaertsDauer,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final eingang = CurvedAnimation(
        parent: animation,
        curve: _vorwaertsKurve,
        reverseCurve: _rueckwaertsKurve,
      );

      final ausgang = CurvedAnimation(
        parent: secondaryAnimation,
        curve: _vorwaertsKurve,
        reverseCurve: _rueckwaertsKurve,
      );

      return RepaintBoundary(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(eingang),
          child: FadeTransition(
            opacity: eingang,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset.zero,
                end: const Offset(-0.03, 0),
              ).animate(ausgang),
              child: FadeTransition(
                opacity: Tween<double>(begin: 1.0, end: 0.9).animate(ausgang),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}