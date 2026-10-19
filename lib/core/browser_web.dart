import 'dart:js_interop';

@JS('pxIsMobile')
external JSBoolean? _isMobile();

@JS('pxKeepAwake')
external void _keepAwake(JSBoolean on);

@JS('pxNotifyPermission')
external JSPromise<JSString>? _notifyPermission();

@JS('pxNotify')
external JSBoolean? _notify(JSString tag, JSString title, JSString body);

/// Téléphone ou tablette (sinon un ordinateur).
bool browserIsMobile() {
  try {
    return _isMobile()?.toDart ?? true;
  } catch (_) {
    return true;
  }
}

/// Écran maintenu allumé (journée en cours) : le navigateur coupe le GPS écran éteint.
void browserKeepAwake(bool on) {
  try {
    _keepAwake(on.toJS);
  } catch (_) {}
}

/// Autorisation des notifications (demandée une fois).
Future<bool> browserNotificationsAllowed() async {
  try {
    final result = await _notifyPermission()?.toDart;
    return result?.toDart == 'granted';
  } catch (_) {
    return false;
  }
}

/// Notification du navigateur ; faux si elle n'a pas pu être affichée.
bool browserNotify(String tag, String title, String body) {
  try {
    return _notify(tag.toJS, title.toJS, body.toJS)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
