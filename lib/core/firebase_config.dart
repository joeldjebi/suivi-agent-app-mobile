import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Projet Firebase « suivi-agent » (notifications push), repris de
/// android/app/google-services.json et ios/Runner/GoogleService-Info.plist.
/// Identifiants publics de l'application : ils ne donnent aucun droit d'envoi.
class FirebaseConfig {
  static FirebaseOptions? get current => switch (defaultTargetPlatform) {
    TargetPlatform.android => android,
    TargetPlatform.iOS => ios,
    _ => null,
  };

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
