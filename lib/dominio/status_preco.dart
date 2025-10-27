/// Converte "12,34" ou "12.34" ou "12" para centavos (int).
int parseReaisParaCentavos(String texto) {
  final t = texto.trim().replaceAll('.', ',');
  if (t.contains(',')) {
    final partes = t.split(',');
    final reais = int.parse(partes[0].replaceAll(RegExp(r'[^0-9]'), ''));
    final cent = int.parse('${partes[1]}00'.substring(0, 2));
    return reais * 100 + cent;
  }
  return int.parse(t.replaceAll(RegExp(r'[^0-9]'), '')) * 100;
}

/// Converte centavos para "R$ 12,34".
String centavosParaReais(int c) {
  final r = (c / 100).toStringAsFixed(2).replaceAll('.', ',');
  return 'R\$ $r';
}

/// Calcula etiqueta: Barato / Na média / Caro (com base na mediana dos anteriores).
String statusPreco(int precoAtualCentavos, List<int> anterioresCentavos) {
  if (anterioresCentavos.isEmpty) return 'Sem base';

  final ordenado = [...anterioresCentavos]..sort();
  final m = ordenado.length ~/ 2;
  final mediana = ordenado.length.isOdd
      ? ordenado[m]
      : ((ordenado[m - 1] + ordenado[m]) / 2).round();

  final barato = (mediana * 0.90).round();
  final caro   = (mediana * 1.10).round();

  if (precoAtualCentavos <= barato) return 'Barato';
  if (precoAtualCentavos >= caro)   return 'Caro';
  return 'Na média';
}
