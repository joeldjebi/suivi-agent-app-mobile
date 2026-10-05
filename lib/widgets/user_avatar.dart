import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';

/// Photo de profil ronde, ou initiales sur fond teinté quand il n'y en a pas.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    required this.version,
    required this.initials,
    this.size = 40,
  });

  final String userId;

  /// Version de la photo (null : pas de photo).
  final int? version;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final photo = version == null
        ? null
        : ref.watch(avatarProvider((userId: userId, version: version!))).value;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primary.withValues(alpha: 0.12),
      foregroundImage: photo == null ? null : MemoryImage(photo),
      child: Text(
        initials,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: scheme.primary,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
