import 'app_lock.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'branding.dart';
import 'database.dart';
import 'day_timer.dart';
import 'field_photo.dart';
import 'form_drafts.dart';
import 'local_alerts.dart';
import 'models.dart';
import 'push.dart';
import 'repository.dart';
import 'session.dart';
import 'sync.dart';
import 'tracking.dart';
import 'zone_guard.dart';

final sessionProvider = Provider<SessionStore>((ref) => SessionStore());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final apiProvider = Provider<ApiClient>((ref) {
  final api = ApiClient(ref.watch(sessionProvider));
  // Session expirée (jeton révoqué, compte désactivé) : retour à l'écran de connexion.
  api.onSessionExpired = () => ref.read(authProvider.notifier).expire();
  api.onPlanChanged = () => ref.read(authProvider.notifier).refresh();
  return api;
});

final repositoryProvider = Provider<Repository>(
  (ref) => Repository(ref.watch(apiProvider)),
);

final trackerProvider = ChangeNotifierProvider<LocationTracker>(
  (ref) => LocationTracker(ref.watch(databaseProvider)),
);

/// Alertes affichées sur le téléphone (remplacées dans les tests).
final alertSinkProvider = Provider<AlertSink>((ref) => LocalAlerts());

/// Surveillance de la zone du jour, sur le téléphone.
final zoneGuardProvider = ChangeNotifierProvider<ZoneGuard>(
  (ref) => ZoneGuard(ref.watch(alertSinkProvider)),
);

final syncProvider = ChangeNotifierProvider<SyncService>((ref) {
  final alerts = ref.watch(alertSinkProvider);
  final sync = SyncService(
    ref.watch(databaseProvider),
    ref.watch(repositoryProvider),
    // Formulaire refusé pendant un envoi en arrière-plan : l'agent est prévenu.
    onRejected: (row, error) => unawaited(
      alerts.show(
        row.clientId.hashCode & 0x7fffffff,
        'Formulaire refusé',
        '${row.missionTitle} : ${error.message}',
      ),
    ),
  );
  return sync;
});

/// Appareil photo des formulaires (remplacé dans les tests).
final photoCaptureProvider = Provider<PhotoCapture>(
  (ref) => CameraPhotoCapture(),
);

/// Chrono de la journée sur l'écran verrouillé (inactif pendant les tests automatisés).
final dayTimerProvider = Provider<DayTimer>(
  (ref) => Platform.environment.containsKey('FLUTTER_TEST')
      ? const NoDayTimer()
      : DeviceDayTimer(),
);

final pendingCountProvider = StreamProvider<int>(
  (ref) => ref.watch(databaseProvider).watchPendingCount(),
);

final brandingCacheProvider = Provider<BrandingCache>((ref) => BrandingCache());

// ---------------------------------------------------------------------------
// Session de l'agent

sealed class AuthState {
  const AuthState();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class SignedOut extends AuthState {
  const SignedOut({this.message});

  /// Raison affichée sur l'écran de connexion (ex. session expirée).
  final String? message;
}

class SignedIn extends AuthState {
  const SignedIn(this.me, this.branding);

  final Me me;
  final Branding branding;
}

class AuthController extends Notifier<AuthState> {
  static const _meKey = 'me.json';

  @override
  AuthState build() => const AuthLoading();

  SessionStore get _session => ref.read(sessionProvider);
  Repository get _repo => ref.read(repositoryProvider);

  /// Reprise de session au lancement, y compris sans réseau (profil et apparence en cache).
  Future<void> restore() async {
    await _session.load();
    if (await _session.refreshToken() == null) {
      state = const SignedOut();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cachedMe = prefs.getString(_meKey);
    final cachedBranding = await ref.read(brandingCacheProvider).read();
    try {
      final me = await _repo.me();
      state = SignedIn(me, cachedBranding ?? Branding.defaults);
      await _refreshBranding(cachedBranding);
    } on ApiException catch (e) {
      if (e.isNetwork && cachedMe != null) {
        state = SignedIn(
          Me.fromJson(jsonDecode(cachedMe) as Map<String, dynamic>),
          cachedBranding ?? Branding.defaults,
        );
      } else {
        await _wipe();
        state = const SignedOut();
      }
    }
  }

  /// Connexion avec le numéro et le mot de passe fournis par la structure.
  /// Ouverte aux agents et aux chefs d'équipe, chacun avec ses écrans.
  Future<void> login(String phone, String password) async {
    final tokens = await _repo.login(phone.trim(), password);
    await _session.save(
      access: tokens['accessToken'] as String,
      refresh: tokens['refreshToken'] as String,
    );
    final raw = await _repo.api.get<Map<String, dynamic>>('/auth/me');
    final me = Me.fromJson(raw);
    if (!me.isAgent && !me.isTeamLead) {
      await _session.clear();
      throw ApiException(
        'Cette application est réservée aux agents et aux chefs d’équipe. Les administrateurs utilisent la plateforme web.',
        code: 'NOT_ALLOWED',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_meKey, jsonEncode(raw));
    final branding = await _refreshBranding(null) ?? Branding.defaults;
    state = SignedIn(me, branding);
  }

  /// Télécharge l'apparence de la structure (et son logo s'il a changé).
  Future<Branding?> _refreshBranding(Branding? cached) async {
    try {
      final json = await _repo.branding();
      Uint8List? logo;
      if (json['logoUrl'] != null) {
        logo =
            cached != null &&
                cached.version == json['version'] &&
                cached.logo != null
            ? cached.logo
            : Uint8List.fromList(await _repo.logoBytes());
      }
      final branding = Branding.fromJson(json, logo: logo);
      await ref.read(brandingCacheProvider).write(branding);
      if (state case SignedIn(:final me)) state = SignedIn(me, branding);
      return branding;
    } on ApiException {
      return cached;
    } catch (_) {
      return cached;
    }
  }

  // Profil : chaque mise à jour remplace le profil affiché et son cache hors ligne.

  Future<void> _applyMe(Map<String, dynamic> raw) async {
    final me = Me.fromJson(raw);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_meKey, jsonEncode(raw));
    if (state case SignedIn(:final branding)) state = SignedIn(me, branding);
  }

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
    required String email,
  }) async => _applyMe(
    await _repo.updateProfile(
      firstName: firstName,
      lastName: lastName,
      email: email,
    ),
  );

  /// Les autres appareils sont déconnectés ; celui-ci garde sa session avec les nouveaux jetons.
  Future<void> changePassword(String current, String next) async {
    final tokens = await _repo.changePassword(current, next);
    await _session.save(
      access: tokens['accessToken'] as String,
      refresh: tokens['refreshToken'] as String,
    );
  }

  Future<void> setAvatar(List<int> bytes) async =>
      _applyMe(await _repo.uploadAvatar(bytes));

  Future<void> removeAvatar() async => _applyMe(await _repo.deleteAvatar());

  DateTime? _refreshedAt;

  /// Relit le profil (formule, fonctionnalités, abonnement) et l'apparence, sans bloquer :
  /// au retour dans l'app et quand l'API signale un changement de formule. Les onglets et
  /// les écrans s'adaptent aussitôt. Au plus une fois toutes les 10 secondes.
  Future<void> refresh() async {
    if (state is! SignedIn) return;
    final now = DateTime.now();
    if (_refreshedAt != null &&
        now.difference(_refreshedAt!) < const Duration(seconds: 10)) {
      return;
    }
    _refreshedAt = now;
    try {
      await _applyMe(await _repo.meJson());
      if (state case SignedIn(:final branding)) {
        await _refreshBranding(branding);
      }
    } catch (_) {
      // Hors connexion : le profil en cache reste valable.
    }
  }

  Future<void> reloadBranding() async {
    if (state case SignedIn(:final branding)) await _refreshBranding(branding);
  }

  Future<void> logout() async {
    // Avant la fin de session : ce téléphone ne recevra plus les notifications du compte.
    await ref.read(pushProvider).unregister();
    final refresh = await _session.refreshToken();
    if (refresh != null) {
      try {
        await _repo.logout(refresh);
      } catch (_) {
        // Hors connexion : le jeton expirera de lui-même.
      }
    }
    await _wipe();
    state = const SignedOut();
  }

  void expire() {
    if (state is! SignedIn) return;
    _wipe();
    state = const SignedOut(
      message: 'Votre session a expiré. Reconnectez-vous.',
    );
  }

  Future<void> _wipe() async {
    await ref.read(trackerProvider).stop();
    ref.read(zoneGuardProvider).stop();
    ref.read(syncProvider).stop();
    await ref.read(dayTimerProvider).clear();
    await ref.read(appLockProvider.notifier).reset();
    await ref.read(pushProvider).forget();
    await _session.clear();
    await ref.read(databaseProvider).wipe();
    await ref.read(brandingCacheProvider).clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_meKey);
    await prefs.remove(MissionCache.key);
    // Brouillons et photos en attente : rien ne reste pour le compte suivant.
    await FormDrafts.clearAll();
    await PhotoStore.clear();
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Apparence active : celle de la structure une fois connecté, sinon l'apparence neutre.
final brandingProvider = Provider<Branding>((ref) {
  final auth = ref.watch(authProvider);
  return auth is SignedIn ? auth.branding : Branding.defaults;
});

/// Dernier profil connu : pendant la déconnexion ou la reprise de session, les écrans
/// encore montés se reconstruisent une dernière fois sans planter.
Me? _lastMe;

final meProvider = Provider<Me>((ref) {
  final auth = ref.watch(authProvider);
  if (auth is SignedIn) return _lastMe = auth.me;
  final last = _lastMe;
  if (last == null) throw StateError('Aucun agent connecté');
  return last;
});

/// Photo de profil d'un utilisateur, gardée en mémoire par version.
final avatarProvider =
    FutureProvider.family<Uint8List?, ({String userId, int version})>((
      ref,
      key,
    ) async {
      final bytes = await ref.read(repositoryProvider).avatarBytes(key.userId);
      return bytes == null ? null : Uint8List.fromList(bytes);
    });

/// Apparence choisie dans le profil : automatique (réglage du téléphone), claire ou sombre.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme.mode';

  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.system;
  }

  Future<void> _restore() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      final mode = ThemeMode.values.where((m) => m.name == raw).firstOrNull;
      if (mode != null) state = mode;
    } catch (_) {
      // Réglage illisible : on suit le téléphone.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, mode.name);
    } catch (_) {
      // Sans stockage, le choix vaut pour la session en cours.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Missions en cache : consultables et remplissables hors connexion.
class MissionCache {
  static const key = 'missions.json';

  static Future<void> write(Map<String, dynamic> data) async =>
      (await SharedPreferences.getInstance()).setString(key, jsonEncode(data));

  static Future<Map<String, dynamic>> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>);
  }
}
