import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'banco_dados.dart';

/// DAO de Produtos com:
/// - inserir (get-or-create): evita duplicados e sempre retorna o id real
/// - buscarPorNome: case-insensitive + escapa '%' e '_' no LIKE
/// - buscarPorEan / buscarPorId
/// - wrapper inserirProduto(nome) para compatibilidade
/// - EXCLUSÃO segura (apaga registros -> produto) em transação
class ProdutosDAO {
  Future<Database> get _db async => await BancoDados().banco;

  // ========= INSERIR =========

  /// Insere um produto e SEMPRE retorna o id do registro existente/criado.
  /// - Se já existir (por EAN ou nome igual ignorando maiúsculas), retorna o id existente.
  /// - Se não existir, cria e retorna o novo id.
  Future<int> inserir({String? ean, required String nome}) async {
    final db = await _db;
    final nomeLimpo = nome.trim();

    // 1) Tenta inserir (ignora conflito)
    final novoId = await db.insert(
      'produtos',
      {
        'ean': (ean?.trim().isEmpty ?? true) ? null : ean!.trim(),
        'nome': nomeLimpo,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    if (novoId != 0) {
      // Inseriu de primeira
      debugPrint('💾 Produto salvo com id: $novoId');
      return novoId;
    }

    // 2) Se não inseriu (provável duplicata), tente recuperar o id existente
    // 2a) Preferência: EAN
    if (ean != null && ean.trim().isNotEmpty) {
      final rEan = await db.query(
        'produtos',
        columns: ['id'],
        where: 'ean = ?',
        whereArgs: [ean.trim()],
        limit: 1,
      );
      if (rEan.isNotEmpty) {
        final id = rEan.first['id'] as int;
        debugPrint('ℹ️ Produto já existia (EAN). id: $id');
        return id;
      }
    }

    // 2b) Fallback: nome case-insensitive
    final rNome = await db.query(
      'produtos',
      columns: ['id'],
      where: 'LOWER(nome) = ?',
      whereArgs: [nomeLimpo.toLowerCase()],
      limit: 1,
    );
    if (rNome.isNotEmpty) {
      final id = rNome.first['id'] as int;
      debugPrint('ℹ️ Produto já existia (NOME). id: $id');
      return id;
    }

    // 3) Situação rara
    debugPrint('⚠️ Insert ignorado e registro não encontrado. Verifique índices/constraints.');
    return 0;
  }

  /// Wrapper para compatibilidade com o código da tela:
  /// permite chamar dao.inserirProduto(nome) do jeito que você já tinha.
  Future<int> inserirProduto(String nome, {String? ean}) {
    return inserir(ean: ean, nome: nome);
  }

  // ========= BUSCAS =========

  /// Busca produto por EAN exato.
  Future<Map<String, dynamic>?> buscarPorEan(String ean) async {
    final db = await _db;
    final res = await db.query(
      'produtos',
      where: 'ean = ?',
      whereArgs: [ean.trim()],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Busca por nome (contém), ignorando maiúsculas/minúsculas,
  /// escapando '%' e '_' para não “quebrar” o LIKE em termos literais.
  Future<List<Map<String, dynamic>>> buscarPorNome(String termo) async {
    final db = await _db;
    final termoLimpo = termo.trim();

    if (termoLimpo.isEmpty) {
      final res = await db.query(
        'produtos',
        orderBy: 'LOWER(nome) ASC',
        limit: 100,
      );
      debugPrint('Listando ${res.length} produtos (ordenados)');
      return res;
    }

    final like = '%${_escapeLike(termoLimpo.toLowerCase())}%';
    final res = await db.query(
      'produtos',
      where: 'LOWER(nome) LIKE ? ESCAPE \'\\\'',
      whereArgs: [like],
      orderBy: 'nome ASC',
      limit: 50,
    );

    debugPrint('🔍 BuscarPorNome("$termoLimpo") retornou ${res.length} resultados');
    return res;
  }

  /// Busca por id.
  Future<Map<String, dynamic>?> buscarPorId(int id) async {
    final db = await _db;
    final res = await db.query(
      'produtos',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  // ========= EXCLUSÃO (segura, em transação) =========

  /// Exclui um produto e todo o seu histórico na tabela 'registros'.
  /// Seguro mesmo sem FK ON DELETE CASCADE.
  Future<int> excluir(int id) async {
    final db = await _db;
    return await db.transaction<int>((txn) async {
      await txn.delete('registros', where: 'produto_id = ?', whereArgs: [id]);
      final apagados = await txn.delete('produtos', where: 'id = ?', whereArgs: [id]);
      return apagados; // 0 ou 1
    });
  }

  /// Exclui TODOS os produtos cujo nome seja exatamente igual (case-insensitive),
  /// removendo os registros de cada um antes.
  Future<int> excluirPorNomeExato(String nome) async {
    final db = await _db;
    final nomeLimpo = nome.trim();
    return await db.transaction<int>((txn) async {
      final idsMap = await txn.query(
        'produtos',
        columns: ['id'],
        where: 'LOWER(nome) = ?',
        whereArgs: [nomeLimpo.toLowerCase()],
      );
      int total = 0;
      for (final m in idsMap) {
        final id = m['id'] as int;
        await txn.delete('registros', where: 'produto_id = ?', whereArgs: [id]);
        total += await txn.delete('produtos', where: 'id = ?', whereArgs: [id]);
      }
      return total;
    });
  }

  /// Exclui TODOS os produtos cujo nome contenha o termo (case-insensitive),
  /// útil para “limpar” duplicatas do tipo "Arroz", "Arroz Tipo 1", etc.
  Future<int> excluirPorTermo(String termo) async {
    final db = await _db;
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return 0;

    final like = '%${_escapeLike(t)}%';
    return await db.transaction<int>((txn) async {
      final idsMap = await txn.query(
        'produtos',
        columns: ['id'],
        where: 'LOWER(nome) LIKE ? ESCAPE \'\\\'',
        whereArgs: [like],
      );
      int total = 0;
      for (final m in idsMap) {
        final id = m['id'] as int;
        await txn.delete('registros', where: 'produto_id = ?', whereArgs: [id]);
        total += await txn.delete('produtos', where: 'id = ?', whereArgs: [id]);
      }
      return total;
    });
  }

  // ========= AUXILIARES =========

  /// Escapa caracteres especiais do LIKE ('%' e '_') usando barra invertida.
  /// Ex.: '10% de desconto' -> '10\% de desconto'
  String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\') // escapa a própria barra primeiro
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  // ========= SUGESTÃO DE ÍNDICES (chame NO onCreate/onUpgrade) =========

  /// Opcional: helper para criar índices/uniques que ajudam a evitar duplicados
  /// e aceleram buscas. Chame dentro do onCreate/onUpgrade do seu BancoDados.
  static Future<void> criarIndices(Database db) async {
    // Índice/constraint para EAN único (se fizer sentido no seu negócio)
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS ux_produtos_ean
      ON produtos(ean)
    ''');

    // Índice no nome com NOCASE para evitar duplicado por variação de caixa
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS ux_produtos_nome_nocase
      ON produtos(nome COLLATE NOCASE)
    ''');

    // Índice auxiliar para melhorar buscas por nome
    await db.execute('''
      CREATE INDEX IF NOT EXISTS ix_produtos_nome_lower
      ON produtos(LOWER(nome))
    ''');
  }


  /// Atualiza o nome do produto garantindo que não haja duplicado.
  /// Retorna true se o nome foi alterado com sucesso.
  Future<bool> atualizarNome({required int id, required String novoNome}) async {
    final db = await _db;
    final nome = novoNome.trim();
    if (nome.isEmpty) return false;

    // verifica se já existe outro produto com o mesmo nome (ignorando maiúsculas)
    final existe = await db.query(
      'produtos',
      columns: ['id'],
      where: 'LOWER(nome) = ? AND id <> ?',
      whereArgs: [nome.toLowerCase(), id],
      limit: 1,
    );

    if (existe.isNotEmpty) {
      // impede duplicado
      throw StateError('duplicado');
    }

    final linhas = await db.update(
      'produtos',
      {'nome': nome},
      where: 'id = ?',
      whereArgs: [id],
    );

    return linhas > 0;
  }

}
