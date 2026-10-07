import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'field_photo.dart';

/// Formulaire commencé, enregistré sur le téléphone au fil de la saisie.
class FormDraft {
  const FormDraft({
    required this.missionId,
    required this.values,
    required this.updatedAt,
  });

  final String missionId;
  final Map<String, Object?> values;
  final DateTime updatedAt;

  /// Champs remplis (pour l'affichage « 3 champs remplis »).
  int get filled => values.values.where((v) => v != null && v != '').length;
}

/// Brouillons des formulaires : un par mission, repris à la réouverture du formulaire,
/// même après la fermeture de l'app ; retirés à l'envoi.
class FormDrafts {
  static const _prefix = 'form.draft.';

  static Future<FormDraft?> read(String missionId) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      '$_prefix$missionId',
    );
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final values = (json['values'] as Map<String, dynamic>)
          .cast<String, Object?>();
      if (values.values.every((v) => v == null || v == '')) return null;
      return FormDraft(
        missionId: missionId,
        values: values,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    String missionId,
    Map<String, Object?> values,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (values.values.every((v) => v == null || v == '')) {
      await prefs.remove('$_prefix$missionId');
      return;
    }
    await prefs.setString(
      '$_prefix$missionId',
      jsonEncode({
        'values': values,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  /// [keepPhotos] : le formulaire est parti avec ses photos (elles attendent l'envoi).
  static Future<void> delete(
    String missionId, {
    bool keepPhotos = false,
  }) async {
    final draft = keepPhotos ? null : await read(missionId);
    await (await SharedPreferences.getInstance()).remove('$_prefix$missionId');
    if (draft != null) await PhotoStore.delete(FieldPhoto.inData(draft.values));
  }

  /// Missions qui ont un brouillon.
  static Future<Set<String>> missionIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(_prefix.length))
        .toSet();
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }
}
