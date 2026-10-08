import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Joignabilité du serveur, vue par les requêtes de l'app.
class NetworkState {
  const NetworkState({this.online = true, this.lastOnlineAt});

  final bool online;

  /// Dernière réponse reçue du serveur : âge des données affichées hors ligne.
  final DateTime? lastOnlineAt;
}

class NetworkStatus extends Notifier<NetworkState> {
  static const _key = 'network.lastOnlineAt';
  DateTime? _savedAt;

  @override
  NetworkState build() {
    _restore();
    return const NetworkState();
  }

  Future<void> _restore() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null && state.lastOnlineAt == null) {
        state = NetworkState(
          online: state.online,
          lastOnlineAt: DateTime.parse(raw),
        );
      }
    } catch (_) {
      // Heure inconnue : le bandeau l'omet.
    }
  }

  /// Une réponse du serveur est arrivée.
  void reachable() {
    final now = DateTime.now();
    final last = state.lastOnlineAt;
    // État relu au plus une fois par minute quand tout va bien (pas de rafraîchissement
    // de l'affichage à chaque requête).
    if (!state.online || last == null || now.difference(last).inSeconds >= 60) {
      state = NetworkState(lastOnlineAt: now);
    }
    if (_savedAt == null || now.difference(_savedAt!).inSeconds >= 60) {
      _savedAt = now;
      SharedPreferences.getInstance()
          .then((p) => p.setString(_key, now.toIso8601String()))
          .catchError((_) => false);
    }
  }

  /// Pas de réponse du serveur (réseau absent ou serveur injoignable).
  void unreachable() {
    if (state.online) {
      state = NetworkState(online: false, lastOnlineAt: state.lastOnlineAt);
    }
  }
}

final networkProvider = NotifierProvider<NetworkStatus, NetworkState>(
  NetworkStatus.new,
);
