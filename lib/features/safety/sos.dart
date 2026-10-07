import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../profile/my_team.dart';

/// Alerte sécurité de l'agent : en cours, en cours d'envoi, ou en attente du réseau.
class SosState {
  const SosState({
    this.alert,
    this.sending = false,
    this.queued = false,
    this.message,
  });

  final AgentAlert? alert;
  final bool sending;

  /// Sans réseau : l'alerte partira dès son retour (nouvel essai toutes les 15 s).
  final bool queued;
  final String? message;

  bool get active => alert != null || sending || queued;
}

class SosController extends Notifier<SosState> {
  Timer? _retry;

  @override
  SosState build() {
    // Un autre compte sur le téléphone : on repart de zéro.
    ref.watch(authProvider.select((a) => a is SignedIn ? a.me.id : null));
    ref.onDispose(() => _retry?.cancel());
    // Après l'initialisation de l'état.
    Future.microtask(refresh);
    return const SosState();
  }

  /// Relit l'alerte en cours (prise en charge, clôture).
  Future<void> refresh() async {
    if (state.sending || state.queued) return;
    try {
      final alert = await ref.read(repositoryProvider).currentSos();
      state = SosState(alert: alert);
    } catch (_) {
      // Sans réseau : l'état connu reste affiché.
    }
  }

  /// Déclenche l'alerte (ou envoie la position actuelle si elle est déjà en cours).
  Future<void> raise({String? message}) async {
    final text = message ?? state.message;
    state = SosState(alert: state.alert, sending: true, message: text);
    final position = await ref.read(trackerProvider).lastKnown();
    try {
      final alert = await ref
          .read(repositoryProvider)
          .raiseSos(
            lat: position?.latitude,
            lng: position?.longitude,
            accuracy: position?.accuracy,
            message: text,
          );
      _retry?.cancel();
      _retry = null;
      state = SosState(alert: alert, message: text);
    } on ApiException catch (e) {
      if (!e.isNetwork && e.status != null && e.status! < 500) {
        state = SosState(alert: state.alert, message: text);
        rethrow;
      }
      state = SosState(alert: state.alert, queued: true, message: text);
      _retry ??= Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(raise()),
      );
    }
  }

  /// Fausse alerte.
  Future<void> cancel() async {
    _retry?.cancel();
    _retry = null;
    if (state.alert != null) await ref.read(repositoryProvider).cancelSos();
    state = const SosState();
  }

  /// Déconnexion.
  void clear() {
    _retry?.cancel();
    _retry = null;
    state = const SosState();
  }
}

final sosProvider = NotifierProvider<SosController, SosState>(
  SosController.new,
);

/// Bouton d'alerte sécurité de « Ma journée » : maintenu 2 secondes pour éviter un
/// déclenchement par erreur. Alerte en cours : accès direct à son écran.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({super.key});

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton>
    with SingleTickerProviderStateMixin {
  late final _hold = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..addStatusListener(_onHold);

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _onHold(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    HapticFeedback.heavyImpact();
    _hold.reset();
    unawaited(_trigger());
  }

  Future<void> _trigger() async {
    unawaited(context.push('/sos'));
    try {
      await ref.read(sosProvider.notifier).raise();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  /// Lecteur d'écran : confirmation à la place du maintien.
  Future<void> _confirm() async {
    final ok = await confirmSheet(
      context,
      title: 'Déclencher une alerte sécurité ?',
      message:
          'Votre chef et votre structure seront prévenus immédiatement, avec votre position.',
      confirmLabel: 'Alerter',
      destructive: true,
    );
    if (ok) await _trigger();
  }

  @override
  Widget build(BuildContext context) {
    final sos = ref.watch(sosProvider);
    final danger = toneColor(context, Tone.danger);
    final text = Theme.of(context).textTheme;

    if (sos.active) {
      return Padding(
        padding: const EdgeInsets.only(top: Space.lg),
        child: SurfaceCard(
          color: danger,
          onTap: () => context.push('/sos'),
          semanticLabel: 'Alerte sécurité en cours. Ouvrir',
          child: Row(
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  sos.queued
                      ? 'Alerte en attente du réseau'
                      : 'Alerte sécurité en cours',
                  style: text.titleSmall?.copyWith(color: Colors.white),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: Semantics(
        button: true,
        label: 'Alerte sécurité',
        hint: 'Prévient votre chef et votre structure',
        onTap: _confirm,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            _hold.forward();
          },
          onTapUp: (_) => _hold.reverse(),
          onTapCancel: () => _hold.reverse(),
          child: AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: Color.lerp(
                  danger.withValues(alpha: 0.08),
                  danger.withValues(alpha: 0.22),
                  _hold.value,
                ),
                borderRadius: BorderRadius.circular(Radii.card),
                border: Border.all(color: danger.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: _hold.value,
                          strokeWidth: 3,
                          color: danger,
                          backgroundColor: danger.withValues(alpha: 0.15),
                        ),
                        Icon(Icons.sos_rounded, color: danger, size: 22),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alerte sécurité',
                          style: text.titleSmall?.copyWith(color: danger),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _hold.value > 0
                              ? 'Maintenez encore…'
                              : 'En danger ? Maintenez 2 secondes pour prévenir votre chef et votre structure.',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Écran de l'alerte en cours : qui est prévenu, qui s'en occupe, appels directs,
/// position à jour, annulation d'une fausse alerte.
class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  Future<void> _call(String phone) => launchUrl(
    Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), '')),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sos = ref.watch(sosProvider);
    final alert = sos.alert;
    final danger = toneColor(context, Tone.danger);
    final text = Theme.of(context).textTheme;
    final leads = ref.watch(myTeamProvider).value?.leads ?? const [];
    final lead = leads.where((l) => l.phone != null).firstOrNull;
    final support = ref.watch(brandingProvider).supportPhone;

    final title = sos.sending && alert == null
        ? 'Envoi de l’alerte…'
        : sos.queued
        ? 'Pas de réseau'
        : alert != null
        ? 'Alerte envoyée'
        : 'Aucune alerte en cours';
    final subtitle = sos.queued
        ? 'L’alerte partira dès le retour du réseau. Appelez directement si vous le pouvez.'
        : alert != null
        ? 'Votre chef et votre structure sont prévenus.'
        : sos.sending
        ? 'Votre position est jointe à l’alerte.'
        : 'Votre alerte a été close ou annulée.';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: danger,
        foregroundColor: Colors.white,
        title: const Text('Alerte sécurité'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sosProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.xl,
            Space.page,
            Space.xxxl,
          ),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: sos.sending && alert == null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: CircularProgressIndicator(color: danger),
                      )
                    : Icon(
                        sos.queued
                            ? Icons.wifi_off_rounded
                            : alert != null
                            ? Icons.sos_rounded
                            : Icons.verified_user_outlined,
                        size: 48,
                        color: alert != null || sos.queued
                            ? danger
                            : toneColor(context, Tone.success),
                      ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(title, textAlign: TextAlign.center, style: text.headlineSmall),
            const SizedBox(height: Space.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (alert?.acknowledgedBy case final by?) ...[
              const SizedBox(height: Space.lg),
              InfoBanner(
                icon: Icons.pan_tool_alt_outlined,
                tone: Tone.success,
                message:
                    '$by s’en occupe${alert!.note == null ? '' : ' : « ${alert.note} »'}',
              ),
            ],
            if (alert != null) ...[
              const SizedBox(height: Space.lg),
              GroupedList(
                children: [
                  ListRow(
                    leading: Icon(Icons.schedule_rounded, color: danger),
                    title: 'Envoyée à ${formatTime(alert.startedAt)}',
                  ),
                  ListRow(
                    leading: Icon(
                      alert.position != null
                          ? Icons.location_on_rounded
                          : Icons.location_off_outlined,
                      color: danger,
                    ),
                    title: alert.position != null
                        ? 'Position transmise'
                        : 'Position indisponible',
                    subtitle: alert.data['accuracy'] is num
                        ? 'À ${(alert.data['accuracy'] as num).round()} m près'
                        : null,
                  ),
                ],
              ),
            ],
            const SizedBox(height: Space.xl),
            if (lead != null) ...[
              PillButton(
                label: 'Appeler ${lead.firstName} (mon chef)',
                icon: Icons.call_rounded,
                style: PillStyle.danger,
                onPressed: () => _call(lead.phone!),
              ),
              const SizedBox(height: Space.sm),
            ],
            if (support != null) ...[
              PillButton(
                label: 'Appeler la structure',
                icon: Icons.support_agent_rounded,
                style: PillStyle.tonal,
                onPressed: () => _call(support),
              ),
              const SizedBox(height: Space.sm),
            ],
            if (alert != null || sos.queued) ...[
              PillButton(
                label: 'Envoyer ma position actuelle',
                icon: Icons.my_location_rounded,
                style: PillStyle.outline,
                loading: sos.sending,
                onPressed: sos.sending
                    ? null
                    : () async {
                        try {
                          await ref.read(sosProvider.notifier).raise();
                          if (context.mounted) {
                            showMessage(context, 'Position envoyée');
                          }
                        } on ApiException catch (e) {
                          if (context.mounted) {
                            showMessage(context, e.message, error: true);
                          }
                        }
                      },
              ),
              const SizedBox(height: Space.xl),
              TextButton(
                onPressed: () async {
                  final ok = await confirmSheet(
                    context,
                    title: 'Annuler l’alerte ?',
                    message:
                        'Votre chef et votre structure seront informés qu’il s’agit d’une fausse alerte.',
                    confirmLabel: 'Annuler l’alerte',
                    destructive: true,
                  );
                  if (!ok) return;
                  try {
                    await ref.read(sosProvider.notifier).cancel();
                    if (context.mounted) {
                      showMessage(context, 'Alerte annulée');
                      context.pop();
                    }
                  } on ApiException catch (e) {
                    if (context.mounted) {
                      showMessage(context, e.message, error: true);
                    }
                  }
                },
                child: const Text('Fausse alerte ? Annuler l’alerte'),
              ),
            ] else if (!sos.sending)
              PillButton(
                label: 'Retour',
                style: PillStyle.tonal,
                onPressed: () => context.pop(),
              ),
          ],
        ),
      ),
    );
  }
}
