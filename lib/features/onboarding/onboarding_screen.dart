import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../core/providers.dart';
import '../../design/tokens.dart';
import 'onboarding_data.dart';

/// Présentation de l'app en quelques pages animées : les animations suivent le glissement
/// et se rejouent au toucher. « Passer » ou « Commencer » termine.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.content,
    required this.onDone,
  });

  final OnboardingContent content;
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;

  List<OnboardingSlide> get _slides => widget.content.slides;
  bool get _last => _index == _slides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_last) return widget.onDone();
    _pages.nextPage(
      duration: Motion.of(context, const Duration(milliseconds: 420)),
      curve: Curves.easeOutCubic,
    );
  }

  /// Couleur d'accent fondue d'une page à l'autre pendant le glissement.
  Color _accent(Color fallback) {
    final page = _pages.hasClients ? (_pages.page ?? 0) : 0.0;
    final from = page.floor().clamp(0, _slides.length - 1);
    final to = page.ceil().clamp(0, _slides.length - 1);
    return Color.lerp(
      _slides[from].color ?? fallback,
      _slides[to].color ?? fallback,
      page - page.floor(),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brand = ref.watch(brandingProvider).primary;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _pages,
          builder: (context, _) {
            final accent = _accent(brand);
            return Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      Space.sm,
                      Space.sm,
                      0,
                    ),
                    child: AnimatedOpacity(
                      opacity: _last ? 0 : 1,
                      duration: Motion.of(context, Motion.medium),
                      child: TextButton(
                        onPressed: _last ? null : widget.onDone,
                        style: TextButton.styleFrom(
                          foregroundColor: scheme.onSurfaceVariant,
                          minimumSize: const Size(64, 44),
                        ),
                        child: const Text('Passer'),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _SlidePage(
                      slide: _slides[i],
                      active: i == _index,
                      // Décalage de la page par rapport à l'écran (−1 … 1) pour l'effet de profondeur.
                      offset:
                          _pages.hasClients && _pages.position.haveDimensions
                          ? (_pages.page ?? 0) - i
                          : (i - _index).toDouble(),
                      accent: _slides[i].color ?? brand,
                    ),
                  ),
                ),
                Semantics(
                  label: 'Page ${_index + 1} sur ${_slides.length}',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: Motion.of(context, Motion.medium),
                          curve: Motion.curve,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 7,
                          width: i == _index ? 22 : 7,
                          decoration: BoxDecoration(
                            color: i == _index ? accent : scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    Space.xxl,
                    Space.xxl,
                    Space.xl,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: text.titleMedium?.semibold,
                      ),
                      child: AnimatedSwitcher(
                        duration: Motion.of(context, Motion.fast),
                        child: Text(
                          _last ? 'Commencer' : 'Suivant',
                          key: ValueKey(_last),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({
    required this.slide,
    required this.active,
    required this.offset,
    required this.accent,
  });

  final OnboardingSlide slide;
  final bool active;
  final double offset;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final distance = offset.abs().clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
      child: Column(
        children: [
          Expanded(
            // L'animation glisse moins vite que la page et rétrécit en s'éloignant.
            child: Transform.translate(
              offset: Offset(offset * -90, 0),
              child: Transform.scale(
                scale: 1 - distance * 0.18,
                child: Opacity(
                  opacity: 1 - distance * 0.6,
                  child: Center(
                    child: _SlideAnimation(
                      slide: slide,
                      active: active,
                      accent: accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(offset * 40, 0),
            child: Opacity(
              opacity: 1 - distance,
              child: Column(
                children: [
                  Text(
                    slide.title,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.bold.copyWith(height: 1.15),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    slide.body,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: Space.xxl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animation de la page : entrée puis boucle calme (images 30 → 120), rejouée au toucher.
/// Les formes « accent » prennent la couleur de la page.
class _SlideAnimation extends StatefulWidget {
  const _SlideAnimation({
    required this.slide,
    required this.active,
    required this.accent,
  });

  final OnboardingSlide slide;
  final bool active;
  final Color accent;

  @override
  State<_SlideAnimation> createState() => _SlideAnimationState();
}

class _SlideAnimationState extends State<_SlideAnimation>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  bool _loaded = false;

  /// Début de la boucle : image 30 sur 120.
  static const _loopStart = 0.25;

  bool get _reduced => MediaQuery.of(context).disableAnimations;

  @override
  void didUpdateWidget(covariant _SlideAnimation old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _play() {
    if (!_loaded || !mounted) return;
    if (_reduced) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0).then((_) {
      if (mounted) _controller.repeat(min: _loopStart, max: 1);
    }, onError: (_) {});
  }

  void _onLoaded(LottieComposition composition) {
    _controller.duration = composition.duration;
    _loaded = true;
    // Page visible : l'entrée se joue ; sinon l'image de la boucle attend.
    if (widget.active) {
      _play();
    } else {
      _controller.value = _loopStart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final delegates = LottieDelegates(
      values: [
        ValueDelegate.color(const ['**', 'accent', '**'], value: widget.accent),
        ValueDelegate.strokeColor(const [
          '**',
          'accent',
          '**',
        ], value: widget.accent),
      ],
    );
    final bytes = widget.slide.lottie;
    final animation = bytes != null
        ? Lottie.memory(
            bytes,
            controller: _controller,
            delegates: delegates,
            onLoaded: _onLoaded,
            errorBuilder: (_, _, _) => _fallback(delegates),
          )
        : _fallback(delegates);
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _play();
      },
      child: AspectRatio(aspectRatio: 1, child: animation),
    );
  }

  Widget _fallback(LottieDelegates delegates) => Lottie.asset(
    widget.slide.asset,
    controller: _controller,
    delegates: delegates,
    onLoaded: _onLoaded,
  );
}

/// Onboarding revu depuis le profil.
class OnboardingReplayScreen extends ConsumerWidget {
  const OnboardingReplayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.read(onboardingProvider.notifier).content;
    return OnboardingScreen(
      content: content,
      onDone: () => unawaited(Navigator.of(context).maybePop()),
    );
  }
}
