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

  @override
  void dispose() {
    for (final c in [_name, _format, _brand, _category, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
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
