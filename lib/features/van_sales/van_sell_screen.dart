import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../outlets/outlet_models.dart';
import '../outlets/outlet_widgets.dart' show formatDistance;
import '../outlets/outlets_controller.dart' show herePositionProvider;

/// Clients à qui vendre depuis le camion : les plus proches d'abord (position du
/// téléphone), ou par nom. Les points de vente fermés ne sont pas proposés.
final vanClientsProvider = FutureProvider.autoDispose
    .family<List<Outlet>, String>((ref, q) async {
      final here = q.isEmpty
          ? await ref.watch(herePositionProvider.future)
          : null;
      final json = await ref
          .read(repositoryProvider)
          .outlets(q: q, lat: here?.latitude, lng: here?.longitude, limit: 30);
      return [
        for (final o in json['items'] as List)
          Outlet.fromJson(o as Map<String, dynamic>),
      ].where((o) => o.status != OutletStatus.closed).toList();
    });

/// « Vendre à un client » : choisir le client, puis la vente s'ouvre (retour au camion
/// une fois validée).
class VanSellScreen extends ConsumerStatefulWidget {
  const VanSellScreen({super.key});

  @override
  ConsumerState<VanSellScreen> createState() => _VanSellScreenState();
}

class _VanSellScreenState extends ConsumerState<VanSellScreen> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final clients = ref.watch(vanClientsProvider(_q));
    return Scaffold(
      appBar: AppBar(title: const Text('Vendre à un client')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Space.sm,
          Space.page,
          Space.xl,
        ),
        children: [
          TextField(
            autofocus: false,
            decoration: const InputDecoration(
              hintText: 'Nom du client',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 350),
                () => setState(() => _q = v.trim()),
              );
            },
          ),
          const SizedBox(height: Space.md),
          SectionHeader(_q.isEmpty ? 'Les plus proches' : 'Résultats'),
          switch (clients) {
            AsyncError(:final error) when !clients.hasValue => InfoBanner(
              icon: Icons.wifi_off_rounded,
              message: ApiException.from(error).message,
            ),
            AsyncValue(:final value?) when value.isEmpty => Text(
              _q.isEmpty
                  ? 'Aucun de vos clients n’est proche. Cherchez-le par son nom.'
                  : 'Aucun de vos clients ne correspond.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            AsyncValue(:final value?) => SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, o) in value.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: Space.lg),
                    ListRow(
                      title: o.name,
                      subtitle: [
                        o.category,
                        o.landmark,
                        if (o.distance != null)
                          'à ${formatDistance(o.distance!)}',
                      ].whereType<String>().join(' · '),
                      onTap: () => context.pushReplacement('/van/sell/${o.id}'),
                    ),
                  ],
                ],
              ),
            ),
            _ => const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          const SizedBox(height: Space.lg),
          Center(
            child: TextButton.icon(
              onPressed: () => context.pushReplacement('/van/out-of-zone'),
              icon: const Icon(Icons.wrong_location_outlined, size: 18),
              label: const Text('Client d’un autre secteur ? Vente hors zone'),
            ),
          ),
        ],
      ),
    );
  }
}
