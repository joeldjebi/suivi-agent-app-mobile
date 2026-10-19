/// Installation de la version web sur l'écran d'accueil (téléphone, ordinateur).
library;

export 'install_app_stub.dart'
    if (dart.library.js_interop) 'install_app_web.dart';
