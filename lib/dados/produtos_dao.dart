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
  ///
  /// A busca por existente acontece ANTES do insert. Isso é essencial para as
  /// notas fiscais: a NFC-e não traz o EAN (só o código interno do mercado),
  /// então um item que você já escaneou (ou marcou como granel) numa compra
  /// anterior precisa ser reconhecido pelo NOME — senão o app criaria um produto
  /// novo e vazio a cada nota, fazendo o item reaparecer como "sem EAN".
  Future<int> inserir({
    String? ean,
    required String nome,
    String? nomeOriginal,
    bool semCodigo = false,
  }) async {
    final db = await _db;
    final nomeLimpo = nome.trim();
    final eanLimpo = (ean?.trim().isEmpty ?? true) ? null : ean!.trim();

    // 1) GET — reaproveita produto já existente.
    // 1a) Preferência máxima: alguém já tem este EAN (identificador universal).
    if (eanLimpo != null) {
      final rEan = await db.query(
        'produtos',
        columns: ['id'],
        where: 'ean = ?',
        whereArgs: [eanLimpo],
        limit: 1,
      );
      if (rEan.isNotEmpty) {
        final id = rEan.first['id'] as int;
        debugPrint('ℹ️ Produto já existia (EAN). id: $id');
        return id;
      }
    }

    // 1b) Mesmo nome (case-insensitive). Se houver duplicatas, prefere a linha
    //     já resolvida: primeiro a que tem EAN, depois a marcada como granel e,
    //     por fim, a mais antiga — assim o status anterior é reaproveitado.
    final rNome = await db.query(
      'produtos',
      columns: ['id', 'ean'],
      where: 'LOWER(nome) = ?',
      whereArgs: [nomeLimpo.toLowerCase()],
      orderBy: "(ean IS NOT NULL AND ean <> '') DESC, "
          'COALESCE(sem_codigo, 0) DESC, id ASC',
      limit: 1,
    );
    if (rNome.isNotEmpty) {
      final existente = rNome.first;
      final id = existente['id'] as int;
      final eanExistente = (existente['ean'] ?? '').toString();

      // Se a nota trouxe um EAN e o produto ainda não tinha, enriquece-o.
      // (atualizarEan não sobrescreve nem quebra se o EAN for de outro produto.)
      if (eanLimpo != null && eanExistente.isEmpty) {
        await atualizarEan(id: id, ean: eanLimpo);
      }
      debugPrint('ℹ️ Produto já existia (NOME). id: $id');
      return id;
    }

    // 2) CREATE — não existe: cria.
    // nome_original preserva o nome cru (ex.: da NFC-e); por padrão = nome.
    final novoId = await db.insert(
      'produtos',
      {
        'ean': eanLimpo,
        'nome': nomeLimpo,
        'nome_original': (nomeOriginal ?? nome).trim(),
        'sem_codigo': semCodigo ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (novoId != 0) {
      debugPrint('💾 Produto salvo com id: $novoId');
      return novoId;
    }

    // 3) Corrida rara: o índice UNIQUE de EAN barrou o insert entre a checagem
    //    e agora. Recupera o id existente (por EAN e, se não, por nome).
    if (eanLimpo != null) {
      final rEan = await db.query(
        'produtos',
        columns: ['id'],
        where: 'ean = ?',
        whereArgs: [eanLimpo],
        limit: 1,
      );
      if (rEan.isNotEmpty) return rEan.first['id'] as int;
    }
    final r2 = await db.query(
      'produtos',
      columns: ['id'],
      where: 'LOWER(nome) = ?',
      whereArgs: [nomeLimpo.toLowerCase()],
      limit: 1,
    );
    if (r2.isNotEmpty) return r2.first['id'] as int;

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

  // ========= ÍNDICES E DE-DUPLICAÇÃO (usados nas migrações) =========

  /// Cria os índices de produtos. Chamado no onCreate/onUpgrade do [BancoDados].
  /// - EAN é único APENAS quando informado (índice parcial), permitindo vários
  ///   produtos sem EAN (criados manualmente por nome).
  /// - Nome ganha índice case-insensitive para acelerar buscas (não-único, pois
  ///   marcas diferentes podem ter nomes iguais).
  static Future<void> criarIndices(Database db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_produtos_ean '
      'ON produtos(ean) WHERE ean IS NOT NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_produtos_nome_nocase '
      'ON produtos(nome COLLATE NOCASE)',
    );
  }

  /// Funde produtos duplicados que tenham o MESMO ean (não nulo), mantendo o
  /// menor id e re-apontando os registros de preço. Necessário antes de criar
  /// o índice UNIQUE de EAN em bancos que já acumularam duplicatas.
  static Future<void> dedupPorEan(Database db) async {
    // Re-aponta registros dos duplicados para o menor id de cada EAN.
    await db.execute('''
      UPDATE registros
         SET produto_id = (
           SELECT MIN(p2.id) FROM produtos p2
            WHERE p2.ean = (SELECT ean FROM produtos p1 WHERE p1.id = registros.produto_id)
              AND p2.ean IS NOT NULL
         )
       WHERE produto_id IN (
         SELECT p.id FROM produtos p
          WHERE p.ean IS NOT NULL
            AND p.id > (SELECT MIN(p3.id) FROM produtos p3 WHERE p3.ean = p.ean)
       )
    ''');
    // Remove os produtos duplicados (mantém o menor id por EAN).
    await db.execute('''
      DELETE FROM produtos
       WHERE ean IS NOT NULL
         AND id > (SELECT MIN(p.id) FROM produtos p WHERE p.ean = produtos.ean)
    ''');
  }

  /// Consolida produtos duplicados de MESMO nome (case-insensitive) que foram
  /// criados por importações de nota antes do get-or-create por nome.
  ///
  /// Para cada nome, elege um produto "canônico" — preferindo o que tem EAN,
  /// depois o marcado como granel e, por fim, o mais antigo — e funde nele
  /// APENAS as cópias sem EAN (re-apontando os preços e apagando as cópias).
  /// Linhas com EAN próprio distinto são preservadas (podem ser produtos
  /// diferentes com o mesmo nome). Assim, notas já importadas passam a exibir
  /// o EAN/granel que você já havia registrado, sem reescanear.
  ///
  /// O canônico é escolhido pela mesma regra usada em [inserir], então a fusão
  /// é consistente com o comportamento de novas importações.
  static Future<void> dedupPorNome(Database db) async {
    // Expressão que elege o id canônico para um dado nome (LOWER).
    const canonicoDoNome = '''
      SELECT p.id FROM produtos p
       WHERE LOWER(p.nome) = LOWER(d.nome)
       ORDER BY (p.ean IS NOT NULL AND p.ean <> '') DESC,
                COALESCE(p.sem_codigo, 0) DESC,
                p.id ASC
       LIMIT 1
    ''';

    // 1) Re-aponta os preços das cópias SEM EAN para o produto canônico.
    await db.execute('''
      UPDATE registros
         SET produto_id = (
           SELECT ($canonicoDoNome)
             FROM produtos d WHERE d.id = registros.produto_id
         )
       WHERE produto_id IN (
         SELECT d.id FROM produtos d
          WHERE (d.ean IS NULL OR d.ean = '')
            AND d.id <> ($canonicoDoNome)
       )
    ''');

    // 2) Apaga as cópias SEM EAN que não são o canônico (os preços já saíram).
    await db.execute('''
      DELETE FROM produtos
       WHERE (ean IS NULL OR ean = '')
         AND id <> (
           SELECT p.id FROM produtos p
            WHERE LOWER(p.nome) = LOWER(produtos.nome)
            ORDER BY (p.ean IS NOT NULL AND p.ean <> '') DESC,
                     COALESCE(p.sem_codigo, 0) DESC,
                     p.id ASC
            LIMIT 1
         )
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

  /// Define o EAN de um produto (usado ao completar uma nota mais tarde).
  /// Retorna false se o EAN já pertence a outro produto.
  Future<bool> atualizarEan({required int id, required String ean}) async {
    final db = await _db;
    final limpo = ean.trim();
    if (limpo.isEmpty) return false;

    final outro = await db.query(
      'produtos',
      columns: ['id'],
      where: 'ean = ? AND id <> ?',
      whereArgs: [limpo, id],
      limit: 1,
    );
    if (outro.isNotEmpty) return false; // EAN já cadastrado em outro produto

    final linhas = await db.update(
      'produtos',
      {'ean': limpo, 'sem_codigo': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    return linhas > 0;
  }

  /// Marca/desmarca um produto como granel (sem código de barras).
  Future<void> marcarSemCodigo({required int id, required bool valor}) async {
    final db = await _db;
    await db.update(
      'produtos',
      {'sem_codigo': valor ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remove o EAN de um produto (volta a ficar sem código / pendente).
  Future<void> removerEan(int id) async {
    final db = await _db;
    await db.update(
      'produtos',
      {'ean': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
