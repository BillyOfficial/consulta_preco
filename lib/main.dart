import 'package:flutter/material.dart';
import 'package:consulta_preco/modelos/loja_model.dart';
import 'package:consulta_preco/servicos/local_loja_service.dart';
import 'package:consulta_preco/servicos/loja_selecionada_store.dart';
import 'package:consulta_preco/telas/pesquisar_produto_tela.dart';
import 'package:consulta_preco/widgets/selecionar_loja_sheet.dart';
import 'package:consulta_preco/telas/pesquisar_ean_tela.dart';

void main() {
  runApp(const ConsultaPrecoApp());
}

class ConsultaPrecoApp extends StatelessWidget {
  const ConsultaPrecoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Consulta de Preço',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const TelaInicial(),
    );
  }
}

class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key});

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
  final _localLojaService = LocalLojaService();
  bool _processandoLocal = false;

  Future<void> _detectarOuSelecionarLoja() async {
    setState(() => _processandoLocal = true);
    LojaModel? lojaSelecionada;
    try {
      final local = await _localLojaService.acharOuCriarLocal();
      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => SelecionarLojaSheet(
          localId: local.id!,
          onSelecionar: (loja) {
            lojaSelecionada = loja;
            LojaSelecionadaStore.instance.atualizar(loja);
          },
        ),
      );

      if (!mounted) return;
      if (lojaSelecionada != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loja selecionada: ${lojaSelecionada!.nome}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao detectar local: $e')),
      );
    } finally {
      if (mounted) setState(() => _processandoLocal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consulta de Preço')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<LojaModel?>(
                valueListenable: LojaSelecionadaStore.instance,
                builder: (context, loja, _) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.storefront),
                      title: Text(
                        loja != null ? loja.nome : 'Nenhuma loja selecionada',
                      ),
                      subtitle: Text(
                        loja != null
                            ? 'ID: ${loja.id}'
                            : 'Selecione a loja para registrar preços',
                      ),
                      trailing: _processandoLocal
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              tooltip: 'Detectar local / escolher loja',
                              icon: const Icon(Icons.place_outlined),
                              onPressed: _detectarOuSelecionarLoja,
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Pesquisar por EAN'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PesquisarEanTela(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Buscar por Produto'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PesquisarProdutoTela(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
