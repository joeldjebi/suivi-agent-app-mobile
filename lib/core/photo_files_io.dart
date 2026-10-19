import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Rien à charger : les photos sont des fichiers.
Future<void> initPhotoFiles() async {}

Future<Directory> _dir() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/form-photos');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// Copie la photo prise dans le dossier des photos en attente ; renvoie son chemin.
Future<String> storePickedPhoto(XFile picked, String clientId) async {
  final target = '${(await _dir()).path}/$clientId.jpg';
  await File(picked.path).copy(target);
  try {
    await File(picked.path).delete();
  } catch (_) {
    // Fichier temporaire du système : retiré par lui.
  }
  return target;
}

bool photoExists(String path) => File(path).existsSync();

ImageProvider photoImage(String path) => FileImage(File(path));

Future<MultipartFile> photoUpload(String path) =>
    MultipartFile.fromFile(path, filename: 'photo.jpg');

/// Petits fichiers : suppression immédiate.
Future<void> deletePhotoFile(String path) async {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } catch (_) {
    // Déjà retiré.
  }
}

Future<void> clearPhotoFiles() async {
  try {
    final dir = await _dir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {
    // Rien à retirer.
  }
}
