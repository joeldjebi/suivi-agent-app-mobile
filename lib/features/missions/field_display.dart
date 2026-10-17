import '../../core/format.dart';
import '../../core/models.dart';
import 'product_readings_input.dart' show readingsSummary;

/// Réponse d'un champ de formulaire, en texte (« Oui », « 12 », « 3 oct. »…).
/// Une valeur inattendue (ancienne version du formulaire) donne « — », jamais du brut.
String fieldDisplay(MissionField f, Object? v) => switch (f.type) {
  FieldType.boolean => v == true ? 'Oui' : 'Non',
  FieldType.number => v is num ? formatNumber(v) : '—',
  FieldType.date => switch (v is String ? DateTime.tryParse(v) : null) {
    final d? => formatShortDate(d),
    null => '—',
  },
  FieldType.photo => 'Photo jointe',
  FieldType.products => readingsSummary(v),
  _ when v is String || v is num => '$v',
  _ when v is List => v.join(', '),
  _ => '—',
};
