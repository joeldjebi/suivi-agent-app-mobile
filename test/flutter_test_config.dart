import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TEXT_SCALE=2 flutter test : tous les tests avec la police agrandie du téléphone (×2),
/// pour vérifier qu'aucun écran ne déborde quand l'utilisateur grossit le texte.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final scale = double.tryParse(Platform.environment['TEXT_SCALE'] ?? '');
  if (scale != null) {
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .textScaleFactorTestValue =
        scale;
  }
  await testMain();
}
