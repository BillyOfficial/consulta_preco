import '../modelos/loja_model.dart';
import 'banco_dados.dart';

class LojasDAO {
  Future<int> inserir(LojaModel loja) async {
    final db = await BancoDados().banco;
    return db.insert('lojas', loja.toMap());
  }

  Future<List<LojaModel>> listarPorLocal(int localId) async {
    final db = await BancoDados().banco;
    final res = await db.query(
      'lojas',
      where: 'local_id = ?',
      whereArgs: [localId],
      orderBy: 'id DESC',
    );
    return res.map((m) => LojaModel.fromMap(m)).toList();
  }

  /// Útil para o caso "Local com 1 loja?" — evita duplicar.
  Future<LojaModel> getOrCreate({
    required int localId,
    required String nome,
  }) async {
    final db = await BancoDados().banco;
    final existe = await db.query(
      'lojas',
      where: 'local_id = ? AND nome = ?',
      whereArgs: [localId, nome],
      limit: 1,
    );
    if (existe.isNotEmpty) {
      return LojaModel.fromMap(existe.first);
    }
    final id = await inserir(LojaModel(localId: localId, nome: nome));
    final novo = await db.query(
      'lojas',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return LojaModel.fromMap(novo.first);
  }
}
