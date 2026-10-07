import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Photo d'un champ de formulaire, gardée sur le téléphone jusqu'à l'envoi : le fichier,
/// la position et l'heure de la prise. Dans les données du formulaire, elle est remplacée
/// par l'identifiant donné par le serveur au moment de l'envoi.
class FieldPhoto {
  const FieldPhoto({
    required this.clientId,
    required this.path,
    required this.takenAt,
    this.lat,
    this.lng,
    this.accuracy,
  });

  final String clientId;
  final String path;
  final DateTime takenAt;
  final double? lat;
  final double? lng;

  /// Précision de la position, en mètres.
  final double? accuracy;

  bool get located => lat != null && lng != null;

  File get file => File(path);

  /// Valeur d'un champ photo encore sur le téléphone ?
  static bool isLocal(Object? value) =>
      value is Map && value['path'] is String && value['clientId'] is String;

  static FieldPhoto? tryParse(Object? value) {
    if (!isLocal(value)) return null;
    final map = (value as Map).cast<String, dynamic>();
    return FieldPhoto(
      clientId: map['clientId'] as String,
      path: map['path'] as String,
      takenAt: DateTime.parse(map['takenAt'] as String),
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'clientId': clientId,
    'path': path,
    'takenAt': takenAt.toUtc().toIso8601String(),
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (accuracy != null) 'accuracy': accuracy,
  };

  /// Photos encore sur le téléphone dans des données de formulaire.
  static List<FieldPhoto> inData(Map<String, Object?> data) =>
      data.values.map(tryParse).whereType<FieldPhoto>().toList();
}

/// Dossier des photos en attente d'envoi.
class PhotoStore {
  static Future<Directory> dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/form-photos');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Retire les fichiers (envoyés, brouillon abandonné). Petits fichiers : suppression
  /// immédiate.
  static Future<void> delete(Iterable<FieldPhoto> photos) async {
    for (final p in photos) {
      try {
        if (p.file.existsSync()) p.file.deleteSync();
      } catch (_) {
        // Déjà retiré.
      }
    }
  }

  /// Déconnexion : plus aucune photo de l'agent sur le téléphone.
  static Future<void> clear() async {
    try {
      final d = await dir();
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {
      // Rien à retirer.
    }
  }
}

/// Prise de photo (remplacée dans les tests).
abstract interface class PhotoCapture {
  /// null si l'agent annule.
  Future<FieldPhoto?> take();
}

/// Appareil photo du téléphone, jamais la galerie : la photo est prise sur place. Réduite
/// avant l'envoi (1600 px, JPEG), avec la position du moment.
class CameraPhotoCapture implements PhotoCapture {
  @override
  Future<FieldPhoto?> take() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 75,
    );
    if (picked == null) return null;
    final takenAt = DateTime.now();
    final position = await _position();
    final clientId = const Uuid().v4();
    final target = '${(await PhotoStore.dir()).path}/$clientId.jpg';
    await File(picked.path).copy(target);
    try {
      await File(picked.path).delete();
    } catch (_) {
      // Fichier temporaire du système : retiré par lui.
    }
    return FieldPhoto(
      clientId: clientId,
      path: target,
      takenAt: takenAt,
      lat: position?.latitude,
      lng: position?.longitude,
      accuracy: position?.accuracy,
    );
  }

  /// Position du moment (8 s au plus), sinon la dernière connue.
  Future<Position?> _position() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }
}
