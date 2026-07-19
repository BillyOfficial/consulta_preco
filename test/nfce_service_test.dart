import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:consulta_preco/servicos/nfce_service.dart';

// HTML representativo do layout nacional do DANFE NFC-e (igual ao da SEFAZ-RJ),
// baseado em uma nota real (SUPERMERCADOS MUNDIAL). Inclui um item por unidade
// e um por KG (quantidade fracionada), além do total via fallback (qtd × unit).
const _htmlNota = '''
<html><body>
  <div id="conteudo">
    <div class="txtTopo">SUPERMERCADOS MUNDIAL LTDA</div>
    <div class="text">CNPJ: 33.304.981/0021-63</div>
    <div class="text">Av. Monsenhor Felix , 1180 , , IRAJA, Rio de Janeiro, RJ</div>
  </div>
  <table id="tabResult">
    <tr id="Item1">
      <td>
        <span class="txtTit">S.COXA FGO NAT PCT 1KG</span>
        <span class="RCod">(Código: 522813 )</span>
        <span class="Rqtd"><strong>Qtde.:</strong>1</span>
        <span class="RUN"><strong>UN: </strong>UN</span>
        <span class="RvlUnit"><strong>Vl. Unit.:</strong>&nbsp;&nbsp;12,98</span>
      </td>
      <td><span class="valor">12,98</span></td>
    </tr>
    <tr id="Item2">
      <td>
        <span class="txtTit">QJO MUSSARELA TRAD.MULLER FATIAS KG</span>
        <span class="RCod">(Código: 88978 )</span>
        <span class="Rqtd"><strong>Qtde.:</strong>1,016</span>
        <span class="RUN"><strong>UN: </strong>KG</span>
        <span class="RvlUnit"><strong>Vl. Unit.:</strong>&nbsp;&nbsp;47,8</span>
      </td>
      <td><span class="valor">48,56</span></td>
    </tr>
  </table>
</body></html>
''';

void main() {
  final service = NfceService();

  test('extrai emitente, CNPJ e itens da NFC-e', () {
    final nota = service.notaDeHtml(_htmlNota, 'https://x/?p=33240712345678000199650030000012341123456789');

    expect(nota.emitente, 'SUPERMERCADOS MUNDIAL LTDA');
    expect(nota.cnpj, '33.304.981/0021-63');
    expect(nota.itens.length, 2);

    final item1 = nota.itens[0];
    expect(item1.nome, 'S.COXA FGO NAT PCT 1KG');
    expect(item1.codigo, '522813');
    expect(item1.quantidade, 1);
    expect(item1.unidade, 'UN');
    expect(item1.valorUnitario, 12.98);
    expect(item1.valorTotal, 12.98);

    final item2 = nota.itens[1];
    expect(item2.nome, 'QJO MUSSARELA TRAD.MULLER FATIAS KG');
    expect(item2.quantidade, 1.016);
    expect(item2.unidade, 'KG');
    expect(item2.valorUnitario, 47.8);
    expect(item2.valorTotal, 48.56);

    expect(nota.total, closeTo(61.54, 0.001));
  });

  test('detecta captcha e lança erro amigável', () {
    const htmlCaptcha = '<html><body><div class="g-recaptcha"></div></body></html>';
    expect(
      () => service.notaDeHtml(htmlCaptcha, 'https://x'),
      throwsA(isA<NfceException>()),
    );
  });

  test('parseia HTML REAL da SEFAZ-RJ (nota SUPERMERCADOS MUNDIAL)', () {
    final html =
        File('test/fixtures/nota_real_rj.html').readAsStringSync();
    final nota = service.notaDeHtml(html, 'https://consultadfe.fazenda.rj.gov.br/...?p=33260633304981002163651580002385911009179621|2|1|3|X');

    expect(nota.emitente, 'SUPERMERCADOS MUNDIAL LTDA');
    expect(nota.cnpj, '33.304.981/0021-63');
    expect(nota.itens.length, 25);

    // Primeiro item conhecido da nota real.
    final primeiro = nota.itens.first;
    expect(primeiro.nome, 'S.COXA FGO NAT PCT 1KG');
    expect(primeiro.codigo, '522813');
    expect(primeiro.valorUnitario, 12.98);

    // Todos os itens devem ter nome e preço unitário válidos.
    for (final item in nota.itens) {
      expect(item.nome.isNotEmpty, isTrue);
      expect(item.valorUnitario, greaterThan(0));
    }

    // Total da nota deve ser positivo e plausível.
    expect(nota.total, greaterThan(0));
  });

  test('pareceNfce reconhece URL com chave e rejeita texto comum', () {
    expect(
      NfceService.pareceNfce(
        'https://consultadfe.fazenda.rj.gov.br/...?p=33240712345678000199650030000012341123456789|2|1',
      ),
      isTrue,
    );
    expect(NfceService.pareceNfce('7891234567895'), isFalse);
    expect(NfceService.pareceNfce('https://google.com'), isFalse);
  });
}
