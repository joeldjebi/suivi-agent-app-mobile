import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import 'day_controller.dart';

/// Choix de la zone : zones du groupe (ou de la structure), places restantes ; les zones pleines
/// ne sont pas sélectionnables (RG-03, RG-06).
Future<void> showZonePicker(BuildContext context, {String? currentZoneId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.88,
      child: _ZonePicker(currentZoneId: currentZoneId),
    ),
  );
}

class _ZonePicker extends ConsumerStatefulWidget {
  const _ZonePicker({this.currentZoneId});

  final String? currentZoneId;

  @override
  ConsumerState<_ZonePicker> createState() => _ZonePickerState();
}

class _ZonePickerState extends ConsumerState<_ZonePicker> {
  String? _sending;

  Future<void> _choose(Zone zone) async {
    tapFeedback();
    setState(() => _sending = zone.id);
    try {
      final request = await ref.read(dayProvider.notifier).chooseZone(zone.id);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
        context,
        request.status == RequestStatus.approved
            ? 'Zone ${zone.name} confirmée'
            : 'Demande envoyée : votre responsable doit valider la zone ${zone.name}',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message, error: true);
      ref.invalidate(availableZonesProvider);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final zones = ref.watch(availableZonesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xxl, 0, Space.xxl, Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Où travaillez-vous aujourd’hui ?', style: text.titleLarge),
              const SizedBox(height: Space.xs),
              Text(
                'Choisissez une zone qui a encore des places.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: zones.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _Message(
              icon: Icons.wifi_off_rounded,
              text: ApiException.from(e).message,
              action: TextButton(
                onPressed: () => ref.invalidate(availableZonesProvider),
                child: const Text('Réessayer'),
              ),
            ),
            data: (data) {
              if (data.groupMissing) {
                return const _Message(
                  icon: Icons.group_off_outlined,
                  text:
                      'Vous n’êtes rattaché à aucun groupe. Contactez votre responsable pour obtenir des zones.',
                );
              }
              if (data.zones.isEmpty) {
                return const _Message(
                  icon: Icons.map_outlined,
                  text: 'Aucune zone ne vous est attribuée pour le moment.',
                );
              }
              return RefreshIndicator(
                onRefresh: () => ref.refresh(availableZonesProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.xxl,
                  ),
                  itemCount: data.zones.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (_, i) {
                    final zone = data.zones[i];
                    final current = zone.id == widget.currentZoneId;
                    return _ZoneTile(
                      zone: zone,
                      current: current,
                      sending: _sending == zone.id,
                      onTap: zone.isFull || current || _sending != null
                          ? null
                          : () => _choose(zone),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile({
    required this.zone,
    required this.current,
    required this.sending,
    required this.onTap,
  });

  final Zone zone;
  final bool current;
  final bool sending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final full = zone.isFull && !current;
    final capacity = zone.capacity;
    final taken = capacity == null ? 0 : capacity - (zone.placesLeft ?? 0);
    final places = capacity == null
        ? 'Places illimitées'
        : zone.isFull
        ? 'Complète'
        : '${zone.placesLeft} place${zone.placesLeft! > 1 ? 's' : ''} libre${zone.placesLeft! > 1 ? 's' : ''} sur $capacity';
    final barColor = zone.isFull
        ? scheme.error
        : (zone.placesLeft ?? 9) <= 1
        ? toneColor(context, Tone.warning)
        : toneColor(context, Tone.success);

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: '${zone.name}, $places${current ? ', votre zone actuelle' : ''}',
      excludeSemantics: true,
      child: Opacity(
        opacity: full ? 0.5 : 1,
        child: SurfaceCard(
          onTap: onTap,
          radius: Radii.tile,
          padding: const EdgeInsets.all(Space.lg),
          border: current ? BorderSide(color: scheme.primary, width: 2) : null,
          child: Row(
            children: [
              IconSquircle(
                icon: full ? Icons.block_rounded : Icons.place_rounded,
                size: 40,
                color: full ? scheme.error : null,
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            zone.name,
                            style: text.titleMedium?.copyWith(fontSize: 17),
                          ),
                        ),
                        if (zone.sensitive) ...[
                          const SizedBox(width: Space.sm),
                          Icon(
                            Icons.verified_user_rounded,
                            size: 16,
                            color: toneColor(context, Tone.warning),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    if (capacity != null) ...[
                      // Jauge des places : chaque segment est une place.
                      Row(
                        children: [
                          for (var p = 0; p < capacity && p < 12; p++)
                            Expanded(
                              child: Container(
                                height: 6,
                                margin: const EdgeInsets.only(right: 3),
                                decoration: BoxDecoration(
                                  color: p < taken
                                      ? barColor
                                      : barColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                    Text(
                      places + (zone.sensitive ? ' · validation possible' : ''),
                      style: text.bodySmall?.copyWith(
                        color: zone.isFull
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              if (sending)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (current)
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 28,
                )
              else if (!zone.isFull)
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconSquircle(icon: icon, size: 64),
            const SizedBox(height: Space.lg),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}
