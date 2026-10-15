import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:suivi_agent/features/profile/notifications_screen.dart';
import 'package:suivi_agent/widgets/brand_header.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('cloche : nombre de notifications non lues', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [unreadCountProvider.overrideWith((ref) async => 3)],
        child: const MaterialApp(
          home: Scaffold(body: BrandHeader(title: 'Ma journée')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('Notifications, 3 non lues'), findsOneWidget);
  });
}
