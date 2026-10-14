import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import '../../design/components.dart';
import '../../design/lucide.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../missions/mission_form_screen.dart' show FieldInput, PhotoInput;
import 'outlet_models.dart';
import 'outlet_widgets.dart';
import 'outlets_controller.dart';

/// Ajout d'un point de vente sur place (position mesurée maintenant, photo de la devanture,
/// fiche de la structure), ou modification de ses informations.
class OutletEditorScreen extends ConsumerStatefulWidget {
  const OutletEditorScreen({super.key, this.outlet});

  /// Point de vente à modifier ; absent pour un ajout.
  final Outlet? outlet;

  @override
  ConsumerState<OutletEditorScreen> createState() => _OutletEditorScreenState();
}

class _OutletEditorScreenState extends ConsumerState<OutletEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.outlet?.name);
  late final _category = TextEditingController(text: widget.outlet?.category);
  late final _manager = TextEditingController(text: widget.outlet?.managerName);
  late final _phone = TextEditingController(text: widget.outlet?.phone);
  late final _landmark = TextEditingController(text: widget.outlet?.landmark);
  final _comment = TextEditingController();
  late final Map<String, Object?> _data = {...?widget.outlet?.data};
  Object? _photo;

  /// « Autre » touché : saisie libre du type de commerce.
  bool _otherCategory = false;
  OutletStatus _status = OutletStatus.newOutlet;
  Position? _position;
  bool _locating = false;
  bool _saving = false;
  bool _submitted = false;
  String? _error;

  bool get _editing => widget.outlet != null;

  @override
  void initState() {
    super.initState();
    _photo = widget.outlet?.photoId;
    if (!_editing) _locate();
  }

  @override
  void dispose() {
    for (final c in [_name, _category, _manager, _phone, _landmark, _comment]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final p = await ref.read(trackerProvider).freshPosition();
    if (!mounted) return;
    setState(() {
      _position = p;
      _locating = false;
    });
  }

  Map<String, dynamic> _body({bool force = false}) => {
    'name': _name.text.trim(),
    'category': _category.text.trim().isEmpty ? null : _category.text.trim(),
    'managerName': _manager.text.trim().isEmpty ? null : _manager.text.trim(),
    'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
    'landmark': _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
    'data': {
      for (final e in _data.entries)
        if (e.value != null && e.value != '') e.key: e.value,
    },
    // Photo prise maintenant (fichier du téléphone) : envoyée avant le point de vente.
    if (_photo is Map) 'photo': _photo,
    if (!_editing) ...{
      'lat': _position!.latitude,
      'lng': _position!.longitude,
      'accuracy': _position!.accuracy,
      'status': _status.code,
      if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
      if (force) 'force': true,
    },
  };

  Future<void> _save({bool force = false}) async {
    setState(() => _submitted = true);
    if (!(_form.currentState?.validate() ?? false)) {
      showMessage(context, 'Complétez les champs signalés.', error: true);
      return;
    }
    if (!_editing && _position == null) {
      setState(
        () => _error =
            'Position introuvable : activez la localisation puis touchez « Actualiser ».',
      );
      return;
    }
    tapFeedback();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await sendOutletAction(
        ref,
        kind: _editing ? 'update' : 'create',
        outletId: widget.outlet?.id,
        name: _name.text.trim(),
        body: _body(force: force),
      );
      if (!mounted) return;
      if (saved.outcome == SubmitOutcome.queued) {
        context.pop();
        showMessage(
          context,
          'Enregistré sur le téléphone : il sera envoyé au retour du réseau.',
        );
      } else if (_editing || saved.outlet == null) {
        context.pop();
        showMessage(context, 'Point de vente enregistré.');
      } else {
        context.pushReplacement('/outlets/${saved.outlet!.id}');
        showMessage(context, 'Point de vente ajouté.');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      if (e.code == 'OUTLET_DUPLICATE') {
        await _askDuplicate(e);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Un commerce semblable existe tout près : est-ce le même ?
  Future<void> _askDuplicate(ApiException e) async {
    final candidates = [
      for (final c in (e.details?['candidates'] as List? ?? const []))
        OutletCandidate.fromJson((c as Map).cast<String, dynamic>()),
    ];
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            0,
            Space.page,
            Space.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Est-ce l’un de ceux-ci ?', style: text.titleLarge),
              const SizedBox(height: Space.xs),
              Text(
                'Un point de vente semblable existe déjà tout près.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Space.md),
              for (final c in candidates)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: OutletAvatar(category: null, status: c.status),
                  title: Text(c.name),
                  subtitle: Text(
                    '${c.status.label} · à ${formatDistance(c.distance)}',
                  ),
                  trailing: const Text('C’est lui'),
                  onTap: () => Navigator.pop(context, c.id),
                ),
              const SizedBox(height: Space.md),
              PillButton(
                label: 'Non, c’est un autre commerce',
                style: PillStyle.tonal,
                onPressed: () => Navigator.pop(context, ''),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice.isEmpty) return _save(force: true);
    context.pushReplacement('/outlets/$choice');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final form = ref.watch(outletFormProvider).value;
    final fields = form?.fields ?? const <MissionField>[];
    final categories = form?.categories ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Modifier' : 'Nouveau point de vente'),
      ),
      body: Form(
        key: _form,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.sm,
            Space.page,
            Space.xxxl,
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
            if (!_editing) ...[
              _PositionCard(
                position: _position,
                locating: _locating,
                onRefresh: _locate,
              ),
              const SizedBox(height: Space.lg),
            ],
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom du point de vente *',
                hintText: 'Ex. : Boutique Awa',
              ),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Nom obligatoire' : null,
            ),
            const SizedBox(height: Space.lg),
            Text('Type de commerce', style: text.titleSmall),
            const SizedBox(height: Space.sm),
            _CategoryGrid(
              categories: categories.where((c) => c != 'Autre').toList(),
              selected: _category.text,
              other: _otherCategory,
              onSelect: (c) => setState(() {
                _otherCategory = false;
                _category.text = _category.text == c ? '' : c;
              }),
              onOther: () => setState(() {
                _otherCategory = true;
                _category.clear();
              }),
            ),
            if (_otherCategory ||
                (_category.text.isNotEmpty &&
                    !categories.contains(_category.text))) ...[
              const SizedBox(height: Space.sm),
              TextFormField(
                controller: _category,
                autofocus: _otherCategory,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Quel type de commerce ?',
                  hintText: 'Ex. : Quincaillerie',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: Space.lg),
            TextFormField(
              controller: _manager,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom du gérant'),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone du gérant',
                hintText: '07 07 07 07 07',
              ),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _landmark,
              decoration: const InputDecoration(
                labelText: 'Repère',
                hintText: 'Ex. : en face de la pharmacie du marché',
              ),
            ),
            const SizedBox(height: Space.lg),
            PhotoInput(
              label: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _editing && _photo is String
                      ? 'Photo de la devanture (déjà envoyée : reprenez-la pour la changer)'
                      : 'Photo de la devanture',
                  style: text.titleSmall,
                ),
              ),
              value: _photo is Map ? _photo : null,
              required: false,
              onChanged: (v) =>
                  setState(() => _photo = v ?? widget.outlet?.photoId),
            ),
            if (fields.isNotEmpty) ...[
              const SizedBox(height: Space.xl),
              Text('Fiche', style: text.titleMedium),
              const SizedBox(height: Space.sm),
              for (final f in fields) ...[
                FieldInput(
                  key: ValueKey(f.key),
                  field: f,
                  value: _data[f.key],
                  onChanged: (v) => _data[f.key] = v,
                ),
                const SizedBox(height: Space.lg),
              ],
            ],
            if (!_editing) ...[
              const SizedBox(height: Space.md),
              Text('Statut', style: text.titleSmall),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in OutletStatus.values)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: LucideIcon(s.icon, size: 16, color: s.color),
                      label: Text(s.label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                ],
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: _comment,
                decoration: const InputDecoration(
                  labelText: 'Commentaire (facultatif)',
                ),
              ),
            ],
            const SizedBox(height: Space.xl),
            PillButton(
              label: 'Enregistrer',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _saving || (!_editing && _locating) ? null : _save,
            ),
            if (!_editing)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Enregistrez devant le commerce : sa position est celle du téléphone.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Position mesurée sur place, avec sa précision.
class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.position,
    required this.locating,
    required this.onRefresh,
  });

  final Position? position;
  final bool locating;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final accuracy = position?.accuracy.round();
    final good = accuracy != null && accuracy <= 30;
    return SurfaceCard(
      child: Row(
        children: [
          Icon(
            locating
                ? Icons.gps_not_fixed_rounded
                : position == null
                ? Icons.location_off_outlined
                : Icons.my_location_rounded,
            color: position == null
                ? scheme.error
                : good
                ? scheme.primary
                : toneColor(context, Tone.warning),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              locating
                  ? 'Mesure de la position…'
                  : position == null
                  ? 'Position introuvable'
                  : good
                  ? 'Position enregistrée (à $accuracy m près)'
                  : 'Position approximative (à $accuracy m près) : sortez à découvert puis actualisez.',
              style: text.bodyMedium,
            ),
          ),
          TextButton(
            onPressed: locating ? null : onRefresh,
            child: const Text('Actualiser'),
          ),
        ],
      ),
    );
  }
}

/// Modification ouverte par son adresse : la fiche est relue avant l'écran.
class OutletEditLoader extends ConsumerWidget {
  const OutletEditLoader({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extra = GoRouterState.of(context).extra;
    if (extra is Outlet) return OutletEditorScreen(outlet: extra);
    return switch (ref.watch(outletProvider(id))) {
      AsyncData(:final value) => OutletEditorScreen(outlet: value.outlet),
      AsyncError(:final error) => Scaffold(
        appBar: AppBar(title: const Text('Modifier')),
        body: Padding(
          padding: const EdgeInsets.all(Space.page),
          child: InfoBanner(
            icon: Icons.wifi_off_rounded,
            message: ApiException.from(error).message,
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// Types de commerce en grandes tuiles (icône du site au-dessus du nom), faciles à toucher
/// sur le terrain ; la dernière ouvre une saisie libre.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selected,
    required this.other,
    required this.onSelect,
    required this.onOther,
  });

  final List<String> categories;
  final String selected;
  final bool other;
  final ValueChanged<String> onSelect;
  final VoidCallback onOther;

  @override
  Widget build(BuildContext context) {
    final custom =
        other || (selected.isNotEmpty && !categories.contains(selected));
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Space.sm,
      crossAxisSpacing: Space.sm,
      childAspectRatio: 1.05,
      children: [
        for (final c in categories)
          _CategoryTile(
            label: c,
            icon: categoryIcon(c),
            selected: selected == c,
            onTap: () => onSelect(c),
          ),
        _CategoryTile(
          label: 'Autre…',
          icon: null,
          selected: custom,
          onTap: onOther,
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// Icône Lucide ; null pour « Autre ».
  final String? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon == null
                    ? Icon(Icons.edit_outlined, size: 28, color: color)
                    : LucideIcon(icon!, size: 28, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: selected ? scheme.primary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
