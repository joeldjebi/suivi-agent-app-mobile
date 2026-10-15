import '../../core/format.dart';
import '../../core/models.dart';
import 'product_readings_input.dart' show readingsSummary;

/// Réponse d'un champ de formulaire, en texte (« Oui », « 12 », « 3 oct. »…).
String fieldDisplay(MissionField f, Object? v) => switch (f.type) {
  FieldType.boolean => v == true ? 'Oui' : 'Non',
  FieldType.number => formatNumber(v as num),
  FieldType.date => formatShortDate(DateTime.parse(v as String)),
  FieldType.photo => 'Photo jointe',
  FieldType.products => readingsSummary(v),
  _ => '$v',
};
