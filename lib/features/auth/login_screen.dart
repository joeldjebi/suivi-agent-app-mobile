import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/phone_format.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// Connexion avec le numéro et le mot de passe fournis par la structure.
/// Pas de création de compte : c'est la structure qui crée les accès.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(_phone.text, _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);
    final notice = auth is SignedOut ? auth.message : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.xxl,
              Space.xxl,
              Space.xxl,
              Space.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(Radii.control),
                          ),
                          child: Icon(
                            Icons.place_rounded,
                            color: scheme.onPrimary,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xxl),
                      Text('Connexion', style: text.headlineMedium),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Avec le numéro de téléphone et le mot de passe fournis par votre structure.',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Space.xxl),
                      if (notice != null && _error == null) ...[
                        InfoBanner(
                          icon: Icons.lock_clock_outlined,
                          message: notice,
                        ),
                        const SizedBox(height: Space.lg),
                      ],
                      Text('Numéro de téléphone', style: text.labelLarge),
                      const SizedBox(height: Space.sm),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [
                          AutofillHints.telephoneNumber,
                          AutofillHints.username,
                        ],
                        inputFormatters: [PhoneInputFormatter()],
                        decoration: const InputDecoration(
                          hintText: '07 00 00 00 00',
                          prefixIcon: Icon(
                            Icons.phone_iphone_outlined,
                            size: 20,
                          ),
                        ),
                        validator: (v) => v == null || !isPlausiblePhone(v)
                            ? 'Saisissez votre numéro de téléphone'
                            : null,
                      ),
                      const SizedBox(height: Space.lg),
                      Text('Mot de passe', style: text.labelLarge),
                      const SizedBox(height: Space.sm),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Afficher le mot de passe'
                                : 'Masquer le mot de passe',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Saisissez votre mot de passe'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: Space.lg),
                        InfoBanner(
                          icon: Icons.error_outline_rounded,
                          message: _error!,
                          tone: Tone.danger,
                        ),
                      ],
                      const SizedBox(height: Space.xxl),
                      PillButton(
                        label: 'Se connecter',
                        loading: _loading,
                        onPressed: _submit,
                      ),
                      const SizedBox(height: Space.lg),
                      Text(
                        'Mot de passe oublié ou pas encore de compte ? Votre structure crée et réinitialise les accès.',
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
