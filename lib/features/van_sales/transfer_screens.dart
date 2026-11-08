import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/product_readings_input.dart' show UnitQuantityField;
import 'transfers.dart';
import 'van_sales.dart';

// ------------------------------------------------------------ « Mon camion »

/// Dans « Mon camion » : mes demandes de dépannage (code à montrer), mes parts à remettre,
/// les demandes de collègues que je peux aider, et la vente d'urgence hors zone.
class TransfersSection extends ConsumerWidget {
  const TransfersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final me = ref.watch(meProvider).id;
    final mine = ref.watch(myTransfersProvider);
    final nearby = ref.watch(nearbyTransfersProvider);
    final list = mine.value ?? const <Transfer>[];
    final requests = list.where((t) => t.requesterId == me && t.isOpen);
    final shares = [
      for (final t in list)
        for (final l in t.legs)
          if (l.giverId == me && l.isActive) (t: t, leg: l),
    ];
    final help = nearby.value ?? const <Transfer>[];
    final offline = mine.hasError && mine.value == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Dépannages'),
        if (offline)
          Text(
            'Les dépannages demandent du réseau.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        for (final t in requests) ...[
          _MyRequestCard(transfer: t),
          const SizedBox(height: Space.sm),
        ],
        for (final s in shares) ...[
          _MyShareCard(transfer: s.t, leg: s.leg),
          const SizedBox(height: Space.sm),
        ],
        for (final t in help) ...[
          _HelpCard(transfer: t),
          const SizedBox(height: Space.sm),
        ],
        if (requests.isEmpty && shares.isEmpty && help.isEmpty && !offline)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              'Un produit vous manque ? Vos collègues proches qui l’ont sont prévenus et viennent vous le remettre.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: PillButton(
                label: 'Demander un dépannage',
                icon: Icons.handshake_outlined,
                style: PillStyle.tonal,
                onPressed: () => context.push('/van/transfer/new'),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: PillButton(
                label: 'Vente hors zone',
                icon: Icons.wrong_location_outlined,
                style: PillStyle.tonal,
                onPressed: () => context.push('/van/out-of-zone'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MyRequestCard extends ConsumerWidget {
  const _MyRequestCard({required this.transfer});

  final Transfer transfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final t = transfer;
    return SurfaceCard(
      border: BorderSide(color: toneColor(context, Tone.info)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ma demande · ${t.statusLabel}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.xs),
          for (final l in t.lines)
            Text(
              '${l.name} : ${formatQty(l.given)} reçu sur ${formatQty(l.requested)}'
              '${l.remaining > 0 ? ' · ${formatQty(l.remaining)} encore cherché' : ''}',
              style: text.bodyMedium,
            ),
          for (final l in t.legs.where((l) => l.isActive)) ...[
            const SizedBox(height: Space.xs),
            Text(
              l.status == 'approval'
                  ? '${l.giverName} (autre équipe) propose ${l.summary} : en attente de son chef.'
                  : '${l.giverName} arrive avec ${l.summary}.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: Space.md),
          if (t.token != null)
            PillButton(
              label: 'Montrer mon code',
              icon: Icons.qr_code_2_rounded,
              onPressed: () => showTransferCode(context, t),
            ),
          const SizedBox(height: Space.xs),
          TextButton(
            onPressed: () async {
              final ok = await confirmSheet(
                context,
                title: 'Clore la demande ?',
                message:
                    'Vos collègues ne viendront plus. Ce qui a déjà été remis reste dans votre camion.',
                confirmLabel: 'J’ai ce qu’il me faut',
              );
              if (!ok || !context.mounted) return;
              await _run(context, ref, () async {
                await ref.read(repositoryProvider).closeTransfer(t.id);
                return 'Demande close.';
              });
            },
            child: const Text('J’ai ce qu’il me faut'),
          ),
        ],
      ),
    );
  }
}

class _MyShareCard extends ConsumerWidget {
  const _MyShareCard({required this.transfer, required this.leg});

  final Transfer transfer;
  final TransferLeg leg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final waiting = leg.status == 'approval';
    return SurfaceCard(
      border: BorderSide(color: toneColor(context, Tone.warning)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dépanner ${transfer.requesterName}',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            waiting
                ? '${leg.summary} · en attente de l’accord de votre chef'
                : '${leg.summary}${leg.expiresAt == null ? '' : ' · réservé jusqu’à ${formatTime(leg.expiresAt!)}'}',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          PillButton(
            label: 'Remettre (scanner son code)',
            icon: Icons.qr_code_scanner_rounded,
            onPressed: waiting
                ? null
                : () => context.push(
                    '/van/transfer/${transfer.id}/handover',
                    extra: (transfer: transfer, leg: leg),
                  ),
          ),
          TextButton(
            onPressed: () async {
              final ok = await confirmSheet(
                context,
                title: 'Abandonner votre part ?',
                message: 'Elle sera de nouveau proposée aux autres collègues.',
                confirmLabel: 'Abandonner',
                destructive: true,
              );
              if (!ok || !context.mounted) return;
              await _run(context, ref, () async {
                await ref.read(repositoryProvider).releaseTransferLeg(leg.id);
                return 'Part abandonnée.';
              });
            },
            child: const Text('Je ne peux plus y aller'),
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard({required this.transfer});

  final Transfer transfer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final t = transfer;
    final where = t.distanceM == null
        ? ''
        : ' (à ${formatDistance(t.distanceM!)})';
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${t.requesterName}$where a besoin de :',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          for (final l in t.missing)
            Text(
              '${formatQty(l.remaining)} × ${l.name} · vous en avez ${formatQty(t.myStock[l.productId] ?? 0)}',
              style: text.bodyMedium,
            ),
          if (t.needsApproval)
            Text(
              'Autre équipe : votre chef validera.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: Space.sm),
          PillButton(
            label: 'Prendre une part',
            icon: Icons.volunteer_activism_outlined,
            style: PillStyle.tonal,
            onPressed: () =>
                context.push('/van/transfer/${t.id}/take', extra: t),
          ),
        ],
      ),
    );
  }
}

String formatDistance(int m) => m < 1000
    ? '$m m'
    : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// Action réseau depuis une carte : message, rechargement, erreur affichée.
Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<String> Function() action,
) async {
  try {
    final message = await action();
    refreshTransfers(ref);
    if (context.mounted) showMessage(context, message);
  } catch (error) {
    if (context.mounted) {
      showMessage(context, ApiException.from(error).message, error: true);
    }
  }
}

/// Code QR du demandeur, à faire scanner par chaque collègue qui le dépanne.
Future<void> showTransferCode(
  BuildContext context,
  Transfer t,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      // Police agrandie : le code reste accessible en faisant défiler.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mon code de dépannage',
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xs),
            Text(
              'Faites-le scanner par le collègue qui vous remet les produits : votre stock se met à jour.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.lg),
            Semantics(
              label: 'Code QR de votre demande de dépannage',
              image: true,
              child: Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: '$transferQrPrefix${t.token}',
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);

// ------------------------------------------------------------ demande

/// Demande de dépannage : les produits qui manquent, envoyée aux collègues proches.
class TransferRequestScreen extends ConsumerStatefulWidget {
  const TransferRequestScreen({super.key});

  @override
  ConsumerState<TransferRequestScreen> createState() =>
      _TransferRequestScreenState();
}

class _TransferRequestScreenState extends ConsumerState<TransferRequestScreen> {
  final _quantities = <String, num>{};
  final _note = TextEditingController();
  final _clientId = const Uuid().v4();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final lines = [
      for (final e in _quantities.entries)
        if (e.value > 0) {'productId': e.key, 'quantity': e.value},
    ];
    if (lines.isEmpty) {
      setState(() => _error = 'Saisissez la quantité d’au moins un produit.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final t = Transfer.fromJson(
        await ref.read(repositoryProvider).createTransfer({
          'clientId': _clientId,
          'lines': lines,
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        }),
      );
      refreshTransfers(ref);
      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        'Demande envoyée à vos collègues proches. Montrez votre code à ceux qui viennent.',
      );
      unawaited(showTransferCode(context, t));
    } catch (error) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = ApiException.from(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final products = ref.watch(ownProductsProvider);
    final van = ref.watch(myVanProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Demander un dépannage')),
      body: switch (products) {
        AsyncError(:final error) => Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(Space.page),
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
              'Ce qu’il vous faut : vos collègues proches qui l’ont sont prévenus, et chacun peut vous en apporter une partie.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            for (final p in value) ...[
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      p.label,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (van != null)
                      Text(
                        'Dans votre camion : ${formatQty(van.quantityOf(p.id))}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: Space.sm),
                    UnitQuantityField(
                      product: p,
                      value: _quantities[p.id],
                      onChanged: (q) => setState(() {
                        _quantities[p.id] = q ?? 0;
                        _error = null;
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
            ],
            TextField(
              controller: _note,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (facultatif)',
                hintText: 'Ex. : rupture chez la Supérette',
              ),
            ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.page),
          child: PillButton(
            label: 'Envoyer la demande',
            icon: Icons.send_rounded,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ prendre une part

/// Je prends une part de la demande d'un collègue : au plus ce qui manque et ce que j'ai.
class TransferTakeScreen extends ConsumerStatefulWidget {
  const TransferTakeScreen({super.key, required this.transfer});

  final Transfer transfer;

  @override
  ConsumerState<TransferTakeScreen> createState() => _TransferTakeScreenState();
}

class _TransferTakeScreenState extends ConsumerState<TransferTakeScreen> {
  late final Map<String, num> _quantities = {
    for (final l in widget.transfer.missing)
      l.productId: [
        l.remaining,
        widget.transfer.myStock[l.productId] ?? 0,
      ].reduce((a, b) => a < b ? a : b),
  };
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final lines = [
      for (final e in _quantities.entries)
        if (e.value > 0) {'productId': e.key, 'quantity': e.value},
    ];
    if (lines.isEmpty) {
      setState(() => _error = 'Indiquez ce que vous pouvez apporter.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .acceptTransfer(widget.transfer.id, lines);
      refreshTransfers(ref);
      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        widget.transfer.needsApproval
            ? 'Proposition envoyée : votre chef doit la valider avant la remise.'
            : 'Part réservée pour 1 h. Allez remettre les produits et scannez le code de ${widget.transfer.requesterName}.',
      );
    } catch (error) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = ApiException.from(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final t = widget.transfer;
    final van = ref.watch(myVanProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text('Dépanner ${t.requesterName}')),
      body: ListView(
        padding: const EdgeInsets.all(Space.page),
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
            'Ce que vous pouvez apporter. Le reste reste proposé aux autres collègues.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          for (final l in t.missing) ...[
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.name,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Il manque ${formatQty(l.remaining)} · vous en avez ${formatQty(t.myStock[l.productId] ?? 0)}',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  UnitQuantityField(
                    product: _productOf(van, l),
                    value: _quantities[l.productId],
                    onChanged: (q) => setState(() {
                      _quantities[l.productId] = q ?? 0;
                      _error = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.page),
          child: PillButton(
            label: 'Prendre cette part',
            icon: Icons.volunteer_activism_outlined,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ),
      ),
    );
  }
}

/// Produit du camion (unité, conditionnements) ; à défaut, un produit à l'unité.
CatalogProduct _productOf(MyVan? van, TransferLine l) =>
    van?.stock.where((s) => s.product.id == l.productId).firstOrNull?.product ??
    CatalogProduct(id: l.productId, name: l.name, own: true, unit: 'unité');

// ------------------------------------------------------------ remise sur place

/// Remise : je règle ce que je donne (au plus ma part), puis je scanne le code du demandeur.
class TransferHandoverScreen extends ConsumerStatefulWidget {
  const TransferHandoverScreen({
    super.key,
    required this.transfer,
    required this.leg,
  });

  final Transfer transfer;
  final TransferLeg leg;

  @override
  ConsumerState<TransferHandoverScreen> createState() =>
      _TransferHandoverScreenState();
}

class _TransferHandoverScreenState
    extends ConsumerState<TransferHandoverScreen> {
  late final Map<String, num> _quantities = {
    for (final l in widget.leg.lines) l.productId: l.quantity,
  };
  final _clientId = const Uuid().v4();
  bool _saving = false;
  String? _error;

  Future<void> _scanAndSend() async {
    final lines = [
      for (final e in _quantities.entries)
        if (e.value > 0) {'productId': e.key, 'quantity': e.value},
    ];
    if (lines.isEmpty) {
      setState(() => _error = 'Indiquez ce que vous remettez.');
      return;
    }
    final raw = await ref.read(codeScannerProvider).scan(context);
    if (raw == null || !mounted) return;
    if (!raw.startsWith(transferQrPrefix)) {
      setState(
        () => _error =
            'Ce code n’est pas un code de dépannage PerformX. Scannez le code affiché par votre collègue.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).handoverTransfer({
        'clientId': _clientId,
        'token': raw.substring(transferQrPrefix.length),
        'lines': lines,
      });
      tapFeedback();
      refreshTransfers(ref);
      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        'Remis à ${widget.transfer.requesterName} : votre stock et le sien sont à jour.',
      );
    } catch (error) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = ApiException.from(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final van = ref.watch(myVanProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text('Remettre à ${widget.transfer.requesterName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.page),
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
            'Vérifiez ce que vous remettez (au plus votre part), puis scannez le code affiché sur le téléphone de ${widget.transfer.requesterName}.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          for (final l in widget.leg.lines) ...[
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.name,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Votre part : ${formatQty(l.quantity)}',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  UnitQuantityField(
                    product: _productOf(
                      van,
                      TransferLine(
                        productId: l.productId,
                        name: l.name,
                        requested: l.quantity,
                        reserved: l.quantity,
                        given: 0,
                        remaining: 0,
                      ),
                    ),
                    value: _quantities[l.productId],
                    onChanged: (q) => setState(() {
                      _quantities[l.productId] = q ?? 0;
                      _error = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(Space.page),
          child: PillButton(
            label: 'Scanner le code et remettre',
            icon: Icons.qr_code_scanner_rounded,
            loading: _saving,
            onPressed: _saving ? null : _scanAndSend,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ vente hors zone

/// Vente d'urgence chez un client hors de ma zone : je le cherche dans toute la structure.
class OutOfZoneSearchScreen extends ConsumerStatefulWidget {
  const OutOfZoneSearchScreen({super.key});

  @override
  ConsumerState<OutOfZoneSearchScreen> createState() =>
      _OutOfZoneSearchScreenState();
}

class _OutOfZoneSearchScreenState extends ConsumerState<OutOfZoneSearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>>? _results;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search({bool near = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final position = near
          ? await ref.read(trackerProvider).freshPosition()
          : null;
      if (near && position == null) {
        setState(
          () => _error =
              'Position introuvable : activez la localisation, ou cherchez le client par son nom.',
        );
        return;
      }
      final rows = await repo.searchOutlets(
        q: near ? null : _q.text.trim(),
        lat: position?.latitude,
        lng: position?.longitude,
      );
      if (mounted) setState(() => _results = rows.cast<Map<String, dynamic>>());
    } catch (error) {
      if (mounted) setState(() => _error = ApiException.from(error).message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Vente hors zone')),
      body: ListView(
        padding: const EdgeInsets.all(Space.page),
        children: [
          Text(
            'Un client hors de votre secteur a besoin d’un produit en urgence ? Trouvez-le, rendez-vous chez lui et vendez sur place, en indiquant le motif. Vos chefs sont prévenus.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.md),
          TextField(
            controller: _q,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Nom du client',
            ),
            onChanged: (v) {
              _debounce?.cancel();
              if (v.trim().length < 2) return;
              _debounce = Timer(
                const Duration(milliseconds: 400),
                () => unawaited(_search()),
              );
            },
          ),
          const SizedBox(height: Space.sm),
          PillButton(
            label: 'Clients autour de moi',
            icon: Icons.near_me_outlined,
            style: PillStyle.tonal,
            onPressed: _loading ? null : () => _search(near: true),
          ),
          const SizedBox(height: Space.md),
          if (_error != null)
            InfoBanner(
              icon: Icons.error_outline_rounded,
              tone: Tone.danger,
              message: _error!,
            ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_results != null && _results!.isEmpty && !_loading)
            Text('Aucun client trouvé.', style: text.bodyMedium),
          if (_results != null && _results!.isNotEmpty)
            GroupedList(
              indent: 0,
              children: [
                for (final o in _results!)
                  ListRow(
                    title: o['name'] as String,
                    subtitle: [
                      if (o['zoneName'] != null) 'Zone ${o['zoneName']}',
                      if (o['distance'] != null)
                        'à ${formatDistance((o['distance'] as num).round())}',
                      if (o['inScope'] == true) 'dans votre secteur',
                    ].join(' · '),
                    onTap: () => context.push(
                      o['inScope'] == true
                          ? '/outlets/${o['id']}/sell'
                          : '/van/out-of-zone/${o['id']}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
