import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Plateforme d'exécution, sans planter dans un navigateur (où `dart:io` n'est pas
/// disponible) : la version web de l'app partage le code du mobile.
abstract final class AppPlatform {
  /// Version web (navigateur).
  static bool get isWeb => kIsWeb;

  static bool get isIOS => !kIsWeb && Platform.isIOS;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Application installée sur un téléphone (suivi en arrière-plan, notifications locales…).
  static bool get isMobile => isIOS || isAndroid;

  /// Tests automatiques (flutter test).
  static bool get isTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Nom envoyé au serveur (appareils, version de l'app).
  static String get name => isWeb ? 'web' : (isIOS ? 'ios' : 'android');
}
