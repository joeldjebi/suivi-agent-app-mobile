import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/phone_format.dart';
import '../../core/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/user_avatar.dart';
import '../pay/pay_screens.dart';
import 'my_team.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final pending = ref.read(pendingCountProvider).value ?? 0;
    final confirmed = await confirmSheet(
      context,
      title: 'Se déconnecter ?',
      message: pending > 0
          ? 'Attention : $pending donnée${pending > 1 ? 's n’ont' : ' n’a'} pas encore été envoyée${pending > 1 ? 's' : ''} et ${pending > 1 ? 'seront perdues' : 'sera perdue'}. Reconnectez-vous au réseau avant de vous déconnecter.'
          : 'Vous devrez saisir à nouveau votre numéro et votre mot de passe.',
      confirmLabel: 'Se déconnecter',
      destructive: pending > 0,
    );
    if (confirmed) await ref.read(authProvider.notifier).logout();
  }

  /// Photo de profil : appareil photo, galerie ou suppression.
  Future<void> _editPhoto(BuildContext context, WidgetRef ref) async {
    final me = ref.read(meProvider);
    final choice = await pickOption<String>(
      context,
      title: 'Photo de profil',
      selected: '',
      options: {
        'camera': 'Prendre une photo',
        'gallery': 'Choisir dans la galerie',
        if (me.avatarVersion != null) 'remove': 'Supprimer la photo',
      },
    );
    if (choice == null || !context.mounted) return;
    final auth = ref.read(authProvider.notifier);
    try {
      if (choice.value == 'remove') {
        await auth.removeAvatar();
        if (context.mounted) showMessage(context, 'Photo supprimée');
        return;
      }
      // Image réduite sur le téléphone : envoi rapide, même en 3G.
      final picked = await ImagePicker().pickImage(
        source: choice.value == 'camera'
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      if (picked == null) return;
      await auth.setAvatar(await picked.readAsBytes());
      if (context.mounted) showMessage(context, 'Photo mise à jour');
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    } on PlatformException {
      if (context.mounted) {
        showMessage(
          context,
          'Accès à l’appareil photo ou aux photos refusé. Autorisez-le dans les réglages du téléphone.',
          error: true,
        );
      }
    }
  }

  Future<void> _editTheme(BuildContext context, WidgetRef ref) async {
    final picked = await pickOption<ThemeMode>(
      context,
      title: 'Apparence',
      selected: ref.read(themeModeProvider),
      options: {for (final m in ThemeMode.values) m: _themeLabel(m)},
    );
    if (picked != null) {
      await ref.read(themeModeProvider.notifier).set(picked.value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final branding = ref.watch(brandingProvider);
    final theme = ref.watch(themeModeProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget icon(IconData icon, Color color) =>
        IconSquircle(icon: icon, color: color, size: 28, solid: true);

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Space.page,
          MediaQuery.paddingOf(context).top + Space.xxl,
          Space.page,
          Space.xxxl,
        ),
        children: [
          // Fiche d'identité, centrée ; toucher la photo pour la changer.
          Center(
            child: Semantics(
              button: true,
              label: 'Changer la photo de profil',
              child: GestureDetector(
                onTap: () => _editPhoto(context, ref),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(
                      userId: me.id,
                      version: me.avatarVersion,
                      initials: me.initials,
                      size: 84,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 3),
                        ),
                        child: Icon(
                          Icons.photo_camera_rounded,
                          size: 14,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.md),
          Text(
            me.fullName,
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            me.isTeamLead ? 'Chef d’équipe' : 'Agent de terrain',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          GroupedList(
            header: 'Mon compte',
            footer:
                'Votre numéro sert à vous connecter : seule votre structure peut le modifier.',
            children: [
              ListRow(
                leading: icon(Icons.person_rounded, const Color(0xFF3B82F6)),
                title: 'Informations personnelles',
                subtitle: me.email,
                onTap: () => context.push('/profile/edit'),
              ),
              ListRow(
                leading: icon(Icons.phone_rounded, const Color(0xFF34A853)),
                title: 'Téléphone',
                value: me.phone == null ? null : displayPhone(me.phone!),
              ),
              ListRow(
                leading: icon(Icons.key_rounded, const Color(0xFF6B7280)),
                title: 'Mot de passe',
                onTap: () => context.push('/profile/password'),
              ),
            ],
          ),
          if (me.hasPayroll)
            GroupedList(
              header: 'Rémunération',
              children: [
                ListRow(
                  leading: icon(
                    Icons.account_balance_wallet_rounded,
                    const Color(0xFF34A853),
                  ),
                  title: 'Mes gains',
                  subtitle: 'Estimation en direct et paies',
                  value: switch (ref.watch(myPayProvider).value) {
                    final MyPay pay => formatMoney(
                      pay.estimate?.gross ?? 0,
                      pay.current.currency,
                    ),
                    null => null,
                  },
                  onTap: () => context.push('/profile/earnings'),
                ),
                if (me.isTeamLead)
                  ListRow(
                    leading: icon(
                      Icons.groups_rounded,
                      const Color(0xFF3B82F6),
                    ),
                    title: 'Gains de l’équipe',
                    onTap: () => context.push('/profile/team-earnings'),
                  ),
              ],
            ),
          if (me.isAgent) const MyTeamSection(),
          GroupedList(
            header: 'Ma structure',
            children: [
              ListRow(
                leading: BrandLogo(branding: branding, size: 28),
                title: branding.displayName,
              ),
              if (branding.supportPhone != null)
                ListRow(
                  leading: icon(Icons.call_rounded, const Color(0xFF34A853)),
                  title: 'Appeler la structure',
                  value: branding.supportPhone,
                  onTap: () => launchUrl(
                    Uri(
                      scheme: 'tel',
                      path: branding.supportPhone!.replaceAll(
                        RegExp(r'[^0-9+]'),
                        '',
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GroupedList(
            header: 'Préférences',
            children: [
              ListRow(
                leading: icon(
                  Icons.notifications_rounded,
                  const Color(0xFFE5484D),
                ),
                title: 'Notifications',
                onTap: () => context.push('/notifications'),
              ),
              ListRow(
                leading: icon(Icons.dark_mode_rounded, const Color(0xFF6366F1)),
                title: 'Apparence',
                value: _themeLabel(theme),
                onTap: () => _editTheme(context, ref),
              ),
              ListRow(
                leading: icon(
                  Icons.auto_awesome_rounded,
                  const Color(0xFF0EA5E9),
                ),
                title: 'Découvrir l’app',
                onTap: () => context.push('/welcome'),
              ),
            ],
          ),
          if (me.isAgent)
            GroupedList(
              header: 'Confidentialité',
              footer:
                  'Votre position est partagée avec ${branding.displayName} uniquement pendant votre journée de travail'
                  '${me.trackDuringPause ? ', pauses comprises' : ', sans les pauses'}. Le suivi s’arrête dès que vous terminez la journée.',
              children: [
                ListRow(
                  leading: icon(
                    Icons.location_on_rounded,
                    const Color(0xFF3B82F6),
                  ),
                  title: 'Partage de position',
                  value: 'En journée',
                ),
              ],
            ),
          const SizedBox(height: Space.xxl),
          GroupedList(
            children: [
              ListRow(
                title: 'Se déconnecter',
                titleColor: scheme.error,
                centered: true,
                onTap: () => _logout(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _themeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Automatique',
  ThemeMode.light => 'Clair',
  ThemeMode.dark => 'Sombre',
};
