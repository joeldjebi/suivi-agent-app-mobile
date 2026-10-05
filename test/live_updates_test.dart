import 'package:flutter_test/flutter_test.dart';
import 'package:suivi_agent/features/shell/live_updates.dart';

void main() {
  test('chaque annonce relit les écrans concernés', () {
    expect(areasFor('missions'), {LiveArea.missions, LiveArea.pay});
    expect(areasFor('zones'), containsAll([LiveArea.day, LiveArea.team]));
    expect(areasFor('groups'), contains(LiveArea.profile));
    expect(areasFor('branding'), {LiveArea.profile});
    expect(areasFor('pay'), {LiveArea.pay});
    // Sujet inconnu (nouvelle fonctionnalité) : tout est relu.
    expect(areasFor('nouveau-module'), LiveArea.values.toSet());
  });
}
