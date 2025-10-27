import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class BancoDados {
  static final BancoDados _instancia = BancoDados._interno();
  Database? _db;

  factory BancoDados() => _instancia;
  BancoDados._interno();

  Future<Database> get banco async {
    if (_db != null) return _db!;
    _db = await _abrir();
    return _db!;
  }

  Future<Database> _abrir() async {
    final dir = await getDatabasesPath();
    final caminho = p.join(dir, 'consulta_preco.db');
    return await openDatabase(
      caminho,
      version: 2, // 👈 aumenta a versão para recriar o banco
      onCreate: (db, version) async {
        await _criarTabelas(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _recriarTabelas(db);
      },
    );
  }

  Future<void> _criarTabelas(Database db) async {
    // Tabela de produtos
    await db.execute('''
      CREATE TABLE produtos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        ean TEXT
      );
    ''');

    // Tabela de registros de preços
    await db.execute('''
      CREATE TABLE registros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        produto_id INTEGER NOT NULL,
        preco REAL NOT NULL,
        data TEXT NOT NULL,
        loja TEXT,
        FOREIGN KEY (produto_id) REFERENCES produtos (id) ON DELETE CASCADE
      );
    ''');

    print('✅ Tabelas criadas com sucesso');
  }

  Future<void> _recriarTabelas(Database db) async {
    // Remove antigas (durante testes)
    await db.execute('DROP TABLE IF EXISTS registros;');
    await db.execute('DROP TABLE IF EXISTS produtos;');
    await _criarTabelas(db);
  }
}
