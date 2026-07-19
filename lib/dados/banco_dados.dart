import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'produtos_dao.dart';

class BancoDados {
  static final BancoDados _instancia = BancoDados._();
  BancoDados._();
  factory BancoDados() => _instancia;

  static const _dbNome = 'consulta_preco.db';
  static const _dbVersion = 6;

  Database? _db;
  Future<Database> get banco async => _db ??= await _abrir();

  Future<Database> _abrir() async {
    final caminho = await getDatabasesPath();
    final dbPath = p.join(caminho, _dbNome);
    return openDatabase(
      dbPath,
      version: _dbVersion,
      // ✅ Garante Foreign Keys no SQLite
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Tabela produtos. `nome` é o de exibição (popular, editável);
    // `nome_original` preserva o nome cru vindo da NFC-e/SEFAZ.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS produtos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ean TEXT,
        nome TEXT NOT NULL,
        nome_original TEXT,
        sem_codigo INTEGER NOT NULL DEFAULT 0
      );
    ''');

    // Tabela registros (mantendo colunas legadas e já prevendo loja_id)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS registros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        produto_id INTEGER NOT NULL,
        preco REAL NOT NULL,
        data TEXT NOT NULL,
        loja TEXT,         -- legado (mantido por compat)
        loja_id INTEGER,   -- novo
        nota_chave TEXT,   -- chave da NFC-e de origem (quando veio de nota)
        FOREIGN KEY(produto_id) REFERENCES produtos(id) ON DELETE CASCADE
        -- FOREIGN KEY(loja_id) REFERENCES lojas(id) ON DELETE SET NULL -- será válido após criarmos lojas
      );
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_reg_produto ON registros(produto_id);');

    // ⬇️ Novas tabelas para Local/Loja
    await db.execute('''
      CREATE TABLE IF NOT EXISTS locais (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        raio_metros REAL NOT NULL DEFAULT 150,
        criado_em TEXT DEFAULT CURRENT_TIMESTAMP
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lojas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_id INTEGER NOT NULL,
        nome TEXT NOT NULL,
        criado_em TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(local_id) REFERENCES locais(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_lojas_local ON lojas(local_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_reg_loja_id ON registros(loja_id);');

    // v4: índices de produtos (EAN único parcial + nome case-insensitive)
    await ProdutosDAO.criarIndices(db);

    // v4: notas fiscais já importadas (evita reimportar a mesma NFC-e)
    await _criarTabelaNotas(db);
  }

  Future<void> _criarTabelaNotas(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notas_importadas (
        chave TEXT PRIMARY KEY,
        emitente TEXT,
        importada_em TEXT NOT NULL,
        total REAL,
        qtd_itens INTEGER
      );
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // 🚫 NÃO RECRIAR TABELAS! Só migrar.
    if (oldV < 2) {
      // v2: adiciona loja_id + índice
      await db.execute('ALTER TABLE registros ADD COLUMN loja_id INTEGER;');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_reg_loja_id ON registros(loja_id);');
    }
    if (oldV < 3) {
      // v3: cria locais e lojas (se ainda não existem)
      await db.execute('''
        CREATE TABLE IF NOT EXISTS locais (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          raio_metros REAL NOT NULL DEFAULT 150,
          criado_em TEXT DEFAULT CURRENT_TIMESTAMP
        );
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS lojas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          local_id INTEGER NOT NULL,
          nome TEXT NOT NULL,
          criado_em TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(local_id) REFERENCES locais(id) ON DELETE CASCADE
        );
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_lojas_local ON lojas(local_id);');
    }
    if (oldV < 4) {
      // v4: funde duplicatas por EAN e cria os índices de produtos.
      // A de-duplicação precisa rodar ANTES do índice UNIQUE, senão ele falha
      // em bancos que já acumularam produtos repetidos.
      await ProdutosDAO.dedupPorEan(db);
      await ProdutosDAO.criarIndices(db);
      await _criarTabelaNotas(db);
    }
    if (oldV < 5) {
      // v5: nome popular vs original; vínculo registro→nota; resumo da nota.
      await _addColuna(db, 'produtos', 'nome_original', 'TEXT');
      await db.execute(
        'UPDATE produtos SET nome_original = nome WHERE nome_original IS NULL;',
      );
      await _addColuna(db, 'registros', 'nota_chave', 'TEXT');
      await _addColuna(db, 'notas_importadas', 'total', 'REAL');
      await _addColuna(db, 'notas_importadas', 'qtd_itens', 'INTEGER');
    }
    if (oldV < 6) {
      // v6: marca itens a granel / sem código de barras (distingue de "pendente").
      await _addColuna(db, 'produtos', 'sem_codigo', 'INTEGER NOT NULL DEFAULT 0');
    }
  }

  /// Adiciona uma coluna apenas se ela ainda não existir (migração idempotente).
  Future<void> _addColuna(
    Database db,
    String tabela,
    String coluna,
    String tipo,
  ) async {
    final cols = await db.rawQuery("PRAGMA table_info('$tabela')");
    final existe = cols.any((c) => c['name'] == coluna);
    if (!existe) {
      await db.execute('ALTER TABLE $tabela ADD COLUMN $coluna $tipo;');
    }
  }
}
