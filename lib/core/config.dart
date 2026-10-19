import 'package:flutter/foundation.dart';

import 'platform.dart';

/// Serveur de production, en HTTPS.
const productionApiUrl = 'https://performx.online/api';

/// URL de l'API. Surcharger avec : flutter run --dart-define=API_URL=https://…
/// Version publiée (release) : la production ; la version web passe par sa propre adresse
/// (app.performx.online/api), sans requête vers un autre domaine. Développement : la machine
/// hôte (10.0.2.2 depuis l'émulateur Android).
final String apiUrl = const String.fromEnvironment('API_URL').isNotEmpty
    ? const String.fromEnvironment('API_URL')
    : kReleaseMode
    ? (AppPlatform.isWeb ? '${Uri.base.origin}/api' : productionApiUrl)
    : AppPlatform.isAndroid
    ? 'http://10.0.2.2:3000/api'
    : 'http://localhost:3000/api';

/// Origine du serveur (pour les adresses relatives renvoyées par l'API, ex. le logo).
String get serverOrigin => Uri.parse(
  apiUrl,
).replace(path: '').toString().replaceAll(RegExp(r'/$'), '');
