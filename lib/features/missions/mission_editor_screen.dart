import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/form_rows.dart';
import 'missions_controller.dart';

/// Types de mission de la structure (formulaires des agents).
final missionTypesProvider = FutureProvider.autoDispose<List<MissionType>>(
  (ref) => ref.read(repositoryProvider).missionTypes(),
);

/// Groupes dirigés par le chef ; vide si la formule n'inclut pas les groupes.
final leaderGroupsProvider = FutureProvider.autoDispose<List<TeamGroup>>(
  (ref) => ref.read(repositoryProvider).leaderGroups(),
);

/// Agents de l'équipe du chef.
final teamMembersProvider = FutureProvider.autoDispose<List<TeamMember>>(
  (ref) => ref.read(repositoryProvider).team(),
);

const _methods = {
  'count': 'Nombre de formulaires',
  'field_sum': 'Somme d’un champ',
  'manual': 'Validation par le chef',
};

/// Création (mission == null) ou modification d'une mission par le chef d'équipe.
/// À la création : type, assignation et méthode ; ensuite, seuls le titre, la description,
/// la cible et l'échéance changent (les formulaires déjà reçus restent valables).
class MissionEditorScreen extends ConsumerStatefulWidget {
  const MissionEditorScreen({super.key, this.missionId});

  final String? missionId;

  @override
  ConsumerState<MissionEditorScreen> createState() =>
      _MissionEditorScreenState();
}

class _MissionEditorScreenState extends ConsumerState<MissionEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _target = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  MissionType? _type;
  bool _toGroup = true;
  TeamGroup? _group;
  TeamMember? _agent;
  String _method = 'count';
  MissionField? _sumField;
  DateTime? _due;

  bool get _editing => widget.missionId != null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _target.dispose();
    super.dispose();
  }

  /// Valeurs de la mission modifiée, une seule fois.
  void _fill(Mission m) {
    if (_loaded) return;
    _loaded = true;
    _title.text = m.title;
    _description.text = m.description ?? '';
    if (m.targetValue != null) _target.text = formatNumber(m.targetValue!);
    _due = m.dueDate?.toLocal();
    _method = m.progressMethod;
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Échéance de la mission',
    );
    if (picked != null) {
      setState(
        () => _due = DateTime(picked.year, picked.month, picked.day, 18),
      );
    }
  }

  double? get _targetValue => double.tryParse(
    _target.text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'),
  );

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (!_editing) {
      if (_type == null) {
        return showMessage(
          context,
          'Choisissez le type de formulaire',
          error: true,
        );
      }
      if (_toGroup ? _group == null : _agent == null) {
        return showMessage(
          context,
          _toGroup ? 'Choisissez le groupe' : 'Choisissez l’agent',
          error: true,
        );
      }
      if (_method == 'field_sum' && _sumField == null) {
        return showMessage(
          context,
          'Choisissez le champ à additionner',
          error: true,
        );
      }
    }
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    try {
      final common = {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        if (_method != 'manual') 'targetValue': _targetValue,
        if (_due != null) 'dueDate': _due!.toUtc().toIso8601String(),
      };
      if (_editing) {
        await repo.updateMission(widget.missionId!, common);
        ref.invalidate(missionProvider(widget.missionId!));
      } else {
        final created = await repo.createMission({
          ...common,
          'typeId': _type!.id,
          if (_toGroup)
            'assigneeGroupId': _group!.id
          else
            'assigneeAgentId': _agent!.id,
          'progressMethod': _method,
          if (_method == 'field_sum') 'sumFieldKey': _sumField!.key,
        });
        if (!mounted) return;
        ref.invalidate(missionsProvider);
        showMessage(context, 'Mission créée : l’équipe la voit dès maintenant');
        context.pushReplacement('/missions/${created['id']}');
        return;
      }
      ref.invalidate(missionsProvider);
      if (!mounted) return;
      showMessage(context, 'Mission mise à jour');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mission = _editing
        ? ref.watch(missionProvider(widget.missionId!))
        : null;
    if (mission != null) {
      if (mission.hasValue) _fill(mission.value!);
      if (!mission.hasValue) {
        return Scaffold(
          appBar: AppBar(title: const Text('Modifier la mission')),
          body: mission.hasError
              ? Padding(
                  padding: const EdgeInsets.all(Space.page),
                  child: InfoBanner(
                    icon: Icons.wifi_off_rounded,
                    message: ApiException.from(mission.error!).message,
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        );
      }
    }
    final types = _editing ? null : ref.watch(missionTypesProvider);
    final groups = _editing ? null : ref.watch(leaderGroupsProvider);
    final agents = _editing ? null : ref.watch(teamMembersProvider);
    // Sans groupe (formule sans groupes, ou aucun groupe) : mission pour un agent.
    final hasGroups = (groups?.value ?? const []).isNotEmpty;
    final toGroup = hasGroups && _toGroup;
    final manual = _method == 'manual';
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget pickRow(
      String label,
      String? value,
      VoidCallback? onTap, {
      bool loading = false,
    }) => ListRow(
      title: label,
      value: value ?? (loading ? 'Chargement…' : 'Choisir'),
      onTap: onTap,
      titleColor: null,
    );

    return FormScaffold(
      title: _editing ? 'Modifier la mission' : 'Nouvelle mission',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      saveLabel: _editing ? 'Enregistrer' : 'Créer',
      children: [
        GroupedList(
          header: 'Mission',
          indent: Space.lg,
          children: [
            FieldRow(
              label: 'Titre',
              controller: _title,
              autofocus: !_editing,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Donnez un titre' : null,
            ),
            FieldRow(
              label: 'Consignes',
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              multiline: true,
            ),
          ],
        ),
        if (!_editing) ...[
          GroupedList(
            header: 'Formulaire',
            footer:
                'Les agents remplissent ce formulaire à chaque visite ou action.',
            indent: Space.lg,
            children: [
              pickRow(
                'Type',
                _type?.name,
                types?.value == null
                    ? null
                    : () async {
                        final picked = await pickOption<MissionType?>(
                          context,
                          title: 'Type de formulaire',
                          selected: _type,
                          options: {for (final t in types!.value!) t: t.name},
                        );
                        if (picked != null) {
                          setState(() {
                            _type = picked.value;
                            _sumField = null;
                            if (_method == 'field_sum' &&
                                (_type?.numberFields.isEmpty ?? true)) {
                              _method = 'count';
                            }
                          });
                        }
                      },
                loading: types?.isLoading ?? false,
              ),
            ],
          ),
          GroupedList(
            header: 'Pour qui',
            footer: toGroup
                ? 'Objectif d’équipe : tous les agents du groupe y contribuent.'
                : 'Seul cet agent voit la mission.',
            indent: Space.lg,
            children: [
              if (hasGroups)
                Padding(
                  padding: const EdgeInsets.all(Space.sm),
                  child: AppSegmented<bool>(
                    segments: const {true: 'Un groupe', false: 'Un agent'},
                    selected: toGroup,
                    onChanged: (v) => setState(() => _toGroup = v),
                  ),
                ),
              if (toGroup)
                pickRow('Groupe', _group?.name, () async {
                  final picked = await pickOption<TeamGroup?>(
                    context,
                    title: 'Groupe',
                    selected: _group,
                    options: {for (final g in groups!.value!) g: g.name},
                  );
                  if (picked != null) setState(() => _group = picked.value);
                })
              else
                pickRow(
                  'Agent',
                  _agent?.fullName,
                  agents?.value == null
                      ? null
                      : () async {
                          final picked = await pickOption<TeamMember?>(
                            context,
                            title: 'Agent',
                            selected: _agent,
                            options: {
                              for (final a in agents!.value!) a: a.fullName,
                            },
                          );
                          if (picked != null) {
                            setState(() => _agent = picked.value);
                          }
                        },
                  loading: agents?.isLoading ?? false,
                ),
            ],
          ),
        ],
        GroupedList(
          header: 'Objectif',
          footer: _editing
              ? 'La méthode de calcul ne change plus une fois la mission créée.'
              : manual
              ? 'Vous déclarez vous-même la mission atteinte ou échouée.'
              : 'La progression se calcule seule avec les formulaires acceptés.',
          indent: Space.lg,
          children: [
            ListRow(
              title: 'Mesure',
              value: _methods[_method],
              onTap: _editing
                  ? null
                  : () async {
                      final canSum = _type?.numberFields.isNotEmpty ?? false;
                      final picked = await pickOption<String>(
                        context,
                        title: 'Mesure de la progression',
                        selected: _method,
                        options: {
                          for (final e in _methods.entries)
                            if (e.key != 'field_sum' || canSum) e.key: e.value,
                        },
                      );
                      if (picked != null) {
                        setState(() => _method = picked.value);
                      }
                    },
            ),
            if (!_editing && _method == 'field_sum')
              pickRow('Champ additionné', _sumField?.label, () async {
                final picked = await pickOption<MissionField?>(
                  context,
                  title: 'Champ à additionner',
                  selected: _sumField,
                  options: {for (final f in _type!.numberFields) f: f.label},
                );
                if (picked != null) setState(() => _sumField = picked.value);
              }),
            if (!manual)
              FieldRow(
                label: _method == 'field_sum' ? 'Total visé' : 'Formulaires',
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  final value = double.tryParse(
                    (v ?? '')
                        .replaceAll(RegExp(r'\s'), '')
                        .replaceAll(',', '.'),
                  );
                  return value == null || value <= 0
                      ? 'Indiquez une cible positive'
                      : null;
                },
              ),
            ListRow(
              title: 'Échéance',
              value: _due == null ? 'Aucune' : formatDay(_due!),
              onTap: _pickDue,
              trailing: _due == null
                  ? null
                  : IconButton(
                      tooltip: 'Retirer l’échéance',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _due = null);
                      },
                    ),
            ),
          ],
        ),
        if (!_editing && types?.value?.isEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: Space.lg),
            child: Text(
              'Aucun type de formulaire : demandez à l’administrateur d’en créer un.',
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
      ],
    );
  }
}
