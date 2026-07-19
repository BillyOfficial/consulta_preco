/// Um item (produto) de uma NFC-e.
class ItemNota {
  final String nome;
  final String? codigo; // código interno do estabelecimento (não é o EAN)
  final double quantidade;
  final String unidade; // UN, KG, etc.
  final double valorUnitario; // preço por unidade/kg
  final double valorTotal;

  /// EAN/GTIN do produto. A NFC-e não traz; é preenchido na revisão (scanner).
  String? ean;

  /// Marcado quando o item é a granel / sem código de barras (fruta, verdura...).
  bool semCodigo;

  ItemNota({
    required this.nome,
    this.codigo,
    required this.quantidade,
    required this.unidade,
    required this.valorUnitario,
    required this.valorTotal,
    this.ean,
    this.semCodigo = false,
  });

  /// Item já revisado: tem EAN escaneado ou foi marcado como granel.
  bool get revisado => (ean != null && ean!.isNotEmpty) || semCodigo;
}

/// Dados de uma NFC-e lida pelo QR Code e consultada na SEFAZ.
class NotaFiscal {
  final String? emitente; // nome do supermercado
  final String? cnpj;
  final String? endereco;
  final String? chaveAcesso; // 44 dígitos
  final String url; // URL completa do QR Code
  final List<ItemNota> itens;

  NotaFiscal({
    this.emitente,
    this.cnpj,
    this.endereco,
    this.chaveAcesso,
    required this.url,
    required this.itens,
  });

  double get total =>
      itens.fold(0.0, (soma, item) => soma + item.valorTotal);
}
