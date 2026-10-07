import 'package:url_launcher/url_launcher.dart';

String _digits(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

/// Appel téléphonique.
Future<void> callPhone(String phone) =>
    launchUrl(Uri(scheme: 'tel', path: _digits(phone)));

/// WhatsApp : numéro au format international, sans « + ».
Future<void> openWhatsApp(String phone) => launchUrl(
  Uri.parse('https://wa.me/${_digits(phone).replaceAll('+', '')}'),
  mode: LaunchMode.externalApplication,
);
