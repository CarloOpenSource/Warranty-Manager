import 'package:material_ui/material_ui.dart';

class EmptyDevicesState extends StatelessWidget {
  final VoidCallback onAddDevice;

  const EmptyDevicesState({super.key, required this.onAddDevice});

  @override
  Widget build(BuildContext context) {
    return Center(
      // 💡 FIX: SingleChildScrollView verhindert Render-Fehler auf dem Handy im Querformat
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.devices_other_rounded,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              const Text(
                'Noch keine Produkte vorhanden',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Füge dein erstes Produkt hinzu, um Kassenbons zu speichern und Garantie-Fristen nicht zu verpassen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: onAddDevice,
                icon: const Icon(Icons.add),
                label: const Text('Erstes Produkt hinzufügen'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24, 
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}