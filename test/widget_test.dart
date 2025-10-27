import 'package:flutter_test/flutter_test.dart';
import 'package:consulta_preco/main.dart';

void main() {
  testWidgets('Tela inicial mostra dois botões', (tester) async {
    await tester.pumpWidget(const ConsultaPrecoApp());

    expect(find.text('Pesquisar por EAN'), findsOneWidget);
    expect(find.text('Pesquisar por Produto'), findsOneWidget);
  });
}
