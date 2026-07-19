import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import '../modelos/nota_fiscal_model.dart';

/// Erro de importação com mensagem amigável para exibir ao usuário.
class NfceException implements Exception {
  final String mensagem;
  NfceException(this.mensagem);
  @override
  String toString() => mensagem;
}

/// Interpreta o HTML de uma página de NFC-e (DANFE NFC-e, layout nacional).
///
/// O HTML é obtido por um WebView (navegador real), pois portais como o da
/// SEFAZ-RJ usam bot-defense + reCAPTCHA e não respondem a requisições HTTP
/// simples. Esta classe cuida apenas do parsing — fácil de testar.
class NfceService {
  /// Extrai a chave de acesso (44 dígitos) de uma string do QR.
  static String? extrairChave(String texto) {
    final m = RegExp(r'\d{44}').firstMatch(texto);
    return m?.group(0);
  }

  /// Confere se o conteúdo do QR parece uma NFC-e (tem URL + chave).
  static bool pareceNfce(String texto) {
    final t = texto.toLowerCase();
    return t.startsWith('http') && extrairChave(texto) != null;
  }

  /// Indica se o HTML já contém a tabela de itens (página de resultado pronta).
  static bool temItens(String html) {
    final doc = html_parser.parse(html);
    return _selecionarLinhasItens(doc).any(
      (tr) => tr.querySelector('.txtTit') != null,
    );
  }

  /// Interpreta o HTML da página da NFC-e e devolve a nota com seus itens.
  /// Lança [NfceException] se não houver itens (captcha pendente ou layout novo).
  NotaFiscal notaDeHtml(String corpo, String url) {
    final doc = html_parser.parse(corpo);
    final itens = _extrairItens(doc);

    if (itens.isEmpty) {
      final baixo = corpo.toLowerCase();
      if (baixo.contains('captcha') ||
          baixo.contains('recaptcha') ||
          baixo.contains('turnstile')) {
        throw NfceException(
          'A SEFAZ ainda está pedindo a verificação de segurança. Conclua a '
          'verificação na tela e aguarde os itens aparecerem.',
        );
      }
      throw NfceException(
        'Não encontrei itens nesta nota. O layout da SEFAZ pode ter mudado.',
      );
    }

    return NotaFiscal(
      emitente: _texto(doc.querySelector('.txtTopo')),
      cnpj: _extrairCnpj(doc),
      endereco: _extrairEndereco(doc),
      chaveAcesso: extrairChave(url),
      url: url,
      itens: itens,
    );
  }

  // ---- Parsing ----

  static List<Element> _selecionarLinhasItens(Document doc) {
    var linhas = doc.querySelectorAll('#tabResult tr');
    if (linhas.isEmpty) {
      linhas = doc.querySelectorAll('table tr').where((tr) {
        return tr.querySelector('.txtTit') != null ||
            tr.querySelector('.RvlUnit') != null;
      }).toList();
    }
    return linhas;
  }

  List<ItemNota> _extrairItens(Document doc) {
    final itens = <ItemNota>[];
    for (final tr in _selecionarLinhasItens(doc)) {
      final nome = _texto(tr.querySelector('.txtTit')) ??
          _texto(tr.querySelector('.txtTit2'));
      if (nome == null || nome.isEmpty) continue;

      final codigo = _digitos(_texto(tr.querySelector('.RCod')));
      final qtd = _numero(_texto(tr.querySelector('.Rqtd'))) ?? 1;
      final unidade = _depoisDoisPontos(_texto(tr.querySelector('.RUN'))) ?? 'UN';
      final vlUnit = _numero(_texto(tr.querySelector('.RvlUnit'))) ?? 0;
      final vlTotal =
          _numero(_texto(tr.querySelector('.valor'))) ?? (qtd * vlUnit);

      itens.add(ItemNota(
        nome: nome,
        codigo: (codigo == null || codigo.isEmpty) ? null : codigo,
        quantidade: qtd,
        unidade: unidade,
        valorUnitario: vlUnit,
        valorTotal: vlTotal,
      ));
    }
    return itens;
  }

  String? _extrairCnpj(Document doc) {
    final texto = doc.body?.text ?? '';
    final m = RegExp(r'\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}').firstMatch(texto);
    return m?.group(0);
  }

  String? _extrairEndereco(Document doc) {
    for (final d in doc.querySelectorAll('.text')) {
      final t = d.text.trim();
      if (t.isNotEmpty && !t.contains('CNPJ') && t.length > 10) return t;
    }
    return null;
  }

  // ---- Helpers de texto ----

  String? _texto(Element? el) {
    final t = el?.text.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Extrai o primeiro número PT-BR (vírgula decimal) de um texto rotulado.
  /// Ex.: "Vl. Unit.: 12,98" -> 12.98 ; "Qtde.:1,016" -> 1.016
  double? _numero(String? texto) {
    if (texto == null) return null;
    final m = RegExp(r'\d+(?:\.\d{3})*(?:,\d+)?|\d+(?:\.\d+)?').firstMatch(texto);
    if (m == null) return null;
    var n = m.group(0)!;
    if (n.contains(',')) {
      n = n.replaceAll('.', '').replaceAll(',', '.');
    }
    return double.tryParse(n);
  }

  String? _digitos(String? texto) {
    if (texto == null) return null;
    return RegExp(r'\d+').firstMatch(texto)?.group(0);
  }

  String? _depoisDoisPontos(String? texto) {
    if (texto == null) return null;
    final partes = texto.split(':');
    final v = partes.length > 1 ? partes.last.trim() : texto.trim();
    return v.isEmpty ? null : v;
  }
}
