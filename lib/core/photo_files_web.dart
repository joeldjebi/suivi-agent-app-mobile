import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Version web : les photos en attente sont gardées en mémoire et dans le stockage du
/// navigateur (elles survivent à un rechargement de la page jusqu'à leur envoi).
const _prefix = 'photo.';
const _scheme = 'web-photo:';
final _photos = <String, Uint8List>{};

/// Photos en attente relues au démarrage.
Future<void> initPhotoFiles() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      final value = prefs.getString(key);
      if (value != null) {
        _photos['$_scheme${key.substring(_prefix.length)}'] = base64Decode(
          value,
        );
      }
    }
  } catch (_) {
    // Stockage indisponible : photos gardées pour la session seulement.
  }
}

Future<String> storePickedPhoto(XFile picked, String clientId) async {
  final bytes = await picked.readAsBytes();
  final path = '$_scheme$clientId';
  _photos[path] = bytes;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$clientId', base64Encode(bytes));
  } catch (_) {
    // Stockage plein : la photo reste en mémoire jusqu'à l'envoi.
  }
  return path;
}

bool photoExists(String path) => _photos.containsKey(path);

ImageProvider photoImage(String path) =>
    MemoryImage(_photos[path] ?? Uint8List(0));

Future<MultipartFile> photoUpload(String path) async => MultipartFile.fromBytes(
  _photos[path] ?? Uint8List(0),
  filename: 'photo.jpg',
);

Future<void> deletePhotoFile(String path) async {
  _photos.remove(path);
  if (!path.startsWith(_scheme)) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix${path.substring(_scheme.length)}');
  } catch (_) {}
}

Future<void> clearPhotoFiles() async {
  for (final path in _photos.keys.toList()) {
    await deletePhotoFile(path);
  }
}
