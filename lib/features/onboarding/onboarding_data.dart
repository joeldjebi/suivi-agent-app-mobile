import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/branding.dart';
import '../../core/config.dart';
import '../../core/providers.dart';

/// Page de l'onboarding (réglée par l'éditeur depuis sa console).
class OnboardingSlide {
  const OnboardingSlide({
    required this.id,
    required this.title,
    required this.body,
    required this.animation,
    this.color,
    this.lottieUrl,
    this.lottie,
  });

  final String id;
  final String title;
  final String body;

  /// Animation fournie avec l'app : location, missions ou team.
  final String animation;
  final Color? color;
  final String? lottieUrl;

  /// Animation importée par l'éditeur, téléchargée (null : animation fournie).
  final Uint8List? lottie;

  String get asset => 'assets/onboarding/$animation.json';

  factory OnboardingSlide.fromJson(
    Map<String, dynamic> j, {
    Uint8List? lottie,
  }) => OnboardingSlide(
    id: j['id'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    animation: const {'location', 'missions', 'team'}.contains(j['animation'])
        ? j['animation'] as String
        : 'location',
    color: j['color'] is String
        ? Branding.parseHex(j['color'] as String)
        : null,
    lottieUrl: j['lottieUrl'] as String?,
    lottie: lottie,
  );
}

class OnboardingContent {
  const OnboardingContent({
    required this.enabled,
    required this.version,
    required this.slides,
  });

  final bool enabled;
  final int version;
  final List<OnboardingSlide> slides;

  /// Pages d'origine (premier lancement sans réseau), comme celles du serveur.
  static const defaults = OnboardingContent(
    enabled: true,
    version: 1,
    slides: [
      OnboardingSlide(
        id: 'location',
        title: 'Votre journée, en un geste',
        body:
            'Démarrez votre journée dans votre zone : votre position est partagée avec votre équipe pendant le travail, jamais en dehors.',
        animation: 'location',
      ),
      OnboardingSlide(
        id: 'missions',
        title: 'Vos missions sur le terrain',
        body:
            'Consultez vos objectifs, remplissez vos formulaires même sans réseau et suivez votre progression en direct.',
        animation: 'missions',
      ),
      OnboardingSlide(
        id: 'team',
        title: 'Toute l’équipe, en temps réel',
        body:
            'Votre chef d’équipe vous accompagne : zones, alertes et messages arrivent aussitôt sur votre téléphone.',
        animation: 'team',
      ),
    ],
  );
}

/// État du démarrage : vérification en cours, onboarding à montrer, ou rien à montrer.
sealed class OnboardingState {
  const OnboardingState();
}

class OnboardingChecking extends OnboardingState {
  const OnboardingChecking();
}

class OnboardingPending extends OnboardingState {
  const OnboardingPending(this.content);
  final OnboardingContent content;
}

class OnboardingDone extends OnboardingState {
  const OnboardingDone([this.content = OnboardingContent.defaults]);

  /// Dernier contenu connu, pour le revoir depuis le profil.
  final OnboardingContent content;
}

/// Lecture de l'onboarding : sans connexion, depuis l'API, avec un cache pour le hors-ligne.
class OnboardingSource {
  OnboardingSource(this._dio);

  final Dio _dio;
  static const _cacheKey = 'onboarding.cache';
  static const _lottiePrefix = 'onboarding.lottie.';

  Future<OnboardingContent?> fetch() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? raw;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$apiUrl/public/app-onboarding',
      );
      raw = res.data;
      if (raw != null) await prefs.setString(_cacheKey, jsonEncode(raw));
    } catch (_) {
      final cached = prefs.getString(_cacheKey);
      if (cached != null) raw = jsonDecode(cached) as Map<String, dynamic>;
    }
    if (raw == null) return null;
    final slides = <OnboardingSlide>[];
    for (final s in (raw['slides'] as List).cast<Map<String, dynamic>>()) {
      final url = s['lottieUrl'] as String?;
      slides.add(
        OnboardingSlide.fromJson(
          s,
          lottie: url == null ? null : await _lottie(prefs, url),
        ),
      );
    }
    return OnboardingContent(
      enabled: raw['enabled'] as bool? ?? true,
      version: (raw['version'] as num?)?.toInt() ?? 1,
      slides: slides,
    );
  }

  /// Animation importée : l'adresse change à chaque modification, le cache suit.
  Future<Uint8List?> _lottie(SharedPreferences prefs, String url) async {
    final key = '$_lottiePrefix$url';
    final cached = prefs.getString(key);
    if (cached != null) return base64Decode(cached);
    try {
      final res = await _dio.get<List<int>>(
        '$serverOrigin$url',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(res.data!);
      for (final old in prefs.getKeys().where(
        (k) => k.startsWith(_lottiePrefix),
      )) {
        // Ancienne version de la même animation.
        if (old.split('?').first == key.split('?').first) {
          await prefs.remove(old);
        }
      }
      await prefs.setString(key, base64Encode(bytes));
      return bytes;
    } catch (_) {
      // Sans réseau : l'animation fournie la remplace.
      return null;
    }
  }
}

final onboardingSourceProvider = Provider<OnboardingSource>(
  (ref) => OnboardingSource(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 3),
        receiveTimeout: const Duration(seconds: 4),
      ),
    ),
  ),
);

/// Montré au premier lancement, puis une fois à chaque nouvelle version publiée par
/// l'éditeur. La vérification ne retarde pas le démarrage plus de quelques secondes.
class OnboardingController extends Notifier<OnboardingState> {
  static const seenKey = 'onboarding.seenVersion';

  @override
  OnboardingState build() {
    unawaited(_check());
    return const OnboardingChecking();
  }

  Future<void> _check() async {
    // L'écran de démarrage reste au moins le temps de son animation.
    final minimum = Future<void>.delayed(const Duration(milliseconds: 900));
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getInt(seenKey) ?? 0;
    OnboardingContent? content;
    try {
      content = await ref
          .read(onboardingSourceProvider)
          .fetch()
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      content = null;
    }
    // Premier lancement sans réseau ni cache : les pages d'origine.
    content ??= seen == 0 ? OnboardingContent.defaults : null;
    await minimum;
    if (content != null &&
        content.enabled &&
        content.slides.isNotEmpty &&
        content.version > seen) {
      state = OnboardingPending(content);
    } else {
      state = OnboardingDone(content ?? OnboardingContent.defaults);
    }
  }

  /// Fin (ou « Passer ») : cette version ne sera plus montrée.
  Future<void> complete() async {
    final current = state;
    if (current is! OnboardingPending) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(seenKey, current.content.version);
    state = OnboardingDone(current.content);
  }

  /// Contenu à revoir depuis le profil.
  OnboardingContent get content => switch (state) {
    OnboardingPending(:final content) => content,
    OnboardingDone(:final content) => content,
    _ => OnboardingContent.defaults,
  };
}

final onboardingProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

/// Couleur d'accent d'une page : celle de l'éditeur, sinon celle de l'app.
Color accentOf(OnboardingSlide slide, WidgetRef ref) =>
    slide.color ?? ref.watch(brandingProvider).primary;
