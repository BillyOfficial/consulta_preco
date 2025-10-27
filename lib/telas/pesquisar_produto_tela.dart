import 'package:flutter/material.dart';
import '../dados/produtos_dao.dart';
import 'produto_detalhe_tela.dart';

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

  Future<void> buscar() async {
    final termo = campoBusca.text.trim();
    if (termo.isEmpty) {
      setState(() => resultados = []);
      return;
    }
    setState(() => carregando = true);
    resultados = await dao.buscarPorNome(termo);
    setState(() => carregando = false);
  }

  Future<void> criarProdutoRapido() async {
    final nome = campoBusca.text.trim();
    if (nome.isEmpty) return;
    final id = await dao.inserir(nome: nome);
    if (id > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto criado!')),
      );
      await buscar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Já existe produto com esse nome/EAN.')),
      );
    }
  }

  @override
  void dispose() {
    campoBusca.dispose();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Pesquisar por Produto')),
    // ✅ deixa o Scaffold ajustar a altura quando o teclado aparece
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
                    decoration: const InputDecoration(
                      labelText: 'Nome do produto',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: buscar, child: const Text('Buscar')),
              ],
            ),
            const SizedBox(height: 8),
            if (carregando) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: resultados.length,
                itemBuilder: (_, i) {
                  return null;
                 /* ...igual ao seu... */ },
              ),
            ),
          ],
        ),
      ),
    ),

    // ✅ o rodapé “sobe” junto com o teclado
    bottomNavigationBar: AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        // altura do teclado; 0 quando fechado
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        child: TextButton(
          onPressed: criarProdutoRapido,
          child: const Text('Não achei. Criar produto com esse nome'),
        ),
      ),
    ),
  );
}
}