import 'package:flutter/material.dart';
import 'package:consulta_preco/dados/produtos_dao.dart';
import 'package:consulta_preco/dados/registros_dao.dart';
import 'package:consulta_preco/dominio/status_preco.dart';
import 'package:consulta_preco/dominio/formatadores.dart';
import 'package:consulta_preco/dominio/ean.dart';
import 'package:consulta_preco/modelos/loja_model.dart';
import 'package:consulta_preco/servicos/loja_selecionada_store.dart';
import 'package:consulta_preco/telas/ler_ean_tela.dart';

class ProdutoDetalheTela extends StatefulWidget {
  final int produtoId;
  const ProdutoDetalheTela({super.key, required this.produtoId});

  @override
  State<ProdutoDetalheTela> createState() => _ProdutoDetalheTelaState();
}

class _ProdutoDetalheTelaState extends State<ProdutoDetalheTela> {
  final daoProdutos = ProdutosDAO();
  final daoRegistros = RegistrosDAO();
  final LojaSelecionadaStore _lojaStore = LojaSelecionadaStore.instance;

  LojaModel? _lojaSelecionada;
  bool selecionandoHistorico = false;
  final Set<int> registrosSelecionados = <int>{};
  final precoCtrl = TextEditingController();
  final lojaCtrl = TextEditingController();
  final cidadeCtrl = TextEditingController();

  Map<String, dynamic>? produto;
  List<Map<String, dynamic>> historico = [];
  String etiqueta = 'Sem base';
  Color corEtiqueta = Colors.grey;

  Future<void> _carregar() async {
    try {
      final p = await daoProdutos.buscarPorId(widget.produtoId);
      final h = await daoRegistros.historicoRecentes(
        widget.produtoId,
        limite: 10,
      );

      debugPrint(
        '🔎 produtoId=${widget.produtoId} carregado=${p != null} / histórico=${h.length}',
      );
      if (h.isNotEmpty) debugPrint('Exemplo linha: ${h.first}');

      if (!mounted) return;
      setState(() {
        produto = p;
        historico = h;
        final idsAtuais = h
            .map((e) => e['id'])
            .whereType<int>()
            .toSet();
        registrosSelecionados.removeWhere((id) => !idsAtuais.contains(id));
        if (registrosSelecionados.isEmpty) selecionandoHistorico = false;
      });
      _recalcularEtiqueta();
    } catch (e, st) {
      debugPrint('❌ Erro ao carregar detalhes: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao carregar produto')));
    }
  }

  void _recalcularEtiqueta() {
    // Aceita tanto preco_centavos (int) quanto preco (double)
    final ultimos = historico
        .map((e) {
          final pr = e['preco'];
          return pr is num ? (pr * 100).round() : null;
        })
        .whereType<int>()
        .toList();

    if (ultimos.isEmpty || precoCtrl.text.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        etiqueta = 'Sem base';
        corEtiqueta = Colors.grey;
      });
      return;
    }
    final atual = parseReaisParaCentavos(precoCtrl.text);
    final s = statusPreco(atual, ultimos);
    if (!mounted) return;
    setState(() {
      etiqueta = s;
      corEtiqueta = (s == 'Barato')
          ? Colors.green
          : (s == 'Caro')
          ? Colors.red
          : Colors.amber;
    });
  }

  Future<void> _salvar() async {
    if (precoCtrl.text.trim().isEmpty) return;
    late final int valorCentavos;
    // valida preco digitado antes de salvar
    try {
      valorCentavos = parseReaisParaCentavos(precoCtrl.text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pre\u00E7o inv\u00E1lido')));
      return;
    }
    try {
      final lojaSelecionada = _lojaSelecionada;
      final possuiColunaLojaId = lojaSelecionada?.id != null &&
          await daoRegistros.temColunaLojaId();

      if (possuiColunaLojaId && lojaSelecionada != null) {
        await daoRegistros.inserirComLojaId(
          produtoId: widget.produtoId,
          preco: valorCentavos / 100,
          lojaId: lojaSelecionada.id!,
        );
      } else {
        final fallbackLoja = lojaSelecionada?.nome ??
            (lojaCtrl.text.trim().isEmpty ? null : lojaCtrl.text.trim());
        await daoRegistros.salvarPreco(
          produtoId: widget.produtoId,
          precoCentavos: valorCentavos,
          loja: fallbackLoja,
          cidade: cidadeCtrl.text.trim().isEmpty
              ? null
              : cidadeCtrl.text.trim(),
        );
      }

      precoCtrl.clear();
      try {
        await _carregar();
      } catch (e) {
        debugPrint('Aviso: salvo, mas falhou recarregar: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pre\u00E7o salvo!')));
    } catch (e) {
      debugPrint('Erro ao salvar pre\u00E7o: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Erro ao salvar pre\u00E7o')));
    }
  }




  @override
  void initState() {
    super.initState();
    _lojaSelecionada = _lojaStore.value;
    _lojaStore.addListener(_sincronizarLojaSelecionada);
    _carregar();
    // Recalcula a etiqueta sempre que o usuário digitar o preço
    precoCtrl.addListener(_recalcularEtiqueta);
  }

  void _sincronizarLojaSelecionada() {
    final selecionada = _lojaStore.value;
    if (mounted) {
      setState(() {
        _lojaSelecionada = selecionada;
        if (selecionada != null) {
          lojaCtrl.clear();
          cidadeCtrl.clear();
        }
      });
    } else {
      _lojaSelecionada = selecionada;
    }
  }

  void _limparSelecaoHistorico() {
    setState(() {
      selecionandoHistorico = false;
      registrosSelecionados.clear();
    });
  }

  void _entrarSelecaoHistorico(int id) {
    setState(() {
      selecionandoHistorico = true;
      registrosSelecionados
        ..clear()
        ..add(id);
    });
  }

  void _alternarSelecaoHistorico(int id) {
    setState(() {
      if (!selecionandoHistorico) {
        selecionandoHistorico = true;
        registrosSelecionados.add(id);
        return;
      }
      if (!registrosSelecionados.remove(id)) {
        registrosSelecionados.add(id);
      }
      if (registrosSelecionados.isEmpty) {
        selecionandoHistorico = false;
      }
    });
  }

  Future<void> _excluirRegistrosSelecionados() async {
    if (registrosSelecionados.isEmpty) return;
    final confirmar = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Excluir registros selecionados'),
            content: Text(
              'Confirmar exclusão de ${registrosSelecionados.length} registro(s)?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmar) return;

    try {
      final removidos = await daoRegistros.excluirPorIds(registrosSelecionados);
      _limparSelecaoHistorico();
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removidos: $removidos registro(s)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir registros: $e')),
      );
    }
  }

  PreferredSizeWidget _buildAppBar() {
    if (!selecionandoHistorico) {
      return AppBar(title: const Text('Produto Detalhe'));
    }
    final total = registrosSelecionados.length;
    return AppBar(
      leading: IconButton(
        tooltip: 'Sair da seleção',
        icon: const Icon(Icons.close),
        onPressed: _limparSelecaoHistorico,
      ),
      title: Text('$total selecionado(s)'),
      actions: [
        IconButton(
          tooltip: 'Excluir selecionados',
          icon: const Icon(Icons.delete),
          onPressed: total > 0 ? _excluirRegistrosSelecionados : null,
        ),
      ],
    );
  }

  @override
  void dispose() {
    precoCtrl.dispose();
    lojaCtrl.dispose();
    cidadeCtrl.dispose();
    _lojaStore.removeListener(_sincronizarLojaSelecionada);
    super.dispose();
  }

  Widget _buildCabecalhoProduto() {
    final p = produto!;
    final nome = (p['nome'] ?? 'Produto').toString();
    final nomeOriginal = (p['nome_original'] ?? '').toString();
    final ean = (p['ean'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(nome, style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              tooltip: 'Renomear',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _renomearProduto,
            ),
          ],
        ),
        if (nomeOriginal.isNotEmpty &&
            nomeOriginal.toLowerCase() != nome.toLowerCase())
          Text('Nome na nota: $nomeOriginal',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.qr_code_2, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 6),
            Text(ean.isEmpty ? 'Sem EAN' : 'EAN: $ean'),
            const Spacer(),
            TextButton(
              onPressed: _editarEan,
              child: Text(ean.isEmpty ? 'Adicionar' : 'Editar'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _renomearProduto() async {
    final atual = (produto?['nome'] ?? '').toString();
    final ctrl = TextEditingController(text: atual);
    final novo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renomear produto'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome popular',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Salvar')),
        ],
      ),
    );
    ctrl.dispose();
    if (novo == null || novo.isEmpty || novo == atual) return;
    try {
      await daoProdutos.atualizarNome(id: widget.produtoId, novoNome: novo);
      await _carregar();
    } on StateError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Já existe um produto com esse nome.')),
      );
    }
  }

  Future<void> _editarEan() async {
    final temEan = (produto?['ean'] ?? '').toString().isNotEmpty;
    final acao = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.barcode_reader),
              title: const Text('Escanear código'),
              onTap: () => Navigator.pop(context, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard),
              title: const Text('Digitar código'),
              onTap: () => Navigator.pop(context, 'digitar'),
            ),
            if (temEan)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remover EAN'),
                onTap: () => Navigator.pop(context, 'remover'),
              ),
          ],
        ),
      ),
    );
    if (acao == null || !mounted) return;

    if (acao == 'remover') {
      await daoProdutos.removerEan(widget.produtoId);
      await _carregar();
      return;
    }

    String? ean;
    if (acao == 'scan') {
      ean = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const LerEanTela()),
      );
    } else {
      ean = await _pedirEanManual();
    }
    if (ean == null || !mounted) return;
    if (!eanValido(ean)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código de barras inválido.')),
      );
      return;
    }
    final ok = await daoProdutos.atualizarEan(id: widget.produtoId, ean: ean);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esse EAN já está em outro produto.')),
      );
      return;
    }
    await _carregar();
  }

  Future<String?> _pedirEanManual() async {
    final ctrl = TextEditingController(text: (produto?['ean'] ?? '').toString());
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Digitar EAN'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Código de barras',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (produto != null) _buildCabecalhoProduto(),
            const SizedBox(height: 12),

            // Campo de preço + etiqueta de status
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: precoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      // <-- sem const
                      labelText: 'Preço (R\$)',
                      hintText: 'Ex.: 12,99',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _salvar(),
                  ),
                ),
                const SizedBox(width: 12),
                Chip(
                  label: Text(etiqueta),
                  backgroundColor: corEtiqueta.withValues(alpha: 0.15),
                  shape: StadiumBorder(side: BorderSide(color: corEtiqueta)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Loja selecionada ou campos manuais
            if (_lojaSelecionada != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront),
                  title: Text(_lojaSelecionada!.nome),
                  subtitle: Text(
                    'Loja selecionada na tela inicial (ID: ${_lojaSelecionada!.id ?? '-'} · Local ${_lojaSelecionada!.localId})',
                  ),
                  trailing: const Icon(Icons.check_circle, color: Colors.green),
                ),
              )
            else ...[
              const Text('Informe a loja manualmente:'),
              const SizedBox(height: 8),
              TextField(
                controller: lojaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome da loja',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cidadeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Cidade',
                  border: OutlineInputBorder(),
                ),
              ),
            ],

            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar'),
            ),

            const SizedBox(height: 16),
            Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            // Lista de histórico
            Expanded(
              child: historico.isEmpty
                  ? const Center(child: Text('Sem histórico'))
                  : ListView.builder(
                      itemCount: historico.length,
                      itemBuilder: (_, i) {
                        final r = historico[i];

                        final pv = r['preco'];
                        final double? precoReais =
                            pv is num ? pv.toDouble() : null;

                        final data =
                            formatarDataIso((r['data'] ?? '').toString());

                        final lojaNome = (r['loja_nome'] ?? r['loja'])
                            ?.toString()
                            .trim();
                        final precoTexto = precoReais != null
                            ? 'R\$ ${precoReais.toStringAsFixed(2)}'
                            : 'Preço não informado';
                        final lojaTexto =
                            (lojaNome != null && lojaNome.isNotEmpty)
                                ? lojaNome
                                : 'Loja não informada';
                        final detalhes = data.isNotEmpty
                            ? 'Data: $data'
                            : 'Data não informada';

                        final id = (r['id'] as num?)?.toInt();
                        final selecionado =
                            id != null && registrosSelecionados.contains(id);

                        return Card(
                          color: selecionandoHistorico && selecionado
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                              : null,
                          child: ListTile(
                            leading: selecionandoHistorico
                                ? Checkbox(
                                    value: selecionado,
                                    onChanged: id == null
                                        ? null
                                        : (_) =>
                                            _alternarSelecaoHistorico(id),
                                  )
                                : const Icon(Icons.history),
                            title: Text('$precoTexto - $lojaTexto'),
                            subtitle: Text(detalhes),
                            selected: selecionado,
                            onTap: () {
                              if (!selecionandoHistorico || id == null) return;
                              _alternarSelecaoHistorico(id);
                            },
                            onLongPress: id == null
                                ? null
                                : () => _entrarSelecaoHistorico(id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}




