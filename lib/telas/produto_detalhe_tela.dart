import 'package:flutter/material.dart';
import 'package:consulta_preco/dados/produtos_dao.dart';
import 'package:consulta_preco/dados/registros_dao.dart';
import 'package:consulta_preco/dominio/status_preco.dart';
import 'package:consulta_preco/servicos/local_loja_service.dart';
import 'package:consulta_preco/widgets/selecionar_loja_sheet.dart';
import 'package:consulta_preco/modelos/local_model.dart';
import 'package:consulta_preco/modelos/loja_model.dart';

class ProdutoDetalheTela extends StatefulWidget {
  final int produtoId;
  const ProdutoDetalheTela({super.key, required this.produtoId});

  @override
  State<ProdutoDetalheTela> createState() => _ProdutoDetalheTelaState();
}

class _ProdutoDetalheTelaState extends State<ProdutoDetalheTela> {
  final daoProdutos = ProdutosDAO();
  final daoRegistros = RegistrosDAO();
  final _localLojaService = LocalLojaService();

  LocalModel? _localAtual; // ainda não usado na UI
  LojaModel? _lojaSelecionada;
  final bool _localComUmaLoja = false; // checkbox
  bool _processandoLocal = false;
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
          if (e.containsKey('preco_centavos')) {
            final v = e['preco_centavos'];
            if (v is int) return v;
          }
          final pr = e['preco'];
          if (pr is num) return (pr * 100).round();
          return null;
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

  Future<void> _detectarLocalESelecionarLoja() async {
    setState(() => _processandoLocal = true);
    try {
      // 1) Achar ou criar Local pelo GPS
      final local = await _localLojaService.acharOuCriarLocal();
      setState(() => _localAtual = local);

      // 2) Se marcou “Local com 1 loja?”, cria/pega uma única loja
      if (_localComUmaLoja) {
        final loja = await _localLojaService.getOuCriarLojaUnica(local.id!);
        setState(() => _lojaSelecionada = loja);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Local detectado: ${local.nome} · Loja: ${loja.nome}',
              ),
            ),
          );
        }
        return;
      }

      // 3) Caso contrário, abre o bottom-sheet para selecionar/Adicionar
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SelecionarLojaSheet(
          localId: local.id!,
          onSelecionar: (loja) {
            setState(() => _lojaSelecionada = loja);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Loja selecionada: ${loja.nome}')),
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao detectar local: $e')));
    } finally {
      if (mounted) setState(() => _processandoLocal = false);
    }
  }

  Future<void> _salvar() async {
    if (precoCtrl.text.trim().isEmpty) return;
    try {
      final valor = parseReaisParaCentavos(precoCtrl.text);

      // ✅ NOVO: se houver loja detectada/selecionada, usa loja_id
      if (_lojaSelecionada?.id != null) {
        await daoRegistros.inserirComLojaId(
          produtoId: widget.produtoId,
          preco: valor / 100, // se seu inserir usa REAL, divida por 100
          dataIso: DateTime.now().toIso8601String(),
          lojaId: _lojaSelecionada!.id!,
        );
      } else {
        // 🧩 Antigo: mantém compatibilidade
        await daoRegistros.salvarPreco(
          produtoId: widget.produtoId,
          precoCentavos: valor,
          loja: lojaCtrl.text.trim().isEmpty ? null : lojaCtrl.text.trim(),
          cidade: cidadeCtrl.text.trim().isEmpty
              ? null
              : cidadeCtrl.text.trim(),
        );
      }

      precoCtrl.clear();
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preço salvo!')));
    } catch (e, st) {
      debugPrint('❌ Erro ao salvar preço: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Erro ao salvar preço')));
    }
  }

  @override
  void initState() {
    super.initState();
    _carregar();
    // Recalcula a etiqueta sempre que o usuário digitar o preço
    precoCtrl.addListener(_recalcularEtiqueta);
  }

  @override
  void dispose() {
    precoCtrl.dispose();
    lojaCtrl.dispose();
    cidadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Produto Detalhe')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (produto != null)
              Text(
                (produto!['nome'] ?? 'Produto').toString(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
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

            // Botões de ação
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _processandoLocal
                        ? null
                        : _detectarLocalESelecionarLoja,
                    icon: _processandoLocal
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.place_outlined),
                    label: Text(
                      _lojaSelecionada == null
                          ? 'Detectar local / escolher loja'
                          : 'Loja: ${_lojaSelecionada!.nome}',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _salvar,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                ),
              ],
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

                        // preço: aceita 'preco_centavos' (int) ou 'preco' (double/num)
                        double? precoReais;
                        if (r.containsKey('preco_centavos')) {
                          final v = r['preco_centavos'];
                          if (v is int) precoReais = v / 100.0;
                        } else if (r.containsKey('preco')) {
                          final v = r['preco'];
                          if (v is num) precoReais = v.toDouble();
                        }

                        final data =
                            (r['data'] ??
                                    r['data_iso'] ??
                                    r['created_at'] ??
                                    '')
                                .toString();

                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            precoReais != null
                                ? 'R\$ ${precoReais.toStringAsFixed(2)}'
                                : 'Preço não informado',
                          ),
                          subtitle: Text(
                            data.isNotEmpty ? data : 'Data não informada',
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
