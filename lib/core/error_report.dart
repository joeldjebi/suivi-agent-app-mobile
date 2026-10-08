import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_version.dart';
import 'providers.dart';

/// Erreurs inattendues de l'app : remontées au journal de la console éditeur (connecté
/// seulement, 10 erreurs différentes au plus par session), sans données personnelles.
class ErrorReporter {
  ErrorReporter(this._container);

  final ProviderContainer _container;
  final _sent = <String>{};

  /// Branche les erreurs de Flutter et celles hors de Flutter (asynchrones).
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack, details.context?.toString());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return false;
    };
  }

  void report(Object error, StackTrace? stack, [String? where]) {
    final message = error.toString();
    if (_sent.contains(message) || _sent.length >= 10) return;
    try {
      final api = _container.read(apiProvider);
      if (api.session.accessToken == null) return;
      _sent.add(message);
      unawaited(
        api
            .post<void>('/client-errors', {
              'source': 'mobile',
              'message': message.length > 2000
                  ? message.substring(0, 2000)
                  : message,
              if (stack != null)
                'stack': stack.toString().substring(
                  0,
                  stack.toString().length.clamp(0, 8000),
                ),
              if (where != null)
                'route': where.length > 300 ? where.substring(0, 300) : where,
              'appVersion': AppVersion.current,
            })
            .catchError((Object _) {}),
      );
    } catch (_) {
      // Le journal ne doit jamais faire tomber l'app.
    }
  }
}
