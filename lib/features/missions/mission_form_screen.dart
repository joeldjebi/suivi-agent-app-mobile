import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../design/components.dart';
import '../../widgets/common.dart';
import 'missions_controller.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';

/// Formulaire généré à partir des champs définis par la structure (RG-13).
/// Enregistré sur le téléphone puis envoyé ; fonctionne sans réseau.
class MissionFormScreen extends ConsumerStatefulWidget {
  const MissionFormScreen({super.key, required this.id, this.retry});

  final String id;

  /// Formulaire refusé à corriger : ses valeurs sont reprises, il est remplacé à l'envoi.
  final String? retry;

  @override
  ConsumerState<MissionFormScreen> createState() => _MissionFormScreenState();
}

class _MissionFormScreenState extends ConsumerState<MissionFormScreen> {
  final _form = GlobalKey<FormState>();
  final _values = <String, Object?>{};
  bool _saving = false;
  bool _submitted = false;
  String? _rejectedReason;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Correction : les valeurs du formulaire refusé sont chargées avant l'affichage.
  late bool _loadingRetry = widget.retry != null;

  @override
  void initState() {
    super.initState();
    final retry = widget.retry;
    if (retry != null) unawaited(_loadRetry(retry));
  }

  /// Reprend les valeurs et le motif du formulaire refusé.
  Future<void> _loadRetry(String clientId) async {
    final db = ref.read(databaseProvider);
    final row = await (db.select(
      db.pendingSubmissions,
    )..where((s) => s.clientId.equals(clientId))).getSingleOrNull();
    if (!mounted) return;
    if (row == null) return setState(() => _loadingRetry = false);
    setState(() {
      _loadingRetry = false;
      _values.addAll(
        (jsonDecode(row.dataJson) as Map<String, dynamic>)
            .cast<String, Object?>(),
      );
      _rejectedReason = row.error;
    });
  }

  Future<void> _save(Mission mission) async {
    final form = _form.currentState;
    if (form == null) return;
    setState(() => _submitted = true);
    if (!form.validate()) {
      showMessage(context, 'Complétez les champs signalés.', error: true);
      return;
    }
    tapFeedback();
    setState(() => _saving = true);
    try {
      final data = {
        for (final f in mission.fields)
          if (_values[f.key] != null && _values[f.key] != '')
            f.key: _values[f.key],
      };
      final outcome = await saveSubmission(
        ref,
        mission,
        data,
        replacing: widget.retry,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
        context,
        outcome == SubmitOutcome.sent
            ? 'Formulaire envoyé.'
            : 'Formulaire enregistré sur le téléphone. Il sera envoyé dès le retour du réseau.',
      );
    } on ApiException catch (e) {
      // Refusé par le serveur : les valeurs restent à l'écran, le motif s'affiche en tête
      // (pas de message flottant : il masquerait le bouton d'envoi).
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => _rejectedReason = e.message);
        if (_scroll.hasClients) {
          unawaited(
            _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Mission telle qu'elle était à l'ouverture du formulaire : une relecture (mise à jour en
  /// direct, mission close entre-temps) ne doit ni effacer la saisie ni bloquer l'écran ;
  /// c'est l'envoi qui dira si la mission accepte encore des formulaires.
  Mission? _mission;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(missionProvider(widget.id));
    _mission ??= async.value;
    final loaded = _mission;
    final AsyncValue<Mission> mission = loaded != null
        ? AsyncData(loaded)
        : async;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.retry == null
              ? 'Nouveau formulaire'
              : 'Corriger le formulaire',
        ),
      ),
      body: _loadingRetry
          ? const Center(child: CircularProgressIndicator())
          : mission.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: InfoBanner(
                  icon: Icons.error_outline_rounded,
                  message: ApiException.from(e).message,
                  tone: Tone.danger,
                ),
              ),
              data: (m) => Form(
                key: _form,
                autovalidateMode: _submitted
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  children: [
                    if (_rejectedReason != null) ...[
                      InfoBanner(
                        icon: Icons.error_outline_rounded,
                        tone: Tone.danger,
                        message: 'Refusé : $_rejectedReason',
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(m.title, style: text.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Les champs marqués * sont obligatoires.',
                      style: text.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (m.fields.isEmpty)
                      const InfoBanner(
                        icon: Icons.info_outline_rounded,
                        tone: Tone.info,
                        message:
                            'Aucun champ à remplir : enregistrez pour valider votre visite.',
                      ),
                    for (final f in m.fields) ...[
                      _FieldInput(
                        // Clé stable : le champ garde sa saisie quand un bandeau s'insère au-dessus.
                        key: ValueKey('field-${f.key}'),
                        field: f,
                        value: _values[f.key],
                        onChanged: (v) => setState(() => _values[f.key] = v),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                ),
              ),
            ),
      bottomNavigationBar: mission.hasValue
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PillButton(
                  label: 'Enregistrer',
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onPressed: () => _save(mission.requireValue),
                ),
              ),
            )
          : null,
    );
  }
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final MissionField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  String get _label => '${field.label}${field.required ? ' *' : ''}';

  String? _requiredCheck(Object? v) =>
      field.required && (v == null || v == '') ? 'Champ obligatoire' : null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final label = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(_label, style: text.titleSmall),
    );

    switch (field.type) {
      case FieldType.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            TextFormField(
              initialValue: value is String ? value as String : null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              onChanged: (v) => onChanged(v.trim()),
              validator: (v) => _requiredCheck(v?.trim()),
            ),
          ],
        );
      case FieldType.number:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            TextFormField(
              initialValue: value is num ? formatNumber(value as num) : null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              textInputAction: TextInputAction.next,
              onChanged: (v) => onChanged(
                num.tryParse(
                  v.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.'),
                ),
              ),
              validator: (v) {
                final raw = (v ?? '').replaceAll(RegExp(r'\s'), '');
                if (raw.isEmpty) return _requiredCheck(null);
                return num.tryParse(raw.replaceAll(',', '.')) == null
                    ? 'Saisissez un nombre'
                    : null;
              },
            ),
          ],
        );
      case FieldType.boolean:
        return FormField<bool>(
          initialValue: value as bool?,
          validator: _requiredCheck,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              SegmentedButton<bool>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Oui'),
                    icon: Icon(Icons.check_rounded),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Non'),
                    icon: Icon(Icons.close_rounded),
                  ),
                ],
                selected: {if (state.value != null) state.value!},
                onSelectionChanged: (s) {
                  final v = s.isEmpty ? null : s.first;
                  state.didChange(v);
                  onChanged(v);
                },
              ),
              if (state.hasError) _ErrorText(state.errorText!),
            ],
          ),
        );
      case FieldType.select:
        return FormField<String>(
          initialValue: value as String?,
          validator: _requiredCheck,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in field.options)
                    ChoiceChip(
                      label: Text(option),
                      selected: state.value == option,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      onSelected: (selected) {
                        final v = selected ? option : null;
                        state.didChange(v);
                        onChanged(v);
                      },
                    ),
                ],
              ),
              if (state.hasError) _ErrorText(state.errorText!),
            ],
          ),
        );
      case FieldType.date:
        return FormField<String>(
          initialValue: value as String?,
          validator: _requiredCheck,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                ),
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  state.value == null
                      ? 'Choisir une date'
                      : formatDay(DateTime.parse(state.value!)),
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: state.value == null
                        ? now
                        : DateTime.parse(state.value!),
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (picked == null) return;
                  final v = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                  ).toIso8601String().substring(0, 10);
                  state.didChange(v);
                  onChanged(v);
                },
              ),
              if (state.hasError) _ErrorText(state.errorText!),
            ],
          ),
        );
    }
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 4),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.error,
      ),
    ),
  );
}
