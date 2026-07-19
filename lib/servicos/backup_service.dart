import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../dados/banco_dados.dart';

/// Exporta e importa o arquivo SQLite do app (backup manual entre celulares).
///
/// O celular "principal" exporta pelo compartilhar do Android (WhatsApp,
/// OneDrive etc.); o outro celular importa o arquivo recebido, que SUBSTITUI
/// o banco local inteiro.
class BackupService {
  static const _assinaturaSqlite = 'SQLite format 3';

  /// Copia o banco para um arquivo datado e abre a tela de compartilhar.
  /// Retorna o nome do arquivo exportado.
  Future<String> exportar() async {
    final bd = BancoDados();
    final origem = await bd.caminhoArquivo();
    if (!File(origem).existsSync()) {
      throw Exception('Ainda não há banco de dados para exportar.');
    }

    // Fecha para garantir que tudo esteja gravado no arquivo antes da cópia.
    await bd.fechar();

    final agora = DateTime.now();
    final data =
        '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
    final nome = 'consulta_preco_backup_$data.db';

    final tmp = await getTemporaryDirectory();
    final copia = await File(origem).copy(p.join(tmp.path, nome));

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(copia.path, mimeType: 'application/octet-stream')],
        text: 'Backup do Consulta de Preço ($data)',
      ),
    );
    return nome;
  }

  /// Abre o seletor de arquivos e devolve o escolhido (null se cancelou).
  Future<XFile?> escolherArquivo() => openFile();

  /// Substitui o banco local pelo [arquivo] importado.
  ///
  /// Antes de sobrescrever, valida que o arquivo é um SQLite de verdade e
  /// guarda uma cópia de segurança do banco atual (.anterior.db), para o
  /// caso de o usuário importar a coisa errada.
  Future<void> importar(XFile arquivo) async {
    final bytes = await arquivo.openRead(0, _assinaturaSqlite.length).first;
    if (String.fromCharCodes(bytes) != _assinaturaSqlite) {
      throw Exception(
        'O arquivo escolhido não é um backup válido do Consulta de Preço.',
      );
    }

    final bd = BancoDados();
    final destino = await bd.caminhoArquivo();
    await bd.fechar();

    final atual = File(destino);
    if (atual.existsSync()) {
      await atual.copy('$destino.anterior.db');
    }

    await arquivo.saveTo(destino);

    // Descarta diários de transação do banco antigo, se existirem —
    // misturados com o arquivo novo, corromperiam o banco.
    for (final sufixo in ['-journal', '-wal', '-shm']) {
      final f = File('$destino$sufixo');
      if (f.existsSync()) await f.delete();
    }

    // Reabre já validando: se o backup for de versão antiga do app,
    // as migrações rodam aqui.
    await bd.banco;
  }
}
