import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/form_rows.dart';

/// Prénom, nom, email.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(
    text: ref.read(meProvider).firstName,
  );
  late final _last = TextEditingController(text: ref.read(meProvider).lastName);
  late final _email = TextEditingController(text: ref.read(meProvider).email);
  bool _saving = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile(
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            email: _email.text.trim(),
          );
      if (!mounted) return;
      showMessage(context, 'Profil mis à jour');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        v == null || v.trim().isEmpty ? 'Champ obligatoire' : null;
    return FormScaffold(
      title: 'Informations',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      children: [
        GroupedList(
          header: 'Identité',
          indent: Space.lg,
          footer:
              'Votre nom apparaît auprès de votre responsable et de votre structure.',
          children: [
            FieldRow(
              label: 'Prénom',
              controller: _first,
              validator: required,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.givenName],
            ),
            FieldRow(
              label: 'Nom',
              controller: _last,
              validator: required,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.familyName],
            ),
          ],
        ),
        GroupedList(
          header: 'Contact',
          indent: Space.lg,
          children: [
            FieldRow(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              validator: (v) =>
                  v == null ||
                      !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
                  ? 'Email invalide'
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Nouveau mot de passe : les autres appareils sont déconnectés, pas celui-ci.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  static const _minLength = 8;

  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Les indications se mettent à jour pendant la saisie.
    _next.addListener(_refresh);
    _confirm.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(authProvider.notifier)
          .changePassword(_current.text, _next.text);
      if (!mounted) return;
      showMessage(
        context,
        'Mot de passe modifié. Vos autres appareils ont été déconnectés.',
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(
          context,
          e.status == 401 ? 'Mot de passe actuel incorrect' : e.message,
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final longEnough = _next.text.length >= _minLength;
    final same = _next.text.isNotEmpty && _next.text == _confirm.text;
    final different = _next.text.isNotEmpty && _next.text != _current.text;

    return FormScaffold(
      title: 'Mot de passe',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      children: [
        GroupedList(
          header: 'Mot de passe actuel',
          indent: Space.lg,
          children: [
            FieldRow(
              label: 'Actuel',
              controller: _current,
              obscure: true,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              validator: (v) => v == null || v.isEmpty
                  ? 'Saisissez votre mot de passe actuel'
                  : null,
            ),
          ],
        ),
        GroupedList(
          header: 'Nouveau mot de passe',
          indent: Space.lg,
          children: [
            FieldRow(
              label: 'Nouveau',
              controller: _next,
              obscure: true,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) => v == null || v.length < _minLength
                  ? '$_minLength caractères minimum'
                  : v == _current.text
                  ? 'Choisissez un mot de passe différent'
                  : null,
            ),
            FieldRow(
              label: 'Confirmer',
              controller: _confirm,
              obscure: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              validator: (v) =>
                  v != _next.text ? 'Les deux saisies sont différentes' : null,
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        _Rule(ok: longEnough, label: '$_minLength caractères minimum'),
        _Rule(ok: different, label: 'Différent du mot de passe actuel'),
        _Rule(ok: same, label: 'Les deux saisies sont identiques'),
        const SizedBox(height: Space.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          child: Text(
            'Vos autres appareils seront déconnectés. Vous restez connecté sur celui-ci.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ok
        ? toneColor(context, Tone.success)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 3),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
