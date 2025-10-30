import 'package:flutter/foundation.dart';
import 'banco_dados.dart';

class RegistrosDAO {
  /// Insere um novo registro de preço
  Future<int> inserir({
    required int produtoId,
    required double preco,
    required String dataIso, // exemplo: '2025-10-27'
    String? loja,
    String? cidade,
  }) async {
    final db = await BancoDados().banco;
    final id = await db.insert('registros', {
      'produto_id': produtoId,
      'preco': preco,
      'data': dataIso,
      'loja': loja, // mantém loja (compat com tabela atual)
    });

    debugPrint('💾 Registro inserido com id: $id (produto $produtoId)');
    return id;
  }

  /// Busca registros por produto (histórico completo)
  Future<List<Map<String, dynamic>>> buscarPorProduto(int produtoId) async {
    final db = await BancoDados().banco;
    final res = await db.query(
      'registros',
      where: 'produto_id = ?',
      whereArgs: [produtoId],
      orderBy: 'data DESC',
    );
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
    final res = await db.query(
      'registros',
      where: 'produto_id = ?',
      whereArgs: [produtoId],
      orderBy: 'data DESC',
      limit: limite,
    );
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

    await db.insert('registros', {
      'produto_id': produtoId,
      'preco': valor,
      'data': dataIso,
      'loja': loja, // mantém loja
      // 'cidade': cidade, // REMOVER
    });

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
    final id = await db.insert('registros', {
      'produto_id': produtoId,
      'preco': preco,
      'data': dataIso,
      'loja_id': lojaId,
    });
    return id;
  }
}
