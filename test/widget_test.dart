import 'package:flutter_test/flutter_test.dart';
import 'package:folha_certa/main.dart';

void main() {
  testWidgets('abre tela de login', (tester) async {
    await tester.pumpWidget(const FolhaCertaApp());
    expect(find.text('Folha Certa'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
