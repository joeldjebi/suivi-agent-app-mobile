import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vérification biométrique du téléphone (remplacée dans les tests).
abstract interface class Biometrics {
  /// Face ID, empreinte… configuré sur le téléphone (ou, à défaut, son code).
  Future<bool> available();

  /// « Face ID » sur iPhone si disponible, sinon « empreinte ».
  Future<String> label();

  Future<bool> authenticate(String reason);
}

class DeviceBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> label() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face) &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        return 'Face ID';
      }
      if (types.contains(BiometricType.face) &&
          !types.contains(BiometricType.fingerprint)) {
        return 'reconnaissance du visage';
      }
    } catch (_) {
      // Libellé générique.
    }
    return 'empreinte';
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // Code du téléphone accepté en secours (Face ID qui échoue, doigt mouillé…).
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

final biometricsProvider = Provider<Biometrics>((ref) => DeviceBiometrics());

class AppLockState {
  const AppLockState({this.enabled = false, this.locked = false});

  /// Déverrouillage par Face ID / empreinte activé sur ce téléphone.
  final bool enabled;

  /// L'app attend la vérification.
  final bool locked;
}

/// Verrouillage de l'app : au lancement, puis au retour après [_grace] en arrière-plan.
class AppLock extends Notifier<AppLockState> {
  static const key = 'security.biometric';
  static const _grace = Duration(minutes: 2);

  DateTime? _backgroundAt;
  bool _authenticating = false;

  @override
  AppLockState build() {
    _restore();
    return const AppLockState();
  }

  Future<void> _restore() async {
    try {
      final on = (await SharedPreferences.getInstance()).getBool(key) ?? false;
      // Lancement de l'app : verrouillée d'emblée.
      if (on) state = const AppLockState(enabled: true, locked: true);
    } catch (_) {
      // Réglage illisible : pas de verrouillage.
    }
  }

  Biometrics get _bio => ref.read(biometricsProvider);

  /// Activation : une première vérification confirme que tout fonctionne.
  Future<bool> enable() async {
    if (!await _bio.available()) return false;
    if (!await _bio.authenticate('Activer le déverrouillage de Suivi Agent')) {
      return false;
    }
    await (await SharedPreferences.getInstance()).setBool(key, true);
    state = const AppLockState(enabled: true);
    return true;
  }

  Future<void> disable() async {
    await (await SharedPreferences.getInstance()).remove(key);
    state = const AppLockState();
  }

  void onBackground() {
    if (!_authenticating) _backgroundAt ??= DateTime.now();
  }

  void onResume() {
    final since = _backgroundAt;
    _backgroundAt = null;
    if (state.enabled &&
        !state.locked &&
        since != null &&
        DateTime.now().difference(since) >= _grace) {
      state = const AppLockState(enabled: true, locked: true);
    }
  }

  Future<bool> unlock() async {
    if (_authenticating) return false;
    _authenticating = true;
    try {
      final ok = await _bio.authenticate('Déverrouiller Suivi Agent');
      if (ok) state = AppLockState(enabled: state.enabled);
      return ok;
    } finally {
      _authenticating = false;
      _backgroundAt = null;
    }
  }

  /// Déconnexion : le réglage appartient au compte, il ne passe pas au suivant.
  Future<void> reset() async {
    try {
      await (await SharedPreferences.getInstance()).remove(key);
    } catch (_) {
      // Rien à retirer.
    }
    state = const AppLockState();
  }
}

final appLockProvider = NotifierProvider<AppLock, AppLockState>(AppLock.new);
