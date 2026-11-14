import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'; // Für compute()
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:path_provider/path_provider.dart';           
import '../main.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Text unten im Splash Screen (hier zentral änderbar)
  static const String _markenText = 'CarloOpenSource';

  @override
  void initState() {
    super.initState();
    // Startet die asynchrone Arbeit erst, NACHDEM das UI das erste Mal gezeichnet wurde.
    // Das verhindert das Einfrieren (Lag) des Hauptprozesses beim App-Start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    // Starte eine Zeitmessung
    final stopwatch = Stopwatch()..start();

    List<Map<String, String>> preloadedListe = [];
    String preloadedDocPath = '';

    // Lade die nötigen Hintergrunddaten asynchron, ohne den UI-Thread zu blockieren
    try {
      final prefs = await SharedPreferences.getInstance();
      final directory = await getApplicationDocumentsDirectory();
      preloadedDocPath = directory.path;

      final String? gespeicherterString = prefs.getString('gerate_liste');
      if (gespeicherterString != null && gespeicherterString.isNotEmpty) {
        // Lagert JSON-Decoding in einen Hintergrund-Isolate aus, damit die Animation nicht ruckelt
        final dynamic decodedData = await compute(jsonDecode, gespeicherterString);
        final List<dynamic> jsonListe = decodedData as List<dynamic>;
        preloadedListe = jsonListe.map((item) => Map<String, String>.from(item)).toList();
      }
    } catch (e) {
      //
    }

    stopwatch.stop();
    final elapsed = stopwatch.elapsedMilliseconds;
    
    // Wir wollen, dass der Splash Screen mindestens 2.5 Sekunden (2500ms) sichtbar ist.
    final int minimumDisplayTime = 2500; 
    if (elapsed < minimumDisplayTime) {
      await Future.delayed(Duration(milliseconds: minimumDisplayTime - elapsed));
    }

    if (!mounted) return;
      
    // Sanfter Fade-Übergang zum Hauptbildschirm, wir übergeben direkt die geladenen Daten!
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(
          preloadedListe: preloadedListe,
          preloadedDocPath: preloadedDocPath,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Exakte Abstimmung auf den nativen Android-Hintergrund
      backgroundColor: isDark ? Colors.black : const Color(0xFFF4F6F9),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/logo.png',
                    width: 170,
                    height: 170,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(
                  color: Color.fromARGB(255, 2, 172, 2),
                ),
              ],
            ),
          ),
          // Leicht gräulicher Text unten, passt sich Dunkel-/Hellmodus an
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Text(
                  _markenText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                    color: isDark
                        ? const Color.fromRGBO(255, 255, 255, 0.45)
                        : const Color.fromRGBO(0, 0, 0, 0.45),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}