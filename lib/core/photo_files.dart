/// Stockage des photos en attente d'envoi : fichiers sur le téléphone, stockage du
/// navigateur pour la version web.
library;

export 'photo_files_io.dart'
    if (dart.library.js_interop) 'photo_files_web.dart';
