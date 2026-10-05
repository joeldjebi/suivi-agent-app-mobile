import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Écran de formulaire (style Réglages) : titre, champs groupés, « Enregistrer » en haut à droite.
/// Après un premier essai d'envoi, chaque champ se revalide à la saisie : l'erreur disparaît
/// dès que le champ est corrigé.
class FormScaffold extends StatefulWidget {
  const FormScaffold({
    super.key,
    required this.title,
    required this.formKey,
    required this.saving,
    required this.onSave,
    this.saveLabel = 'Enregistrer',
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final bool saving;
  final VoidCallback onSave;
  final String saveLabel;
  final List<Widget> children;

  @override
  State<FormScaffold> createState() => _FormScaffoldState();
}

class _FormScaffoldState extends State<FormScaffold> {
  var _submitted = false;

  void _save() {
    if (!_submitted) setState(() => _submitted = true);
    widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: widget.saving
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(onPressed: _save, child: Text(widget.saveLabel)),
          ),
        ],
      ),
      body: Form(
        key: widget.formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            0,
            Space.page,
            Space.xxxl,
          ),
          children: widget.children,
        ),
      ),
    );
  }
}

/// Champ sur une ligne de liste groupée : libellé à gauche, saisie à droite.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofocus = false,
    this.multiline = false,
  });

  final String label;
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Texte libre sur plusieurs lignes (la hauteur suit le contenu, jusqu'à 5 lignes).
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 2, Space.sm, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Text(label, style: text.bodyLarge?.medium),
            ),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              keyboardType: multiline ? TextInputType.multiline : keyboardType,
              minLines: 1,
              maxLines: multiline ? 5 : 1,
              obscureText: obscure,
              autofillHints: autofillHints,
              textCapitalization: textCapitalization,
              textInputAction: multiline
                  ? TextInputAction.newline
                  : textInputAction,
              onFieldSubmitted: onSubmitted,
              autofocus: autofocus,
              autocorrect: false,
              style: text.bodyLarge,
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
