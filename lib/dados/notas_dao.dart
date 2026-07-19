import 'package:sqflite/sqflite.dart';
import 'banco_dados.dart';

/// Acesso às notas fiscais (NFC-e) importadas e aos seus itens.
class NotasDAO {
  /// Lista as notas com a contagem de PRODUTOS distintos ainda pendentes
  /// (sem EAN e não marcados como granel) — usado no status "Em progresso".
  Future<List<Map<String, dynamic>>> listarComProgresso() async {
    final db = await BancoDados().banco;
    return db.rawQuery('''
      SELECT n.*,
        (SELECT COUNT(DISTINCT p.id) FROM registros r
           JOIN produtos p ON p.id = r.produto_id
          WHERE r.nota_chave = n.chave
            AND (p.ean IS NULL OR p.ean = '')
            AND COALESCE(p.sem_codigo, 0) = 0
        ) AS pendentes
      FROM notas_importadas n
      ORDER BY n.importada_em DESC
    ''');
  }

  /// Itens de uma nota AGRUPADOS por produto. Itens repetidos (mesmo produto)
  /// viram uma única linha com `qtd_na_nota` — assim, escanear o EAN uma vez
  /// vale para todas as ocorrências.
  Future<List<Map<String, dynamic>>> itensDaNota(String chave) async {
    final db = await BancoDados().banco;
    return db.rawQuery(
      'SELECT MIN(r.id) AS id, p.id AS produto_id, p.nome, p.ean, '
      'COALESCE(p.sem_codigo, 0) AS sem_codigo, '
      'COUNT(*) AS qtd_na_nota, MAX(r.preco) AS preco '
      'FROM registros r '
      'JOIN produtos p ON r.produto_id = p.id '
      'WHERE r.nota_chave = ? '
      'GROUP BY p.id '
      'ORDER BY p.nome COLLATE NOCASE',
      [chave],
    );
  }

  /// Produtos da nota que já têm EAN escaneado (para avisar antes de excluir).
  Future<List<String>> produtosComEan(String chave) async {
    final db = await BancoDados().banco;
    final r = await db.rawQuery(
      'SELECT DISTINCT p.nome FROM registros r '
      'JOIN produtos p ON r.produto_id = p.id '
      "WHERE r.nota_chave = ? AND p.ean IS NOT NULL AND p.ean <> '' "
      'ORDER BY p.nome COLLATE NOCASE',
      [chave],
    );
    return r.map((m) => (m['nome'] ?? '').toString()).toList();
  }

  /// Exclui a nota e os preços que ela registrou.
  /// - [manterProdutos] = true: mantém os produtos no catálogo (só remove a nota
  ///   e seus registros de preço).
  /// - [manterProdutos] = false: também apaga os produtos que ficarem órfãos.
  Future<void> excluirNota(String chave, {bool manterProdutos = false}) async {
    final db = await BancoDados().banco;
    await db.transaction((txn) async {
      final afetados = await txn.rawQuery(
        'SELECT DISTINCT produto_id FROM registros WHERE nota_chave = ?',
        [chave],
      );
      await txn.delete('registros', where: 'nota_chave = ?', whereArgs: [chave]);

      if (!manterProdutos) {
        for (final row in afetados) {
          final pid = row['produto_id'] as int;
          final restantes = Sqflite.firstIntValue(await txn.rawQuery(
            'SELECT COUNT(*) FROM registros WHERE produto_id = ?',
            [pid],
          )) ?? 0;
          if (restantes == 0) {
            await txn.delete('produtos', where: 'id = ?', whereArgs: [pid]);
          }
        }
      }

      await txn.delete('notas_importadas', where: 'chave = ?', whereArgs: [chave]);
    });
  }
}
