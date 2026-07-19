import 'package:flutter/foundation.dart';
import 'banco_dados.dart';

/// DAO de Registros de preço.
///
/// O schema (ver [BancoDados]) usa as colunas fixas `preco` (REAL) e `data` (TEXT,
/// ISO-8601). A coluna `loja_id` foi adicionada na migração v2; `temColunaLojaId`
/// é mantido como rede de segurança para bancos muito antigos.
class RegistrosDAO {
  Set<String>? _colunasCache;

  Future<Set<String>> _colunas() async {
    if (_colunasCache != null) return _colunasCache!;
    final db = await BancoDados().banco;
    final res = await db.rawQuery("PRAGMA table_info('registros')");
    final nomes = <String>{};
    for (final m in res) {
      final nome = m['name'];
      if (nome is String && nome.isNotEmpty) nomes.add(nome);
    }
    _colunasCache = nomes;
    return nomes;
  }

  Future<bool> temColunaLojaId() async => (await _colunas()).contains('loja_id');

  /// Data/hora atual em ISO-8601 (com hora) — preserva a ordem cronológica
  /// mesmo com vários registros no mesmo dia.
  static String agoraIso() => DateTime.now().toIso8601String();

  /// Insere um novo registro de preço (sem loja vinculada).
  /// [notaChave] vincula o registro à NFC-e de origem (quando veio de nota).
  Future<int> inserir({
    required int produtoId,
    required double preco,
    String? dataIso,
    String? loja,
    String? notaChave,
  }) async {
    final db = await BancoDados().banco;
    final id = await db.insert('registros', {
      'produto_id': produtoId,
      'preco': preco,
      'data': dataIso ?? agoraIso(),
      'loja': loja,
      'nota_chave': notaChave,
    });
    debugPrint('💾 Registro inserido com id: $id (produto $produtoId)');
    return id;
  }

  /// Salva o preço de um produto (aceita reais ou centavos; loja em texto).
  Future<int> salvarPreco({
    required int produtoId,
    double? preco,
    int? precoCentavos,
    String? loja,
    String? cidade,
    String? dataIso,
    String? notaChave,
  }) async {
    final valor = preco ?? (precoCentavos != null ? precoCentavos / 100 : 0.0);
    final id = await inserir(
      produtoId: produtoId,
      preco: valor.toDouble(),
      dataIso: dataIso,
      loja: loja,
      notaChave: notaChave,
    );
    debugPrint('🏪 Preço $valor salvo para produto $produtoId (loja: ${loja ?? "?"})');
    return id;
  }

  /// Insere um registro vinculado a uma loja cadastrada (loja_id).
  Future<int> inserirComLojaId({
    required int produtoId,
    required double preco,
    required int lojaId,
    String? dataIso,
    String? notaChave,
  }) async {
    final db = await BancoDados().banco;
    final id = await db.insert('registros', {
      'produto_id': produtoId,
      'preco': preco,
      'data': dataIso ?? agoraIso(),
      'loja_id': lojaId,
      'nota_chave': notaChave,
    });
    return id;
  }

  /// Busca registros por produto (histórico completo), com nome da loja.
  Future<List<Map<String, dynamic>>> buscarPorProduto(int produtoId) async {
    return _historico(produtoId);
  }

  /// Retorna os últimos registros do produto.
  Future<List<Map<String, dynamic>>> historicoRecentes(
    int produtoId, {
    int limite = 10,
  }) async {
    return _historico(produtoId, limite: limite);
  }

  Future<List<Map<String, dynamic>>> _historico(int produtoId, {int? limite}) async {
    final db = await BancoDados().banco;
    final possuiLojaId = await temColunaLojaId();
    final limitSql = limite != null ? ' LIMIT $limite' : '';

    final res = possuiLojaId
        ? await db.rawQuery(
            'SELECT r.*, l.nome AS loja_nome '
            'FROM registros r '
            'LEFT JOIN lojas l ON r.loja_id = l.id '
            'WHERE r.produto_id = ? '
            'ORDER BY r.data DESC$limitSql',
            [produtoId],
          )
        : await db.query(
            'registros',
            where: 'produto_id = ?',
            whereArgs: [produtoId],
            orderBy: 'data DESC',
            limit: limite,
          );

    debugPrint('📜 ${res.length} registros para produto $produtoId');
    return res;
  }

  Future<int> excluirPorIds(Iterable<int> ids) async {
    final lista = ids.toList();
    if (lista.isEmpty) return 0;
    final db = await BancoDados().banco;
    final placeholders = List.filled(lista.length, '?').join(',');
    return db.delete(
      'registros',
      where: 'id IN ($placeholders)',
      whereArgs: lista,
    );
  }
}
