import 'dart:io';

/// URL de l'API. Surcharger avec : flutter run --dart-define=API_URL=https://…
/// Par défaut : la machine hôte (10.0.2.2 depuis l'émulateur Android).
final String apiUrl = const String.fromEnvironment('API_URL').isNotEmpty
    ? const String.fromEnvironment('API_URL')
    : Platform.isAndroid
    ? 'http://10.0.2.2:3000/api'
    : 'http://localhost:3000/api';

/// Origine du serveur (pour les adresses relatives renvoyées par l'API, ex. le logo).
String get serverOrigin => Uri.parse(
  apiUrl,
).replace(path: '').toString().replaceAll(RegExp(r'/$'), '');
