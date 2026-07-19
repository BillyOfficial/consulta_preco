import 'package:consulta_preco/telas/produto_detalhe_tela.dart';
import 'package:flutter/material.dart';
import 'package:consulta_preco/dados/produtos_dao.dart';

class PesquisarProdutoTela extends StatefulWidget {
  const PesquisarProdutoTela({super.key});

  @override
  State<PesquisarProdutoTela> createState() => _PesquisarProdutoTelaState();
}

class _PesquisarProdutoTelaState extends State<PesquisarProdutoTela> {
  final campoBusca = TextEditingController();
  final dao = ProdutosDAO();

  bool carregando = false;
  List<Map<String, dynamic>> resultados = [];
  int _buscaToken = 0;

  @override
  void initState() {
    super.initState();
    buscar();
  }

  // ---- multi-seleção ----
  bool selecionando = false;
  final Set<int> selecionados = <int>{};

  // retorna o id quando há exatamente 1 item selecionado; senão, null
  int? get _idSelecionadoUnico =>
      selecionados.length == 1 ? selecionados.first : null;

  Future<void> buscar() async {
    final termo = campoBusca.text.trim();
    final tokenAtual = ++_buscaToken;

    if (!mounted) return;
    setState(() => carregando = true);

    try {
      final dados = await dao.buscarPorNome(termo);
      debugPrint(
        'BuscarPorNome("$termo") retornou ${dados.length} resultados',
      );

      if (!mounted || tokenAtual != _buscaToken) return;
      setState(() {
        resultados = dados;
        carregando = false;

        final visiveis = dados.map<int>((m) => m['id'] as int).toSet();
        selecionados.removeWhere((id) => !visiveis.contains(id));
        if (selecionados.isEmpty) selecionando = false;
      });
    } catch (e) {
      debugPrint('? Erro ao buscar: $e');
      if (!mounted || tokenAtual != _buscaToken) return;
      setState(() => carregando = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao buscar produtos')));
    }
  }


  Future<void> criarProdutoRapido() async {
    final nome = campoBusca.text.trim();
    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite o nome do produto no campo acima.')),
      );
      return;
    }

    try {
      final id = await dao.inserir(nome: nome);
      if (!mounted) return;
      // Abre o produto recém-criado para já adicionar EAN e o primeiro preço.
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProdutoDetalheTela(produtoId: id)),
      );
      if (!mounted) return;
      await buscar();
    } catch (e, st) {
      debugPrint('❌ Erro ao criar produto: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao criar produto')));
    }
  }

  /// Espaço reservado para a futura foto do produto.
  Widget _placeholderFoto() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade400, size: 22),
    );
  }

  // ---- helpers de seleção ----
  void _limparSelecao() {
    selecionando = false;
    selecionados.clear();
  }

  void _entrarSelecaoCom(int id) {
    setState(() {
      selecionando = true;
      selecionados
        ..clear()
        ..add(id);
    });
  }

  void _alternarSelecao(int id) {
    setState(() {
      if (selecionados.remove(id)) {
        if (selecionados.isEmpty) selecionando = false;
      } else {
        selecionados.add(id);
      }
    });
  }

  void _selecionarTudo() {
    setState(() {
      selecionando = true;
      selecionados
        ..clear()
        ..addAll(resultados.map<int>((m) => m['id'] as int));
    });
  }

  Future<void> _editarSelecionado() async {
    // pega o id do único item selecionado
    if (selecionados.length != 1) return;
    final id = selecionados.first;

    // busca o nome atual para preencher no campo de texto
    final atual = await dao.buscarPorId(id);
    final nomeAtual = (atual?['nome'] ?? '').toString();

    final ctrl = TextEditingController(text: nomeAtual);

    // abre o diálogo para digitar o novo nome
    if (!mounted) return;
    final novoNome = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renomear produto'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Novo nome',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (novoNome == null || novoNome.isEmpty || novoNome == nomeAtual) return;

    try {
      final ok = await dao.atualizarNome(id: id, novoNome: novoNome);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('✅ Renomeado para "$novoNome"')));
        _limparSelecao();
        await buscar();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nada alterado.')));
      }
    } on StateError catch (e) {
      if (e.message == 'duplicado') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Já existe um produto com esse nome.')),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao renomear produto.')),
        );
      }
    } catch (e, st) {
      debugPrint('❌ Erro ao renomear: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro inesperado ao renomear')),
      );
    }
  }

  Future<void> _excluirSelecionados() async {
    if (selecionados.isEmpty) return;
    final qtd = selecionados.length;

    final ok =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Excluir selecionados'),
            content: Text(
              'Confirmar exclusão de $qtd produto(s)? '
              'Os históricos também serão apagados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    try {
      // Versão compatível sem excluirVarios(): apaga um a um
      int removidos = 0;
      for (final id in selecionados) {
        removidos += await dao.excluir(id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('🗑️ Excluídos: $removidos')));
      _limparSelecao();
      await buscar();
    } catch (e, st) {
      debugPrint('❌ Erro ao excluir: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao excluir')));
    }
  }

  PreferredSizeWidget _buildAppBar() {
    if (!selecionando) {
      return AppBar(title: const Text('Pesquisar por Produto'));
    }

    final total = selecionados.length;
    final tudoSelecionado =
        resultados.isNotEmpty && selecionados.length == resultados.length;

    return AppBar(
      leading: IconButton(
        tooltip: 'Sair da seleção',
        icon: const Icon(Icons.close),
        onPressed: () => setState(_limparSelecao),
      ),
      title: Text('$total selecionado(s)'),
      actions: [
        if (_idSelecionadoUnico != null)
          IconButton(
            tooltip: 'Renomear',
            icon: const Icon(Icons.edit),
            onPressed: _editarSelecionado,
          ),
        IconButton(
          tooltip: tudoSelecionado ? 'Limpar seleção' : 'Selecionar tudo',
          icon: Icon(tudoSelecionado ? Icons.select_all : Icons.done_all),
          onPressed: () {
            if (tudoSelecionado) {
              setState(_limparSelecao);
            } else {
              _selecionarTudo();
            }
          },
        ),

        IconButton(
          tooltip: 'Excluir selecionados',
          icon: const Icon(Icons.delete),
          onPressed: _excluirSelecionados,
        ),
      ],
    );
  }

  @override
  void dispose() {
    campoBusca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      resizeToAvoidBottomInset: true,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: campoBusca,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => buscar(),
                      onChanged: (_) => buscar(),
                      decoration: const InputDecoration(
                        labelText: 'Nome do produto',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: buscar,
                    child: const Text('Buscar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (carregando) const LinearProgressIndicator(),

              Expanded(
                child: resultados.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhum produto encontrado',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 8),
                        itemCount: resultados.length,
                        itemBuilder: (_, i) {
                          final item = resultados[i];
                          final id = item['id'] as int;
                          final nome = (item['nome'] ?? '').toString();
                          final ean = item['ean']?.toString();
                          final granel = (item['sem_codigo'] as int? ?? 0) == 1;
                          final marcado = selecionados.contains(id);

                          final subtitulo = granel
                              ? 'Granel'
                              : (ean == null || ean.isEmpty)
                                  ? 'Sem EAN'
                                  : 'EAN: $ean';

                          return Card(
                            child: ListTile(
                              // Foto (placeholder) ou checkbox no modo seleção.
                              leading: selecionando
                                  ? Checkbox(
                                      value: marcado,
                                      onChanged: (_) => _alternarSelecao(id),
                                    )
                                  : _placeholderFoto(),

                              title: Text(nome.isEmpty ? 'Sem nome' : nome),
                              subtitle: Text(subtitulo),
                              trailing: selecionando
                                  ? null
                                  : const Icon(Icons.chevron_right),

                              // Tap alterna seleção quando selecionando; senão navega
                              onTap: () {
                                if (selecionando) {
                                  _alternarSelecao(id);
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ProdutoDetalheTela(produtoId: id),
                                    ),
                                  );
                                }
                              },

                              // Long press entra no modo seleção marcando este item
                              onLongPress: () => _entrarSelecaoCom(id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),

      // Rodapé “Criar rápido”: desabilita quando estiver selecionando
      bottomNavigationBar: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SafeArea(
          child: OutlinedButton.icon(
            onPressed: selecionando ? null : criarProdutoRapido,
            icon: const Icon(Icons.add),
            label: const Text('Cadastrar novo produto'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ),
      ),
    );
  }
}
