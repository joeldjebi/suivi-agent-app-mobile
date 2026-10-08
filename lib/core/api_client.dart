import 'dart:convert';
import 'dart:async';
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
          'Vous êtes hors ligne. Réessayez au retour du réseau.',
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

/// Mémoire des réponses (base locale du téléphone).
abstract interface class ResponseCache {
  Future<void> put(String key, String body);
  Future<String?> get(String key);
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

  /// Mémoire des écrans : la dernière réponse de chaque lecture, rendue hors ligne.
  ResponseCache? cache;

  /// Joignabilité du serveur (bandeau « Hors ligne », relecture au retour du réseau).
  void Function()? onReachable;
  void Function()? onUnreachable;

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

  /// Lecture : gardée en mémoire ; sans réseau, la dernière version gardée est rendue.
  Future<T> get<T>(String path, {Map<String, dynamic>? query}) async {
    final key = cacheKey(path, query);
    try {
      final data = (await dio.get<T>(path, queryParameters: query)).data;
      onReachable?.call();
      if (data is Map || data is List) {
        unawaited(
          cache?.put(key, jsonEncode(data)).catchError((Object _) {}) ??
              Future<void>.value(),
        );
      }
      return data as T;
    } catch (e) {
      final error = ApiException.from(e);
      if (!error.isNetwork) {
        onReachable?.call();
        throw error;
      }
      onUnreachable?.call();
      final saved = await cache?.get(key).catchError((Object _) => null);
      if (saved != null) return jsonDecode(saved) as T;
      throw error;
    }
  }

  /// Clé de mémoire : adresse et paramètres triés.
  static String cacheKey(String path, Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return path;
    final keys = query.keys.toList()..sort();
    return '$path?${keys.map((k) => '$k=${query[k]}').join('&')}';
  }

  Future<T> post<T>(String path, [Object? body]) =>
      _wrap(() => dio.post<T>(path, data: body));

  Future<T> patch<T>(String path, [Object? body]) =>
      _wrap(() => dio.patch<T>(path, data: body));

  Future<T> put<T>(String path, [Object? body]) =>
      _wrap(() => dio.put<T>(path, data: body));

  Future<T> delete<T>(String path) => _wrap(() => dio.delete<T>(path));

  Future<T> _wrap<T>(Future<Response<T>> Function() call) async {
    try {
      final data = (await call()).data as T;
      onReachable?.call();
      return data;
    } catch (e) {
      final error = ApiException.from(e);
      error.isNetwork ? onUnreachable?.call() : onReachable?.call();
      throw error;
    }
  }
}
