import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class BancoDados {
  static final BancoDados _instancia = BancoDados._();
  BancoDados._();
  factory BancoDados() => _instancia;

  static const _dbNome = 'consulta_preco.db';
  // ⬇️ AUMENTE A VERSÃO (deixe em 3, como combinamos)
  static const _dbVersion = 3;

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
    // Tabela produtos (mantendo sua estrutura original)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS produtos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ean TEXT,
        nome TEXT NOT NULL
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
  }
}
