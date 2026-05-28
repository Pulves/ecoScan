import 'package:ecoscan_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EcoScan login opens the main plant screens', (tester) async {
    await tester.pumpWidget(const EcoScanApp());

    expect(find.text('EcoScan'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Historico'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Minha Biblioteca'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.center_focus_strong));
    await tester.pumpAndSettle();
    expect(find.text('Captura'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Historico'), findsOneWidget);
  });
}
