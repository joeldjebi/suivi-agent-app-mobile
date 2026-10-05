import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Enregistre les captures prises par les tests d'intégration.
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final dir = Directory(Platform.environment['SCREENSHOTS_DIR'] ?? 'build/screenshots')..createSync(recursive: true);
        File('${dir.path}/$name.png').writeAsBytesSync(bytes);
        return true;
      },
    );
