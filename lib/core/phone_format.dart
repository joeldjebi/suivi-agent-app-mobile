import 'package:flutter/services.dart';

/// Affiche le numéro par paires pendant la saisie : « 07 07 07 07 07 ».
/// Le format international (+225…) est conservé tel quel ; le serveur normalise.
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    final international = raw.startsWith('+');
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 15 ? digits.substring(0, 15) : digits;
    final text = international
        ? '+${_group(limited, firstGroup: 3)}'
        : _group(limited);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _group(String digits, {int firstGroup = 2}) {
    if (digits.isEmpty) return '';
    final parts = <String>[];
    var i = 0;
    if (firstGroup != 2) {
      parts.add(
        digits.substring(
          0,
          digits.length < firstGroup ? digits.length : firstGroup,
        ),
      );
      i = firstGroup;
    }
    for (; i < digits.length; i += 2) {
      parts.add(
        digits.substring(i, i + 2 > digits.length ? digits.length : i + 2),
      );
    }
    return parts.join(' ');
  }
}

/// Numéro plausible : 8 à 15 chiffres, avec ou sans indicatif.
bool isPlausiblePhone(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length >= 8 && digits.length <= 15;
}

/// Numéro lisible : « 07 99 88 77 66 » pour la Côte d'Ivoire, sinon « +33 6 12 … ».
String displayPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (phone.startsWith('+225') && digits.length == 13) {
    return PhoneInputFormatter()
        .formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(text: digits.substring(3)),
        )
        .text;
  }
  return PhoneInputFormatter()
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: phone))
      .text;
}
