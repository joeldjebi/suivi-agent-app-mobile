import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_lock.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// Masque l'app d'un écran de déverrouillage tant que Face ID / l'empreinte n'a pas été
/// vérifié (connecté seulement : l'écran de connexion n'est jamais verrouillé).
class LockGate extends ConsumerWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    final signedIn = ref.watch(authProvider.select((a) => a is SignedIn));
    return Stack(
      children: [
        child,
        if (locked && signedIn) const Positioned.fill(child: _LockScreen()),
      ],
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen();

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  String _method = 'Face ID / empreinte';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final label = await ref.read(biometricsProvider).label();
      if (mounted) setState(() => _method = label);
      unawaited(_unlock());
    });
  }

  Future<void> _unlock() async {
    final ok = await ref.read(appLockProvider.notifier).unlock();
    if (!ok && mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final branding = ref.watch(brandingProvider);
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            children: [
              const Spacer(),
              const IconSquircle(icon: Icons.lock_rounded, size: 72),
              const SizedBox(height: Space.lg),
              Text(
                branding.displayName,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: Space.xs),
              Text(
                _failed
                    ? 'Vérification annulée ou refusée.'
                    : 'Application verrouillée',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              PillButton(
                label: 'Déverrouiller avec $_method',
                icon: Icons.fingerprint_rounded,
                onPressed: _unlock,
              ),
              const SizedBox(height: Space.sm),
              TextButton(
                onPressed: () => ref.read(authProvider.notifier).logout(),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profil : activer le déverrouillage par Face ID / empreinte (si le téléphone le permet).
class BiometricSection extends ConsumerStatefulWidget {
  const BiometricSection({super.key});

  @override
  ConsumerState<BiometricSection> createState() => _BiometricSectionState();
}

class _BiometricSectionState extends ConsumerState<BiometricSection> {
  bool? _available;
  String _method = 'empreinte';

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final bio = ref.read(biometricsProvider);
    final available = await bio.available();
    final label = available ? await bio.label() : _method;
    if (mounted) {
      setState(() {
        _available = available;
        _method = label;
      });
    }
  }

  Future<void> _toggle(bool on) async {
    final lock = ref.read(appLockProvider.notifier);
    if (!on) return lock.disable();
    final ok = await lock.enable();
    if (!ok && mounted) {
      showMessage(
        context,
        'Vérification non aboutie : le déverrouillage n’est pas activé.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_available != true) return const SizedBox.shrink();
    final enabled = ref.watch(appLockProvider.select((s) => s.enabled));
    return GroupedList(
      header: 'Sécurité',
      footer:
          'L’app demande $_method à son ouverture et après 2 minutes en arrière-plan. Le code du téléphone reste possible en secours.',
      children: [
        ListRow(
          leading: const IconSquircle(
            icon: Icons.fingerprint_rounded,
            color: Color(0xFF10B981),
            size: 28,
            solid: true,
          ),
          title: 'Déverrouiller avec $_method',
          trailing: Switch.adaptive(value: enabled, onChanged: _toggle),
          onTap: () => _toggle(!enabled),
        ),
      ],
    );
  }
}
