import 'dart:io';

import 'package:flutter/foundation.dart';

/// Serveur de production (adresse IP en attendant le nom de domaine et le HTTPS).
const productionApiUrl = 'http://185.215.167.87:8090/api';

/// URL de l'API. Surcharger avec : flutter run --dart-define=API_URL=https://…
/// Version publiée (release) : la production. Développement : la machine hôte
/// (10.0.2.2 depuis l'émulateur Android).
final String apiUrl = const String.fromEnvironment('API_URL').isNotEmpty
    ? const String.fromEnvironment('API_URL')
    : kReleaseMode
    ? productionApiUrl
    : Platform.isAndroid
    ? 'http://10.0.2.2:3000/api'
    : 'http://localhost:3000/api';

/// Origine du serveur (pour les adresses relatives renvoyées par l'API, ex. le logo).
String get serverOrigin => Uri.parse(
  apiUrl,
).replace(path: '').toString().replaceAll(RegExp(r'/$'), '');
