/// Valida o dígito verificador de EAN-13, EAN-8, UPC-A (12) ou GTIN-14.
/// Evita gravar leituras corrompidas como código do produto.
bool eanValido(String code) {
  if (!RegExp(r'^\d+$').hasMatch(code)) return false;
  if (![8, 12, 13, 14].contains(code.length)) return false;

  final digitos = code.split('').map(int.parse).toList();
  final verificador = digitos.removeLast();

  var soma = 0;
  var pesoTres = true;
  for (var i = digitos.length - 1; i >= 0; i--, pesoTres = !pesoTres) {
    soma += digitos[i] * (pesoTres ? 3 : 1);
  }
  final calculado = (10 - (soma % 10)) % 10;
  return calculado == verificador;
}
