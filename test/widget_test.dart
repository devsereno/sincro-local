import "package:flutter_test/flutter_test.dart";
import "package:sincro_local/main.dart";

void main() {
  testWidgets("abre o SincroLocal", (tester) async {
    await tester.pumpWidget(const SincroApp());
    expect(find.text("SincroLocal"), findsOneWidget);
  });
}
