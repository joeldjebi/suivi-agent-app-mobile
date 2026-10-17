import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivi_agent/core/api_client.dart';

DioException _response(int status, Object? data) {
  final request = RequestOptions(path: '/x');
  return DioException(
    requestOptions: request,
    response: Response(requestOptions: request, statusCode: status, data: data),
  );
}

void main() {
  test('message métier gardé, message technique remplacé par du français', () {
    expect(
      ApiException.from(
        _response(409, {
          'code': 'DAY_ALREADY_STARTED',
          'message': 'Votre journée est déjà démarrée',
        }),
      ).message,
      'Votre journée est déjà démarrée',
    );
    // Messages du framework, sans code : jamais affichés tels quels.
    expect(
      ApiException.from(
        _response(403, {'message': 'Forbidden resource'}),
      ).message,
      'Vous n’avez pas accès à cette action.',
    );
    expect(
      ApiException.from(_response(401, {'message': 'Unauthorized'})).message,
      'Votre session a expiré. Reconnectez-vous.',
    );
    expect(
      ApiException.from(
        _response(400, {
          'message': ['phone must be a string'],
        }),
      ).message,
      'Certaines informations sont manquantes ou invalides.',
    );
    expect(
      ApiException.from(
        _response(413, '<html>413 Request Entity Too Large</html>'),
      ).message,
      'Photo ou envoi trop volumineux.',
    );
    expect(
      ApiException.from(_response(502, '<html>Bad Gateway</html>')).message,
      'Le serveur a rencontré un problème. Réessayez dans un instant.',
    );
  });

  test('délai dépassé et hors ligne : messages distincts, action gardée', () {
    final request = RequestOptions(path: '/x');
    final slow = ApiException.from(
      DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    expect(slow.message, 'Le serveur met trop de temps à répondre. Réessayez.');
    expect(slow.isNetwork, isTrue);
    final offline = ApiException.from(
      DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
      ),
    );
    expect(
      offline.message,
      'Vous êtes hors ligne. Réessayez au retour du réseau.',
    );
    expect(
      ApiException.from(StateError('x')).message,
      'Une erreur inattendue est survenue.',
    );
  });
}
