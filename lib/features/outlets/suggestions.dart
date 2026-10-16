import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/database.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/mission_form_screen.dart' show PhotoInput;
import 'outlets_controller.dart';

/// Produit concurrent signalé par l'agent, et sa suite.
class ProductSuggestion {
  ProductSuggestion({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
    this.format,
    this.outletName,
    this.productName,
    this.rejectReason,
  });

  final String id;
  final String name;
  final String? format;
  final String status;
  final DateTime createdAt;
  final String? outletName;

  /// Produit du catalogue (accepté).
  final String? productName;
  final String? rejectReason;

  String get label => [name, ?format].join(' ');

  factory ProductSuggestion.fromJson(Map<String, dynamic> j) =>
      ProductSuggestion(
        id: j['id'] as String,
        name: j['name'] as String,
        format: j['format'] as String?,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        outletName: j['outletName'] as String?,
        productName: j['productName'] as String?,
        rejectReason: j['rejectReason'] as String?,
      );
}

/// Produit concurrent déjà au catalogue (pour ne pas le signaler une seconde fois).
class KnownProduct {
  KnownProduct({
    required this.id,
    required this.name,
    this.format,
    this.brand,
    this.category,
  });

  final String id;
  final String name;
  final String? format;
  final String? brand;
  final String? category;

  String get label => [name, ?format].join(' ');

  factory KnownProduct.fromJson(Map<String, dynamic> j) => KnownProduct(
    id: j['id'] as String,
    name: j['name'] as String,
    format: j['format'] as String?,
    brand: j['brand'] as String?,
    category: j['category'] as String?,
  );
}

/// Produits concurrents du catalogue (gardés pour le hors ligne par le cache des réponses).
final competitorProductsProvider =
    FutureProvider.autoDispose<List<KnownProduct>>(
      (ref) async => [
        for (final p
            in await ref.read(repositoryProvider).products(side: 'competitor'))
          KnownProduct.fromJson(p as Map<String, dynamic>),
      ],
    );

/// « Héineken 33 CL » → « heineken 33 cl » : comparaison sans accents ni majuscules.
String plainText(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Produits du catalogue dont le nom (ou la marque) contient ce qui est tapé.
List<KnownProduct> matchingProducts(List<KnownProduct> all, String query) {
  final q = plainText(query);
  if (q.length < 2) return const [];
  return [
    for (final p in all)
      if (plainText('${p.name} ${p.format ?? ''} ${p.brand ?? ''}').contains(q))
        p,
  ];
}

/// Mes signalements.
final suggestionsProvider = FutureProvider.autoDispose<List<ProductSuggestion>>(
  (ref) async => [
    for (final s in await ref.read(repositoryProvider).suggestions())
      ProductSuggestion.fromJson(s as Map<String, dynamic>),
  ],
);

/// Mes produits concurrents signalés : en attente, ajoutés au catalogue, ou non retenus (avec
/// le motif). Le bouton en bas en signale un nouveau.
class SuggestionsScreen extends ConsumerWidget {
  const SuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(suggestionsProvider);
    final items = list.value;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Produits concurrents signalés')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'suggest',
        onPressed: () => context.push('/outlets/suggest'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Signaler un produit'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(suggestionsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            96,
          ),
          children: [
            Text(
              'Un produit concurrent que vous voyez dans un commerce n’est pas au catalogue ? Signalez-le : l’administrateur l’ajoute, puis vous pourrez le relever pendant vos visites.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.md),
            if (list.hasError && items == null)
              InfoBanner(
                icon: Icons.wifi_off_rounded,
                message: ApiException.from(list.error!).message,
              )
            else if (items == null)
              const Padding(
                padding: EdgeInsets.all(Space.xxl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const InfoBanner(
                icon: Icons.info_outline_rounded,
                tone: Tone.info,
                message: 'Vous n’avez encore rien signalé.',
              )
            else
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, s) in items.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 16),
                      ListTile(
                        title: Text(s.label),
                        subtitle: Text(
                          [
                            if (s.status == 'accepted')
                              'Ajouté au catalogue${s.productName != null && s.productName != s.name ? ' (${s.productName})' : ''}'
                            else if (s.status == 'rejected')
                              'Non retenu : ${s.rejectReason ?? ''}'
                            else
                              'En attente de l’administrateur',
                            ?s.outletName,
                            formatShortDate(s.createdAt),
                          ].join(' · '),
                        ),
                        trailing: StatusChip(
                          label: switch (s.status) {
                            'accepted' => 'Ajouté',
                            'rejected' => 'Non retenu',
                            _ => 'En attente',
                          },
                          icon: switch (s.status) {
                            'accepted' => Icons.check_circle_rounded,
                            'rejected' => Icons.block_rounded,
                            _ => Icons.hourglass_top_rounded,
                          },
                          tone: switch (s.status) {
                            'accepted' => Tone.success,
                            'rejected' => Tone.neutral,
                            _ => Tone.info,
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Signaler un produit concurrent vu dans un commerce : nom, format, marque, catégorie, photo,
/// note. Fonctionne sans réseau (envoyé au retour).
class SuggestionEditorScreen extends ConsumerStatefulWidget {
  const SuggestionEditorScreen({super.key, this.outletId});

  /// Point de vente où le produit a été vu (depuis sa fiche).
  final String? outletId;

  @override
  ConsumerState<SuggestionEditorScreen> createState() =>
      _SuggestionEditorScreenState();
}

class _SuggestionEditorScreenState
    extends ConsumerState<SuggestionEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _format = TextEditingController();
  final _brand = TextEditingController();
  final _category = TextEditingController();
  final _note = TextEditingController();
  Object? _photo;
  bool _saving = false;
  String? _error;

  /// Le produit est déjà au catalogue : rien à signaler.
  KnownProduct? _existing;

  /// Nouveau format d'un produit du catalogue : nom, marque et catégorie repris.
  KnownProduct? _variantOf;

  @override
  void dispose() {
    for (final c in [_name, _format, _brand, _category, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    // Même nom et même format qu'un produit du catalogue : il existe déjà.
    final known = ref.read(competitorProductsProvider).value ?? const [];
    final same = known.where(
      (p) =>
          plainText(p.name) == plainText(_name.text) &&
          plainText(p.format ?? '') == plainText(_format.text),
    );
    if (same.isNotEmpty) {
      setState(() => _existing = same.first);
      return;
    }
    tapFeedback();
    setState(() {
      _saving = true;
      _error = null;
    });
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final db = ref.read(databaseProvider);
      final clientId = const Uuid().v4();
      await db
          .into(db.pendingOutlets)
          .insert(
            PendingOutletsCompanion.insert(
              clientId: clientId,
              kind: 'suggestion',
              outletId: Value(widget.outletId),
              name: 'Signalement · ${_name.text.trim()}',
              bodyJson: jsonEncode({
                'name': _name.text.trim(),
                'format': ?text(_format),
                'brand': ?text(_brand),
                'category': ?text(_category),
                'note': ?text(_note),
                'outletId': ?widget.outletId,
                // Photo du téléphone : envoyée juste avant le signalement.
                if (_photo is Map) 'photo': _photo,
              }),
              createdAt: DateTime.now().toUtc(),
            ),
          );
      final (outcome, _) = await ref.read(syncProvider).sendOutletNow(clientId);
      ref.invalidate(suggestionsProvider);
      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        outcome == SubmitOutcome.queued
            ? 'Signalement enregistré sur le téléphone : envoyé au retour du réseau.'
            : 'Merci ! L’administrateur va l’examiner.',
      );
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Catalogue gardé pendant toute la saisie : suggestions et contrôle des doublons à l'envoi.
    final known = ref.watch(competitorProductsProvider).value ?? const [];
    final outlet = widget.outletId == null
        ? null
        : ref.watch(outletProvider(widget.outletId!)).value?.outlet;
    return Scaffold(
      appBar: AppBar(title: const Text('Signaler un produit')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.xs,
            Space.page,
            Space.xl,
          ),
          children: [
            if (_error != null) ...[
              InfoBanner(
                icon: Icons.error_outline_rounded,
                tone: Tone.danger,
                message: _error!,
              ),
              const SizedBox(height: Space.md),
            ],
            if (_existing != null) ...[
              InfoBanner(
                icon: Icons.check_circle_outline_rounded,
                tone: Tone.success,
                message:
                    '${_existing!.label} est déjà au catalogue : inutile de le signaler. Relevez-le pendant vos visites (présence, stock, prix).',
                action: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Compris'),
                ),
              ),
              const SizedBox(height: Space.md),
            ],
            Text(
              outlet == null
                  ? 'Un produit concurrent absent du catalogue : décrivez-le, l’administrateur l’ajoutera.'
                  : 'Vu chez ${outlet.name}. Décrivez-le, l’administrateur l’ajoutera au catalogue.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom du produit *',
                hintText: 'Ex. : Youzou Cola',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Nom obligatoire' : null,
              onChanged: (_) => setState(() => _existing = null),
            ),
            if (_variantOf != null) ...[
              const SizedBox(height: Space.sm),
              InputChip(
                avatar: const Icon(Icons.layers_outlined, size: 18),
                label: Text('Nouveau format de ${_variantOf!.name}'),
                onDeleted: () => setState(() => _variantOf = null),
                deleteButtonTooltipMessage: 'Ce n’est pas un nouveau format',
              ),
            ] else
              _KnownMatches(
                matches: matchingProducts(known, _name.text),
                onSame: (p) => setState(() => _existing = p),
                onVariant: (p) => setState(() {
                  _variantOf = p;
                  _existing = null;
                  _name.text = p.name;
                  if (p.brand != null) _brand.text = p.brand!;
                  if (p.category != null) _category.text = p.category!;
                  _format.clear();
                }),
              ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _format,
                    decoration: const InputDecoration(
                      labelText: 'Format',
                      hintText: '33 cl',
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: TextFormField(
                    controller: _brand,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Marque'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _category,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Catégorie',
                hintText: 'Ex. : Boissons',
              ),
            ),
            const SizedBox(height: Space.lg),
            PhotoInput(
              label: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Photo du produit', style: text.titleSmall),
              ),
              value: _photo,
              required: false,
              onChanged: (v) => setState(() => _photo = v),
            ),
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _note,
              maxLines: 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Remarque (facultatif)',
                hintText: 'Ex. : vendu 250 FCFA, très demandé',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.sm,
          ),
          child: PillButton(
            label: 'Envoyer le signalement',
            icon: Icons.send_rounded,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
    );
  }
}

/// Sous le nom : les produits concurrents déjà au catalogue qui ressemblent à ce qui est tapé.
/// « C'est lui » : rien à signaler ; « Autre format » : un nouveau format de ce produit.
class _KnownMatches extends StatelessWidget {
  const _KnownMatches({
    required this.matches,
    required this.onSame,
    required this.onVariant,
  });

  final List<KnownProduct> matches;
  final ValueChanged<KnownProduct> onSame;
  final ValueChanged<KnownProduct> onVariant;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                Space.md,
                Space.md,
                Space.xs,
              ),
              child: Text(
                'Déjà au catalogue : est-ce l’un d’eux ?',
                style: text.titleSmall,
              ),
            ),
            for (final p in matches.take(5))
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.md,
                  Space.sm,
                  Space.md,
                  Space.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      p.label,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (p.brand != null)
                      Text(
                        p.brand!,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: Space.xs),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onSame(p),
                            child: const Text('C’est lui'),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onVariant(p),
                            child: const Text('Autre format'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.md,
                0,
                Space.md,
                Space.md,
              ),
              child: Text(
                'Aucun ne correspond ? Continuez : c’est un nouveau produit.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
