import 'app_version.dart';
import 'package:dio/dio.dart';

import 'config.dart';
import 'session.dart';

/// Erreur renvoyée par l'API, avec son code métier (ZONE_FULL, DAY_STARTED…).
class ApiException implements Exception {
  ApiException(this.message, {this.code, this.status});

  final String message;
  final String? code;
  final int? status;

  /// Pas de réponse du serveur : réseau absent ou serveur injoignable.
  bool get isNetwork => status == null;

  @override
  String toString() => message;

  factory ApiException.from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final response = error.response;
      if (response == null) {
        return ApiException(
          'Pas de connexion. Vérifiez votre réseau et réessayez.',
        );
      }
      final data = response.data;
      final body = data is Map ? data : const {};
      final raw = body['message'];
      final message = raw is String && response.statusCode! < 500
          ? raw
          : response.statusCode == 400
          ? 'Certaines valeurs sont invalides.'
          : 'Le serveur a rencontré un problème. Réessayez dans un instant.';
      return ApiException(
        message,
        code: body['code'] as String?,
        status: response.statusCode,
      );
    }
    return ApiException('Une erreur inattendue est survenue.');
  }
}

/// Client HTTP : ajoute le jeton, le renouvelle une fois si besoin, sinon déconnecte.
class ApiClient {
  ApiClient(this.session, {Dio? dio, this.onSessionExpired})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: apiUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ),
          ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = session.accessToken;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          // Version de l'app : le serveur peut exiger une mise à jour.
          options.headers['X-App-Version'] = AppVersion.current;
          options.headers['X-App-Platform'] = AppVersion.platform;
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          // Formule changée ou abonnement suspendu : l'app relit le profil et s'adapte.
          if (error.response?.statusCode == 402) onPlanChanged?.call();
          // App trop ancienne : écran de mise à jour.
          if (error.response?.statusCode == 426) {
            final body = error.response?.data;
            onUpdateRequired?.call(
              body is Map ? body['storeUrl'] as String? : null,
              body is Map ? body['minVersion'] as String? : null,
            );
            return handler.next(error);
          }
          final isAuthCall = request.path.startsWith('/auth/');
          if (error.response?.statusCode != 401 ||
              isAuthCall ||
              request.extra['retried'] == true) {
            return handler.next(error);
          }
          if (await refresh()) {
            request.extra['retried'] = true;
            request.headers['Authorization'] = 'Bearer ${session.accessToken}';
            try {
              return handler.resolve(await this.dio.fetch(request));
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
          onSessionExpired?.call();
          handler.next(error);
        },
      ),
    );
  }

  final SessionStore session;
  final Dio dio;
  void Function()? onSessionExpired;

  /// Réponse 402 (fonctionnalité hors formule, abonnement suspendu).
  void Function()? onPlanChanged;

  /// Réponse 426 : mise à jour de l'app obligatoire (lien de téléchargement, version).
  void Function(String? storeUrl, String? minVersion)? onUpdateRequired;

  Future<bool>? _refreshing;

  /// Renouvelle le jeton d'accès ; un seul appel à la fois.
  Future<bool> refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final token = await session.refreshToken();
    if (token == null) return false;
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': token},
      );
      await session.save(
        access: res.data!['accessToken'] as String,
        refresh: res.data!['refreshToken'] as String,
      );
      return true;
    } on DioException catch (e) {
      // Hors connexion : on garde la session, elle sera renouvelée plus tard.
      if (e.response == null) return false;
      await session.clear();
      return false;
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get<T>(path, queryParameters: query));

  Future<T> post<T>(String path, [Object? body]) =>
      _wrap(() => dio.post<T>(path, data: body));

  Future<T> patch<T>(String path, [Object? body]) =>
      _wrap(() => dio.patch<T>(path, data: body));

  Future<T> put<T>(String path, [Object? body]) =>
      _wrap(() => dio.put<T>(path, data: body));

  Future<T> delete<T>(String path) => _wrap(() => dio.delete<T>(path));

  Future<T> _wrap<T>(Future<Response<T>> Function() call) async {
    try {
      return (await call()).data as T;
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}
