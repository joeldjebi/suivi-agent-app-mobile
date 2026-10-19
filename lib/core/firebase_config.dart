import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Projet Firebase « suivi-agent » (notifications push), repris de
/// android/app/google-services.json, ios/Runner/GoogleService-Info.plist et de l'app Web
/// « PerformX Web » de la console Firebase.
/// Identifiants publics de l'application : ils ne donnent aucun droit d'envoi.
class FirebaseConfig {
  static FirebaseOptions? get current => kIsWeb
      ? web
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => android,
          TargetPlatform.iOS => ios,
          _ => null,
        };

  /// Version web (app.performx.online) ; même configuration dans web/firebase-messaging-sw.js.
  static const web = FirebaseOptions(
    apiKey: 'AIzaSyCxgepwhFDlVk6JKjie0nchbvy8s4bgKEI',
    appId: '1:414870340041:web:49d06407567463a56aa818',
    messagingSenderId: '414870340041',
    projectId: 'suivi-agent',
    authDomain: 'suivi-agent.firebaseapp.com',
    storageBucket: 'suivi-agent.firebasestorage.app',
  );

  /// Clé publique « Web Push » (VAPID) du projet, pour les notifications du navigateur.
  static const webVapidKey =
      'BJdNcbxzQ37UiFcaL0OxPRcC85dLT19CLjxuYK9ZTOv-VtdCl4zOY_m3xESSUdWlWXIh7lT33NBRhAdVtUePXE0';

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyAXY6Z4exXBkpmqL4_5cNZUBt95T1k-Bno',
    appId: '1:414870340041:android:b5fb9745fb9436036aa818',
    messagingSenderId: '414870340041',
    projectId: 'suivi-agent',
    storageBucket: 'suivi-agent.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyA4YFLjKru_W9WF6KdI3QmTzpUcK9gXUrg',
    appId: '1:414870340041:ios:a5bde55e97f825196aa818',
    messagingSenderId: '414870340041',
    projectId: 'suivi-agent',
    storageBucket: 'suivi-agent.firebasestorage.app',
    iosBundleId: 'ci.suiviagent.app',
  );
}
