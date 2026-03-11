import 'package:flutter_test/flutter_test.dart';

import 'package:keuangan_kampus/main.dart';

void main() {
  testWidgets('Dashboard shows key content on startup', (WidgetTester tester) async {
    await tester.pumpWidget(const KeuanganKampusApp());
    await tester.pumpAndSettle();

    expect(find.text('Hi, Administrator'), findsOneWidget);
    expect(find.text('Transaksi Terakhir'), findsOneWidget);
  });
}
