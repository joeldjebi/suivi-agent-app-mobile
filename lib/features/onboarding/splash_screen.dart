import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';

/// Couleur du démarrage (identique à l'écran natif généré par flutter_native_splash).
const splashColor = Color(0xFF2563EB);

/// Démarrage animé, dans la continuité de l'écran natif : même fond, même repère au même
/// endroit, puis une onde et le nom de l'app pendant la reprise de session.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 0.6;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: splashColor,
        body: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            // Onde qui part du repère, comme sur les animations de l'onboarding.
            Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) {
                  final t = Curves.easeOut.transform(_controller.value);
                  return Container(
                    width: 110 + 190 * t,
                    height: 110 + 190 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35 * (1 - t)),
                        width: 3,
                      ),
                    ),
                  );
                },
              ),
            ),
            // 192 points : taille du logo natif (image @4x de 768 pixels).
            Center(
              child: Image.asset(
                'assets/splash/logo.png',
                width: 192,
                height: 192,
                semanticLabel: 'Suivi Agent',
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 72,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.of(context, const Duration(milliseconds: 600)),
                curve: Curves.easeOut,
                builder: (_, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(
                    offset: Offset(0, 12 * (1 - v)),
                    child: child,
                  ),
                ),
                child: Text(
                  'Suivi Agent',
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.bold.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
