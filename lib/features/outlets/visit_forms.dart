import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../widgets/common.dart';

/// Formulaire proposé pour visiter un point de vente sans mission (module Points de vente).
/// Ce sont les formulaires des missions : même saisie, mêmes relevés par produit.
class VisitForm {
  VisitForm({
    required this.id,
    required this.name,
    this.description,
    this.fields = const [],
    this.products = const {},
  });

  final String id;
  final String name;
  final String? description;
  final List<MissionField> fields;

  /// Relevés par produit : les produits de chaque champ, par clé de champ.
  final Map<String, List<CatalogProduct>> products;

  factory VisitForm.fromJson(Map<String, dynamic> j) => VisitForm(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
    fields: [
      for (final f in j['fields'] as List? ?? const [])
        MissionField.fromJson(f as Map<String, dynamic>),
    ],
    products: {
      for (final e in ((j['products'] as Map?) ?? const {}).entries)
        e.key as String: [
          for (final p in e.value as List)
            CatalogProduct.fromJson(p as Map<String, dynamic>),
        ],
    },
  );
}

/// Formulaires de visite choisis par l'administrateur (gardés pour le hors ligne).
final visitFormsProvider = FutureProvider.autoDispose<List<VisitForm>>(
  (ref) async => [
    for (final f in await ref.read(repositoryProvider).visitForms())
      VisitForm.fromJson(f as Map<String, dynamic>),
  ],
);

/// Un formulaire de visite ; erreur s'il n'est plus proposé.
final visitFormProvider = FutureProvider.autoDispose.family<VisitForm, String>((
  ref,
  id,
) async {
  final forms = await ref.watch(visitFormsProvider.future);
  return forms.firstWhere(
    (f) => f.id == id,
    orElse: () => throw ApiException(
      'Ce formulaire n’est plus proposé pour les visites.',
      code: 'VISIT_FORM_NOT_ALLOWED',
      status: 400,
    ),
  );
});

/// Agent du module Points de vente : il peut visiter un point de vente sans mission. Le bouton
/// reste visible même sans formulaire de visite choisi : il explique alors quoi demander.
bool canVisitFreely(WidgetRef ref) {
  final me = ref.watch(meProvider);
  return !me.isTeamLead && me.hasOutlets;
}

/// Ouvre la visite d'un point de vente : le seul formulaire proposé, ou celui que l'agent choisit.
Future<void> startVisit(
  BuildContext context,
  WidgetRef ref,
  String outletId,
) async {
  final List<VisitForm> forms;
  try {
    forms = await ref.refresh(visitFormsProvider.future);
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
    return;
  }
  if (!context.mounted) return;
  if (forms.isEmpty) {
    showMessage(
      context,
      'Aucun formulaire de visite n’est encore proposé. Demandez à votre administrateur de les choisir (site web : Points de vente → ⋯ → Formulaires de visite).',
      error: true,
    );
    return;
  }
  var form = forms.first;
  if (forms.length > 1) {
    final picked = await pickOption<VisitForm?>(
      context,
      title: 'Quel formulaire remplir ?',
      selected: null,
      options: {for (final f in forms) f: f.name},
    );
    if (picked?.value == null || !context.mounted) return;
    form = picked!.value!;
  }
  await context.push('/outlets/$outletId/visit?form=${form.id}');
}
