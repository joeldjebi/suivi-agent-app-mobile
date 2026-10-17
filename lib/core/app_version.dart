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

/// Importance de la dernière version, choisie par l'éditeur.
enum UpdateImportance {
  /// Fenêtre qu'on peut fermer, de nouveau proposée une fois par jour.
  minor,

  /// Fenêtre qu'on peut fermer, de nouveau proposée toutes les heures.
  recommended,

  /// Obligatoire : l'app est bloquée jusqu'à la mise à jour.
  critical;

  static UpdateImportance parse(Object? value) => UpdateImportance.values
      .firstWhere((i) => i.name == value, orElse: () => minor);
}

/// Mise à jour obligatoire (l'app est bloquée) ou simplement proposée.
class UpdateInfo {
  const UpdateInfo({
    required this.required,
    this.version,
    this.storeUrl,
    this.importance = UpdateImportance.minor,
    this.releaseNotes,
  });

  final bool required;

  /// Version minimale (obligatoire) ou dernière version (proposée).
  final String? version;
  final String? storeUrl;
  final UpdateImportance importance;

  /// Nouveautés de la version, rédigées par l'éditeur.
  final String? releaseNotes;

  /// Proposée dans une fenêtre qu'on peut fermer (mineure ou recommandée).
  bool get prompt => !required;

  /// Délai avant de proposer de nouveau la même mise à jour, une fois la fenêtre fermée.
  Duration get remindEvery => importance == UpdateImportance.recommended
      ? const Duration(hours: 1)
      : const Duration(days: 1);
}

class UpdateController extends Notifier<UpdateInfo?> {
  @override
  UpdateInfo? build() => null;

  /// Refus du serveur (426) : l'app passe sur l'écran de mise à jour.
  void requireUpdate({String? storeUrl, String? version}) {
    state = UpdateInfo(
      required: true,
      version: version,
      storeUrl: storeUrl,
      importance: UpdateImportance.critical,
      releaseNotes: state?.releaseNotes,
    );
  }

  /// Au lancement : version minimale et dernière version publiées par l'éditeur.
  Future<void> check() async {
    try {
      final info = await ref
          .read(repositoryProvider)
          .api
          .get<Map<String, dynamic>>('/app/version');
      apply(info);
    } catch (_) {
      // Hors connexion : vérifié au prochain lancement.
    }
  }

  /// Réglages de version reçus (API, ou annonce en direct quand l'éditeur les change).
  void apply(Map<String, dynamic> info) {
    state = updateFor(AppVersion.current, info, ios: Platform.isIOS);
  }
}

/// Mise à jour à proposer (ou imposer) à cette version de l'app, d'après /app/version.
UpdateInfo? updateFor(
  String current,
  Map<String, dynamic> info, {
  required bool ios,
}) {
  final min = info['minVersion'] as String?;
  final latest = info['latestVersion'] as String?;
  final url = info[ios ? 'iosUrl' : 'androidUrl'] as String?;
  final importance = UpdateImportance.parse(info['importance']);
  final notes = (info['releaseNotes'] as String?)?.trim();
  final releaseNotes = notes == null || notes.isEmpty ? null : notes;
  final behind = latest != null && compareVersions(current, latest) < 0;
  if (min != null && compareVersions(current, min) < 0) {
    return UpdateInfo(
      required: true,
      version: behind ? latest : min,
      storeUrl: url,
      importance: UpdateImportance.critical,
      releaseNotes: releaseNotes,
    );
  }
  if (!behind) return null;
  return UpdateInfo(
    required: importance == UpdateImportance.critical,
    version: latest,
    storeUrl: url,
    importance: importance,
    releaseNotes: releaseNotes,
  );
}

final updateProvider = NotifierProvider<UpdateController, UpdateInfo?>(
  UpdateController.new,
);
