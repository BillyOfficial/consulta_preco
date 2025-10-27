import 'package:sqflite/sqflite.dart';
import 'banco_dados.dart';

class ProdutosDAO {
  /// Insere um produto; se já existir o mesmo EAN, ignora.
  Future<int> inserir({String? ean, required String nome}) async {
    // Obtém a instância do banco corretamente
    final db = await BancoDados().banco;

    // Dados que serão salvos
    final dados = {'ean': ean, 'nome': nome};

    // Tenta inserir e retorna o ID gerado
    final id = await db.insert(
      'produtos',
      dados,
      conflictAlgorithm: ConflictAlgorithm.ignore, // ignora duplicados
    );

    print('💾 Produto salvo com id: $id');
    return id;
  }

  /// Busca produto por EAN exato.
  Future<Map<String, dynamic>?> buscarPorEan(String ean) async {
    final db = await BancoDados().banco;
    final res = await db.query(
      'produtos',
      where: 'ean = ?',
      whereArgs: [ean],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Busca por nome (LIKE %termo%), máximo 50 resultados.
  Future<List<Map<String, dynamic>>> buscarPorNome(String termo) async {
    final db = await BancoDados().banco;
    final res = await db.query(
      'produtos',
      where: 'nome LIKE ?',
      whereArgs: ['%$termo%'],
      orderBy: 'nome ASC',
      limit: 50,
    );

    print('🔍 BuscarPorNome("$termo") retornou ${res.length} resultados');
    return res;
  }

  /// Busca um produto pelo ID.
  Future<Map<String, dynamic>?> buscarPorId(int id) async {
    final db = await BancoDados().banco;
    final res = await db.query(
      'produtos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }
}
