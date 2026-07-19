/// Formata uma data ISO-8601 (com ou sem hora) para `dd/MM/yyyy`.
/// Retorna a string original se não for possível interpretar.
String formatarDataIso(String iso) {
  if (iso.trim().isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  return '$dia/$mes/${d.year}';
}
