import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'providers.dart';

/// Version installée, annoncée au serveur à chaque requête (X-App-Version).
class AppVersion {
  AppVersion._();

  static String current = '0.0.0';

  static String get platform => Platform.isIOS ? 'ios' : 'android';

  static Future<void> load() async {
    try {
      current = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // Tests : version par défaut.
    }
  }
}

/// 1.10.0 > 1.9.3 : comparaison numérique, partie par partie.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split(RegExp(r'[.+-]')).map((n) => int.tryParse(n) ?? 0).toList();
  final pa = parts(a);
  final pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Mise à jour obligatoire (l'app est bloquée) ou simplement proposée.
class UpdateInfo {
  const UpdateInfo({required this.required, this.version, this.storeUrl});

  final bool required;

  /// Version minimale (obligatoire) ou dernière version (proposée).
  final String? version;
  final String? storeUrl;
}

class UpdateController extends Notifier<UpdateInfo?> {
  @override
  UpdateInfo? build() => null;

  /// Refus du serveur (426) : l'app passe sur l'écran de mise à jour.
  void requireUpdate({String? storeUrl, String? version}) {
    state = UpdateInfo(required: true, version: version, storeUrl: storeUrl);
  }

  /// Au lancement : version minimale et dernière version publiées par l'éditeur.
  Future<void> check() async {
    try {
      final info = await ref
          .read(repositoryProvider)
          .api
          .get<Map<String, dynamic>>('/app/version');
      final min = info['minVersion'] as String?;
      final latest = info['latestVersion'] as String?;
      final url = info[Platform.isIOS ? 'iosUrl' : 'androidUrl'] as String?;
      if (min != null && compareVersions(AppVersion.current, min) < 0) {
        state = UpdateInfo(required: true, version: min, storeUrl: url);
      } else if (latest != null &&
          compareVersions(AppVersion.current, latest) < 0) {
        state = UpdateInfo(required: false, version: latest, storeUrl: url);
      } else {
        state = null;
      }
    } catch (_) {
      // Hors connexion : vérifié au prochain lancement.
    }
  }
}

final updateProvider = NotifierProvider<UpdateController, UpdateInfo?>(
  UpdateController.new,
);
