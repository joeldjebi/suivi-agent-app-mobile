import 'package:flutter_test/flutter_test.dart';
import 'package:suivi_agent/features/shell/live_updates.dart';

void main() {
  test('chaque annonce relit les écrans concernés', () {
    expect(areasFor('missions'), {
      LiveArea.missions,
      LiveArea.pay,
      LiveArea.day,
      LiveArea.outlets,
    });
    expect(areasFor('zones'), containsAll([LiveArea.day, LiveArea.team]));
    expect(areasFor('groups'), contains(LiveArea.profile));
    expect(areasFor('branding'), {LiveArea.profile});
    expect(areasFor('pay'), {LiveArea.pay});
    // Camion affecté, chargement, vente, dépannage d'un collègue.
    expect(areasFor('stock'), contains(LiveArea.van));
    expect(areasFor('van-sales'), contains(LiveArea.van));
    // Point de vente confié à un autre agent.
    expect(areasFor('outlets'), contains(LiveArea.outlets));
    expect(areasFor('orders'), contains(LiveArea.orders));
    // Sujet inconnu (nouvelle fonctionnalité) : tout est relu.
    expect(areasFor('nouveau-module'), LiveArea.values.toSet());
  });

  test('une notification relit les écrans qu’elle concerne, et la journée', () {
    expect(
      areasForNotification('transfer.requested'),
      containsAll([LiveArea.van, LiveArea.day]),
    );
    expect(
      areasForNotification('stock.van_assigned'),
      containsAll([LiveArea.van, LiveArea.day]),
    );
    expect(
      areasForNotification('outlets.assigned'),
      containsAll([LiveArea.outlets, LiveArea.day]),
    );
    expect(areasForNotification('autre.chose'), LiveArea.values.toSet());
  });
}
