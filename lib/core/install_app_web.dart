import 'dart:js_interop';

@JS('pxStandalone')
external JSBoolean? _standalone();

@JS('pxCanPrompt')
external JSBoolean? _canPrompt();

@JS('pxPrompt')
external JSPromise<JSBoolean>? _prompt();

@JS('pxIsIOS')
external JSBoolean? _isIOS();

/// Déjà ouverte comme une app (depuis l'écran d'accueil).
bool installStandalone() {
  try {
    return _standalone()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// Le navigateur propose sa fenêtre d'installation (Android, Chrome, Edge).
bool installCanPrompt() {
  try {
    return _canPrompt()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// Ouvre la fenêtre d'installation du navigateur ; vrai si la personne accepte.
Future<bool> installPrompt() async {
  try {
    return (await _prompt()?.toDart)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

/// iPhone ou iPad : installation par Partager → « Sur l'écran d'accueil ».
bool installIsIOS() {
  try {
    return _isIOS()?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
