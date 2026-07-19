import 'package:flutter/material.dart';

import 'package:consulta_preco/dados/notas_dao.dart';
import 'package:consulta_preco/dados/produtos_dao.dart';
import 'package:consulta_preco/dominio/formatadores.dart';
import 'package:consulta_preco/telas/ler_ean_tela.dart';
import 'package:consulta_preco/telas/escanear_bolsa_tela.dart';
import 'package:consulta_preco/telas/produto_detalhe_tela.dart';

class HistoricoNotasTela extends StatefulWidget {
  const HistoricoNotasTela({super.key});

  @override
  State<HistoricoNotasTela> createState() => _HistoricoNotasTelaState();
}

class _HistoricoNotasTelaState extends State<HistoricoNotasTela> {
  final _dao = NotasDAO();
  List<Map<String, dynamic>> _notas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final notas = await _dao.listarComProgresso();
    if (!mounted) return;
    setState(() {
      _notas = notas;
      _carregando = false;
    });
  }

  Future<void> _abrirNota(Map<String, dynamic> nota) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NotaDetalheTela(nota: nota)),
    );
    await _carregar(); // atualiza o status ao voltar
  }

  Future<bool> _confirmarExclusao(Map<String, dynamic> nota) async {
    final chave = (nota['chave'] ?? '').toString();
    final comEan = await _dao.produtosComEan(chave);
    if (!mounted) return false;

    final escolha = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir nota'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(comEan.isEmpty
                ? 'Remover esta nota e os preços que ela registrou?'
                : 'Esta nota tem ${comEan.length} item(ns) que você já '
                    'escaneou o EAN:'),
            if (comEan.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...comEan.take(5).map(
                    (n) => Text('• $n', style: const TextStyle(fontSize: 12)),
                  ),
              if (comEan.length > 5)
                Text('• … e mais ${comEan.length - 5}',
                    style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Deseja excluir os produtos também?'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancelar'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'so_nota'),
            child: const Text('Só a nota'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'tudo'),
            child: const Text('Nota + produtos'),
          ),
        ],
      ),
    );
    if (escolha == null || escolha == 'cancelar') return false;
    await _dao.excluirNota(chave, manterProdutos: escolha == 'so_nota');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notas Escaneadas')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _notas.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma nota importada ainda.\nUse "Ler Nota Fiscal" na tela inicial.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _notas.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final n = _notas[i];
                    final total = (n['total'] as num?)?.toDouble();
                    final qtd = n['qtd_itens'] as int?;
                    final pendentes = (n['pendentes'] as int?) ?? 0;
                    return Dismissible(
                      key: ValueKey(n['chave']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: (_) => _confirmarExclusao(n),
                      onDismissed: (_) => setState(() => _notas.removeAt(i)),
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long),
                        title: Text((n['emitente'] ?? 'Nota fiscal').toString()),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatarDataIso((n['importada_em'] ?? '').toString())}'
                              '${qtd != null ? ' · $qtd itens' : ''}',
                            ),
                            const SizedBox(height: 2),
                            _badgeStatus(pendentes),
                          ],
                        ),
                        trailing: total != null
                            ? Text('R\$ ${total.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold))
                            : null,
                        onTap: () => _abrirNota(n),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _badgeStatus(int pendentes) {
    final completa = pendentes == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          completa ? Icons.check_circle : Icons.pending_outlined,
          size: 14,
          color: completa ? Colors.green : Colors.orange.shade800,
        ),
        const SizedBox(width: 4),
        Text(
          completa ? 'Completa' : 'Em progresso · $pendentes sem EAN',
          style: TextStyle(
            fontSize: 12,
            color: completa ? Colors.green : Colors.orange.shade800,
          ),
        ),
      ],
    );
  }
}

/// Detalhe de uma nota: permite continuar a revisão (escanear EAN / granel).
class NotaDetalheTela extends StatefulWidget {
  final Map<String, dynamic> nota;
  const NotaDetalheTela({super.key, required this.nota});

  @override
  State<NotaDetalheTela> createState() => _NotaDetalheTelaState();
}

class _NotaDetalheTelaState extends State<NotaDetalheTela> {
  final _notasDao = NotasDAO();
  final _produtosDao = ProdutosDAO();
  List<Map<String, dynamic>> _itens = [];
  bool _carregando = true;

  String get _chave => (widget.nota['chave'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final itens = await _notasDao.itensDaNota(_chave);
    if (!mounted) return;
    setState(() {
      _itens = itens;
      _carregando = false;
    });
  }

  Future<void> _escanearEan(int produtoId) async {
    final ean = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const LerEanTela()),
    );
    if (ean == null || !mounted) return;
    final ok = await _produtosDao.atualizarEan(id: produtoId, ean: ean);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esse EAN já está em outro produto.')),
      );
      return;
    }
    await _carregar();
  }

  Future<void> _marcarGranel(int produtoId) async {
    await _produtosDao.marcarSemCodigo(id: produtoId, valor: true);
    await _carregar();
  }

  String _nomeComQtd(Map<String, dynamic> it) {
    final nome = (it['nome'] ?? '').toString();
    final qtd = (it['qtd_na_nota'] as int? ?? 1);
    return qtd > 1 ? '$nome  (${qtd}x)' : nome;
  }

  Future<void> _escanearGuiado() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EscanearBolsaTela(
          chave: _chave,
          titulo: (widget.nota['emitente'] ?? 'Nota fiscal').toString(),
        ),
      ),
    );
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = _itens.where((it) {
      final ean = (it['ean'] ?? '').toString();
      final granel = (it['sem_codigo'] as int? ?? 0) == 1;
      return ean.isEmpty && !granel;
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: Text((widget.nota['emitente'] ?? 'Nota fiscal').toString()),
      ),
      bottomNavigationBar: (!_carregando && pendentes > 0)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _escanearGuiado,
                  icon: const Icon(Icons.barcode_reader),
                  label: Text('Escanear guiado ($pendentes restantes)'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
            )
          : null,
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: pendentes == 0
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    pendentes == 0
                        ? 'Todos os itens revisados ✓'
                        : '$pendentes item(ns) sem EAN — escaneie ou marque como granel',
                    style: TextStyle(
                      color: pendentes == 0
                          ? Colors.green.shade800
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: _itens.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final it = _itens[i];
                      final preco = (it['preco'] as num?)?.toDouble();
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _nomeComQtd(it),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                                if (preco != null)
                                  Text('R\$ ${preco.toStringAsFixed(2)}'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _statusItem(it),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statusItem(Map<String, dynamic> it) {
    final produtoId = it['produto_id'] as int?;
    final ean = (it['ean'] ?? '').toString();
    final granel = (it['sem_codigo'] as int? ?? 0) == 1;

    if (ean.isNotEmpty) {
      return InkWell(
        onTap: produtoId == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProdutoDetalheTela(produtoId: produtoId),
                  ),
                ),
        child: Row(
          children: [
            const Icon(Icons.qr_code_2, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            Text('EAN: $ean', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    if (granel) {
      return Row(
        children: [
          const Icon(Icons.eco, size: 16, color: Colors.teal),
          const SizedBox(width: 4),
          const Text('Granel / sem código', style: TextStyle(fontSize: 12)),
          const Spacer(),
          if (produtoId != null)
            TextButton(
              onPressed: () async {
                await _produtosDao.marcarSemCodigo(id: produtoId, valor: false);
                await _carregar();
              },
              child: const Text('Desfazer'),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: produtoId == null ? null : () => _escanearEan(produtoId),
          icon: const Icon(Icons.barcode_reader, size: 18),
          label: const Text('Escanear EAN'),
        ),
        TextButton.icon(
          onPressed: produtoId == null ? null : () => _marcarGranel(produtoId),
          icon: const Icon(Icons.eco, size: 18),
          label: const Text('Granel'),
        ),
      ],
    );
  }
}
