import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../dados/banco_dados.dart';
import '../dados/produtos_dao.dart';
import '../dados/registros_dao.dart';
import '../modelos/loja_model.dart';
import '../modelos/nota_fiscal_model.dart';

class ImportacaoResultado {
  final int itensImportados;
  final bool jaImportada;
  ImportacaoResultado({required this.itensImportados, required this.jaImportada});
}

/// Grava os itens de uma [NotaFiscal] como produtos + registros de preço.
///
/// O preço registrado é o **valor unitário** (preço por UN/KG), que é o que faz
/// sentido comparar entre lojas. Cada item vira/atualiza um produto (por nome,
/// pois a NFC-e traz só o código interno do mercado, não o EAN).
class ImportarNotaService {
  final _produtosDao = ProdutosDAO();
  final _registrosDao = RegistrosDAO();

  Future<bool> jaImportada(String? chave) async {
    if (chave == null) return false;
    final db = await BancoDados().banco;
    final r = await db.query(
      'notas_importadas',
      where: 'chave = ?',
      whereArgs: [chave],
      limit: 1,
    );
    return r.isNotEmpty;
  }

  Future<ImportacaoResultado> importar(
    NotaFiscal nota, {
    LojaModel? loja,
  }) async {
    final db = await BancoDados().banco;

    if (await jaImportada(nota.chaveAcesso)) {
      return ImportacaoResultado(itensImportados: 0, jaImportada: true);
    }

    final dataIso = RegistrosDAO.agoraIso();
    final usarLojaId =
        loja?.id != null && await _registrosDao.temColunaLojaId();

    final chave = nota.chaveAcesso;
    int importados = 0;
    for (final item in nota.itens) {
      final produtoId = await _produtosDao.inserir(
        ean: item.ean,
        nome: item.nome,
        nomeOriginal: item.nome,
        semCodigo: item.semCodigo,
      );
      if (produtoId == 0) continue;

      if (usarLojaId) {
        await _registrosDao.inserirComLojaId(
          produtoId: produtoId,
          preco: item.valorUnitario,
          lojaId: loja!.id!,
          dataIso: dataIso,
          notaChave: chave,
        );
      } else {
        await _registrosDao.salvarPreco(
          produtoId: produtoId,
          preco: item.valorUnitario,
          loja: loja?.nome ?? nota.emitente,
          dataIso: dataIso,
          notaChave: chave,
        );
      }
      importados++;
    }

    if (chave != null) {
      await db.insert(
        'notas_importadas',
        {
          'chave': chave,
          'emitente': nota.emitente,
          'importada_em': dataIso,
          'total': nota.total,
          'qtd_itens': nota.itens.length,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    debugPrint('🧾 Nota importada: $importados itens (loja: ${loja?.nome ?? nota.emitente})');
    return ImportacaoResultado(itensImportados: importados, jaImportada: false);
  }
}
