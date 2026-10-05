import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Apparence de l'app définie par la structure. Appliquée uniquement une fois
/// l'agent connecté ; l'écran de connexion garde l'apparence par défaut.
class Branding {
  const Branding({
    required this.displayName,
    required this.primary,
    required this.onPrimary,
    this.welcomeMessage,
    this.supportPhone,
    this.logo,
    this.version = 0,
  });

  final String displayName;
  final Color primary;
  final Color onPrimary;
  final String? welcomeMessage;
  final String? supportPhone;
  final Uint8List? logo;
  final int version;

  /// Apparence neutre « Suivi Agent ».
  static const defaults = Branding(
    displayName: 'Suivi Agent',
    primary: Color(0xFF2563EB),
    onPrimary: Colors.white,
  );

  factory Branding.fromJson(Map<String, dynamic> json, {Uint8List? logo}) =>
      Branding(
        displayName: json['displayName'] as String,
        primary: parseHex(json['primaryColor'] as String) ?? defaults.primary,
        onPrimary: parseHex(json['onPrimaryColor'] as String) ?? Colors.white,
        welcomeMessage: json['welcomeMessage'] as String?,
        supportPhone: json['supportPhone'] as String?,
        logo: logo,
        version: json['version'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'primaryColor': toHex(primary),
    'onPrimaryColor': toHex(onPrimary),
    'welcomeMessage': welcomeMessage,
    'supportPhone': supportPhone,
    'version': version,
  };

  static Color? parseHex(String value) {
    final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value);
    return match == null
        ? null
        : Color(int.parse('FF${match.group(1)}', radix: 16));
  }

  static String toHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// Cache local : l'app garde l'apparence de la structure sans réseau.
class BrandingCache {
  static const _jsonKey = 'branding.json';
  static const _logoKey = 'branding.logo';

  Future<Branding?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_jsonKey);
    if (raw == null) return null;
    final logo = prefs.getString(_logoKey);
    return Branding.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      logo: logo == null ? null : base64Decode(logo),
    );
  }

  Future<void> write(Branding branding) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jsonKey, jsonEncode(branding.toJson()));
    if (branding.logo == null) {
      await prefs.remove(_logoKey);
    } else {
      await prefs.setString(_logoKey, base64Encode(branding.logo!));
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_jsonKey);
    await prefs.remove(_logoKey);
  }
}
