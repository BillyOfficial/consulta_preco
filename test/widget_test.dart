import 'package:flutter_test/flutter_test.dart';
import 'package:consulta_preco/main.dart';

void main() {
  testWidgets('Tela inicial mostra os botões principais', (tester) async {
    await tester.pumpWidget(const ConsultaPrecoApp());

    expect(find.text('Pesquisar por EAN'), findsOneWidget);
    expect(find.text('Ler Nota Fiscal'), findsOneWidget);
    expect(find.text('Buscar por Produto'), findsOneWidget);
  });
}
