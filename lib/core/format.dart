import 'package:intl/intl.dart';

String formatDuration(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final h = total.inHours;
  final m = total.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = total.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h h $m' : '$m:$s';
}

/// Durée courte pour un libellé : « 3 h 12 », « 30 min ».
String formatShortDuration(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final h = total.inHours;
  final m = total.inMinutes.remainder(60);
  return h > 0 ? '$h h ${m.toString().padLeft(2, '0')}' : '$m min';
}

String formatTime(DateTime d) => DateFormat.Hm('fr_FR').format(d);

String formatDay(DateTime d) =>
    toBeginningOfSentenceCase(DateFormat('EEEE d MMMM', 'fr_FR').format(d));

String formatShortDate(DateTime d) => DateFormat('d MMM', 'fr_FR').format(d);

String formatNumber(num v) => NumberFormat.decimalPattern('fr_FR').format(v);

/// « 54 750 FCFA » ; le franc CFA (XOF) s'affiche comme on le dit sur le terrain.
String formatMoney(num v, [String currency = 'XOF']) =>
    '${formatNumber(v)}\u00a0${currency == 'XOF' || currency == 'XAF' ? 'FCFA' : currency}';

/// « 1 oct. → 31 oct. »
String formatRange(DateTime start, DateTime end) =>
    '${formatShortDate(start)} → ${formatShortDate(end)}';

/// « à l'instant », « il y a 5 min », « il y a 2 h »
String formatAgo(DateTime d, [DateTime? now]) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inSeconds < 45) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  return 'le ${formatShortDate(d)}';
}

String greeting([DateTime? now]) =>
    (now ?? DateTime.now()).hour < 18 ? 'Bonjour' : 'Bonsoir';

/// Durée de travail : 480 → « 8 h », 450 → « 7 h 30 », 30 → « 30 min ».
String formatWorkday(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}
