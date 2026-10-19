/// Fonctions du navigateur pour la version web (sans effet dans l'app mobile).
library;

export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';
