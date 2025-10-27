import 'package:flutter/material.dart';
import '../dados/produtos_dao.dart';
import '../dados/registros_dao.dart';
import '../dominio/status_preco.dart';

class ProdutoDetalheTela extends StatefulWidget {
  final int produtoId;
  const ProdutoDetalheTela({super.key, required this.produtoId});

  @override
  State<ProdutoDetalheTela> createState() => _ProdutoDetalheTelaState();
}

class _ProdutoDetalheTelaState extends State<ProdutoDetalheTela> {
  final daoProdutos = ProdutosDAO();
  final daoRegistros = RegistrosDAO();

  final precoCtrl = TextEditingController();
  final lojaCtrl = TextEditingController();
  final cidadeCtrl = TextEditingController();

  Map<String, dynamic>? produto;
  List<Map<String, dynamic>> historico = [];
  String etiqueta = 'Sem base';
  Color corEtiqueta = Colors.grey;

  Future<void> _carregar() async {
    final p = await daoProdutos.buscarPorId(widget.produtoId);
    final h = await daoRegistros.historicoRecentes(widget.produtoId, limite: 10);

    setState(() {
      produto = p;
      historico = h;
    });
    _recalcularEtiqueta();
  }

  void _recalcularEtiqueta() {
    final ultimos = historico.map((e) => e['preco_centavos'] as int).toList();
    if (ultimos.isEmpty || precoCtrl.text.trim().isEmpty) {
      setState(() { etiqueta = 'Sem base'; corEtiqueta = Colors.grey; });
      return;
    }
    final atual = parseReaisParaCentavos(precoCtrl.text);
    final s = statusPreco(atual, ultimos);
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
    final cent = parseReaisParaCentavos(precoCtrl.text);
    await daoRegistros.salvarPreco(
      produtoId: widget.produtoId,
      precoCentavos: cent,
      loja: lojaCtrl.text.trim().isEmpty ? null : lojaCtrl.text.trim(),
      cidade: cidadeCtrl.text.trim().isEmpty ? null : cidadeCtrl.text.trim(),
    );
    precoCtrl.clear();
    await _carregar();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preço salvo!')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _carregar();
    precoCtrl.addListener(_recalcularEtiqueta);
  }

  @override
  void dispose() {
    precoCtrl.removeListener(_recalcularEtiqueta);
    precoCtrl.dispose();
    lojaCtrl.dispose();
    cidadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nome = produto?['nome'] ?? '...';
    final ean = produto?['ean'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(nome)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (ean != null)
              Align(alignment: Alignment.centerLeft, child: Text('EAN: $ean')),
            const SizedBox(height: 12),

            // Preço + campos opcionais
            TextField(
              controller: precoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Preço (ex.: 12,34)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: lojaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Loja (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: cidadeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cidade (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Etiqueta de status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: corEtiqueta.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: corEtiqueta),
              ),
              child: Text(
                'Status: $etiqueta',
                style: TextStyle(color: corEtiqueta, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.save),
              label: const Text('Salvar preço'),
            ),
            const SizedBox(height: 12),

            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Histórico recente', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),

            Expanded(
              child: ListView.builder(
                itemCount: historico.length,
                itemBuilder: (_, i) {
                  final r = historico[i];
                  final data = DateTime.fromMillisecondsSinceEpoch(r['criado_em'] as int);
                  final preco = centavosParaReais(r['preco_centavos'] as int);
                  final dd = '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
                  return ListTile(
                    leading: const Icon(Icons.price_check),
                    title: Text(preco),
                    subtitle: Text(dd),
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
