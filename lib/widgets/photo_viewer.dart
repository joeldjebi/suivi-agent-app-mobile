import 'package:flutter/material.dart';

/// Ouvre une photo en plein écran : fond noir, zoom aux doigts (jusqu'à 5 fois), fermeture
/// par la croix ou le retour. Pour vérifier qu'une photo est nette, ou en lire un détail.
Future<void> showPhoto(
  BuildContext context, {
  required ImageProvider image,
  required String title,
  String? caption,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) =>
        _PhotoViewerScreen(image: image, title: title, caption: caption),
  ),
);

class _PhotoViewerScreen extends StatelessWidget {
  const _PhotoViewerScreen({
    required this.image,
    required this.title,
    this.caption,
  });

  final ImageProvider image;
  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image(
                  image: image,
                  fit: BoxFit.contain,
                  semanticLabel: title,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.hide_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                [?caption, 'Écartez deux doigts pour zoomer'].join('\n'),
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Petite icône « agrandir » posée sur une photo : montre qu'un toucher l'ouvre en grand.
class ExpandBadge extends StatelessWidget {
  const ExpandBadge({super.key});

  @override
  Widget build(BuildContext context) => Positioned(
    right: 8,
    bottom: 8,
    child: IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.open_in_full_rounded,
          size: 16,
          color: Colors.white,
        ),
      ),
    ),
  );
}
