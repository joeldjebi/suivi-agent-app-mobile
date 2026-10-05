import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';

/// Adresse des tuiles OpenStreetMap, remplaçable au build par un serveur dédié :
/// --dart-define=TILE_URL=...
const _osmUrl = String.fromEnvironment(
  'TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// Styles de carte, tous issus des données OpenStreetMap.
enum MapStyle {
  standard('Standard', Icons.map_outlined),
  sobre('Sobre', Icons.filter_b_and_w_rounded),
  sombre('Sombre', Icons.dark_mode_outlined),
  humanitaire('Humanitaire', Icons.volunteer_activism_outlined);

  const MapStyle(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Rendu « Humanitaire » d'OpenStreetMap France (HOT) : routes et lieux utiles
  /// sur le terrain mieux mis en avant.
  String get url => this == MapStyle.humanitaire
      ? 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png'
      : _osmUrl;

  String get attribution => this == MapStyle.humanitaire
      ? '© les contributeurs d’OpenStreetMap · OSM France'
      : '© les contributeurs d’OpenStreetMap';

  /// Sobre et Sombre : les tuiles standard, retouchées sur le téléphone.
  TileBuilder? get tileBuilder => switch (this) {
    MapStyle.sobre => (context, tile, _) => ColorFiltered(
      colorFilter: _grayscale,
      child: tile,
    ),
    MapStyle.sombre => darkModeTileBuilder,
    _ => null,
  };
}

/// Niveaux de gris éclaircis : les zones et les agents ressortent.
const _grayscale = ColorFilter.matrix([
  0.2126 * 0.85, 0.7152 * 0.85, 0.0722 * 0.85, 0, 30, //
  0.2126 * 0.85, 0.7152 * 0.85, 0.0722 * 0.85, 0, 30, //
  0.2126 * 0.85, 0.7152 * 0.85, 0.0722 * 0.85, 0, 30, //
  0, 0, 0, 1, 0,
]);

/// Réglages des cartes, gardés sur le téléphone.
class MapPrefs {
  const MapPrefs({
    this.chosenStyle,
    this.showZones = true,
    this.showNames = false,
    this.alertsOnly = false,
  });

  /// Style choisi ; vide : il suit le thème du téléphone (Standard, ou Sombre la nuit).
  final MapStyle? chosenStyle;
  final bool showZones;
  final bool showNames;
  final bool alertsOnly;

  MapStyle styleFor(Brightness brightness) =>
      chosenStyle ??
      (brightness == Brightness.dark ? MapStyle.sombre : MapStyle.standard);

  MapPrefs copyWith({
    MapStyle? style,
    bool? showZones,
    bool? showNames,
    bool? alertsOnly,
  }) => MapPrefs(
    chosenStyle: style ?? chosenStyle,
    showZones: showZones ?? this.showZones,
    showNames: showNames ?? this.showNames,
    alertsOnly: alertsOnly ?? this.alertsOnly,
  );
}

class MapPrefsController extends Notifier<MapPrefs> {
  static const _prefix = 'map.';

  @override
  MapPrefs build() {
    _restore();
    return const MapPrefs();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = MapPrefs(
        chosenStyle: MapStyle.values
            .where((s) => s.name == p.getString('${_prefix}style'))
            .firstOrNull,
        showZones: p.getBool('${_prefix}zones') ?? true,
        showNames: p.getBool('${_prefix}names') ?? false,
        alertsOnly: p.getBool('${_prefix}alerts') ?? false,
      );
    } catch (_) {
      // Réglages illisibles : on garde les valeurs par défaut.
    }
  }

  Future<void> update(MapPrefs next) async {
    state = next;
    try {
      final p = await SharedPreferences.getInstance();
      final style = next.chosenStyle;
      if (style == null) {
        await p.remove('${_prefix}style');
      } else {
        await p.setString('${_prefix}style', style.name);
      }
      await p.setBool('${_prefix}zones', next.showZones);
      await p.setBool('${_prefix}names', next.showNames);
      await p.setBool('${_prefix}alerts', next.alertsOnly);
    } catch (_) {
      // Sans stockage, le réglage vaut pour la session en cours.
    }
  }
}

final mapPrefsProvider = NotifierProvider<MapPrefsController, MapPrefs>(
  MapPrefsController.new,
);

/// Panneau « Carte » : style et, pour la carte de l'équipe, éléments affichés.
Future<void> showMapOptions(
  BuildContext context, {
  bool layers = true,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  // Fond gris : les cartes blanches ressortent, comme dans les réglages iOS.
  backgroundColor: Theme.of(context).colorScheme.surface,
  builder: (_) => _MapOptionsSheet(layers: layers),
);

class _MapOptionsSheet extends ConsumerWidget {
  const _MapOptionsSheet({required this.layers});

  /// Zones, noms des agents, alertes : carte de l'équipe seulement.
  final bool layers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(mapPrefsProvider);
    final controller = ref.read(mapPrefsProvider.notifier);
    final text = Theme.of(context).textTheme;

    Widget toggle(
      String title,
      String subtitle,
      bool value,
      IconData icon,
      Color color,
      ValueChanged<bool> onChanged,
    ) => ListRow(
      leading: IconSquircle(icon: icon, color: color, size: 28, solid: true),
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
      chevron: false,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Text('Carte', style: text.headlineSmall),
          ),
          const SectionHeader('Style'),
          Row(
            children: [
              for (final style in MapStyle.values) ...[
                if (style != MapStyle.values.first)
                  const SizedBox(width: Space.sm),
                Expanded(
                  child: _StyleTile(
                    style: style,
                    selected:
                        prefs.styleFor(Theme.of(context).brightness) == style,
                    onTap: () =>
                        controller.update(prefs.copyWith(style: style)),
                  ),
                ),
              ],
            ],
          ),
          if (layers)
            GroupedList(
              header: 'Afficher',
              children: [
                toggle(
                  'Zones',
                  'Contours et noms des zones',
                  prefs.showZones,
                  Icons.pentagon_outlined,
                  Theme.of(context).colorScheme.primary,
                  (v) => controller.update(prefs.copyWith(showZones: v)),
                ),
                toggle(
                  'Noms des agents',
                  'Sous chaque pastille',
                  prefs.showNames,
                  Icons.badge_outlined,
                  const Color(0xFF3B82F6),
                  (v) => controller.update(prefs.copyWith(showNames: v)),
                ),
                toggle(
                  'Alertes seulement',
                  'Hors zone, signal perdu, position simulée',
                  prefs.alertsOnly,
                  Icons.warning_amber_rounded,
                  const Color(0xFFE5484D),
                  (v) => controller.update(prefs.copyWith(alertsOnly: v)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final MapStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Style ${style.label}',
      excludeSemantics: true,
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        border: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
        child: Column(
          children: [
            Icon(
              style.icon,
              size: 24,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: Space.xs),
            Text(
              style.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(
                fontSize: 11.5,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
