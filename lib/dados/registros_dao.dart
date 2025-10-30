import 'package:flutter/foundation.dart';
import 'banco_dados.dart';

class RegistrosDAO {
  String? _dataColCache;
  String? _precoColCache;
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

  Future<String> _colunaData() async {
    if (_dataColCache != null) return _dataColCache!;
    final nomes = await _colunas();
    if (nomes.contains('data')) {
      _dataColCache = 'data';
    } else if (nomes.contains('data_iso')) {
      _dataColCache = 'data_iso';
    } else if (nomes.contains('created_at')) {
      _dataColCache = 'created_at';
    } else {
      _dataColCache = 'data';
    }
    return _dataColCache!;
  }

  Future<String> _colunaPreco() async {
    if (_precoColCache != null) return _precoColCache!;
    final nomes = await _colunas();
    if (nomes.contains('preco')) {
      _precoColCache = 'preco';
    } else if (nomes.contains('preco_centavos')) {
      _precoColCache = 'preco_centavos';
    } else {
      _precoColCache = 'preco';
    }
    return _precoColCache!;
  }

  Future<bool> temColunaLojaId() async => (await _colunas()).contains('loja_id');
  /// Insere um novo registro de preço
  Future<int> inserir({
    required int produtoId,
    required double preco,
    required String dataIso, // exemplo: '2025-10-27'
    String? loja,
    String? cidade,
  }) async {
    final db = await BancoDados().banco;
    final dataCol = await _colunaData();
    final precoCol = await _colunaPreco();
    final map = <String, Object?>{
      'produto_id': produtoId,
      precoCol: precoCol == 'preco' ? preco : (preco * 100).round(),
      dataCol: dataIso,
      'loja': loja, // mantém loja (compat com tabela atual)
    };
    final id = await db.insert('registros', map);

    debugPrint('💾 Registro inserido com id: $id (produto $produtoId)');
    return id;
  }

  /// Busca registros por produto (histórico completo)
  Future<List<Map<String, dynamic>>> buscarPorProduto(int produtoId) async {
    final db = await BancoDados().banco;
    final dataCol = await _colunaData();
    final possuiLojaId = await temColunaLojaId();
    List<Map<String, dynamic>> res;
    if (possuiLojaId) {
      res = await db.rawQuery(
        'SELECT r.*, l.nome AS loja_nome '
        'FROM registros r '
        'LEFT JOIN lojas l ON r.loja_id = l.id '
        'WHERE r.produto_id = ? '
        'ORDER BY r.$dataCol DESC',
        [produtoId],
      );
    } else {
      res = await db.query(
        'registros',
        where: 'produto_id = ?',
        whereArgs: [produtoId],
        orderBy: '$dataCol DESC',
      );
    }
    debugPrint(
      '📜 Encontrados ${res.length} registros para produto $produtoId',
    );
    return res;
  }

  /// Método compatível com versões antigas: retorna últimos registros
  Future<List<Map<String, dynamic>>> historicoRecentes(
    int produtoId, {
    int limite = 10,
  }) async {
    final db = await BancoDados().banco;
    final dataCol = await _colunaData();
    final possuiLojaId = await temColunaLojaId();
    List<Map<String, dynamic>> res;
    if (possuiLojaId) {
      res = await db.rawQuery(
        'SELECT r.*, l.nome AS loja_nome '
        'FROM registros r '
        'LEFT JOIN lojas l ON r.loja_id = l.id '
        'WHERE r.produto_id = ? '
        'ORDER BY r.$dataCol DESC '
        'LIMIT ?',
        [produtoId, limite],
      );
    } else {
      res = await db.query(
        'registros',
        where: 'produto_id = ?',
        whereArgs: [produtoId],
        orderBy: '$dataCol DESC',
        limit: limite,
      );
    }
    debugPrint('📊 Últimos ${res.length} registros do produto $produtoId');
    return res;
  }

  /// Salva o preço de um produto (aceita preco, precoCentavos, loja e cidade)
  Future<void> salvarPreco({
    required int produtoId,
    double? preco,
    int? precoCentavos,
    String? loja,
    String? cidade,
  }) async {
    final db = await BancoDados().banco;

    // Converte centavos em reais, se for o caso
    final valor = preco ?? (precoCentavos != null ? precoCentavos / 100 : 0);

    // Data atual (yyyy-MM-dd)
    final dataIso = DateTime.now().toIso8601String().split('T').first;
    final dataCol = await _colunaData();
    final precoCol = await _colunaPreco();

    final map = <String, Object?>{
      'produto_id': produtoId,
      precoCol: precoCol == 'preco' ? valor : (valor * 100).round(),
      dataCol: dataIso,
      'loja': loja, // mantém loja
      // 'cidade': cidade,
    };
    await db.insert('registros', map);

    debugPrint(
      '🏪 Preço $valor salvo para produto $produtoId (loja: ${loja ?? "?"}, cidade: ${cidade ?? "?"})',
    );
  }

  Future<int> inserirComLojaId({
    required int produtoId,
    required double preco,
    required String dataIso,
    required int lojaId,
  }) async {
    final db = await BancoDados().banco;
    final dataCol = await _colunaData();
    final precoCol = await _colunaPreco();
    final map = <String, Object?>{
      'produto_id': produtoId,
      precoCol: precoCol == 'preco' ? preco : (preco * 100).round(),
      dataCol: dataIso,
      'loja_id': lojaId,
    };
    final id = await db.insert('registros', map);
    return id;
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
