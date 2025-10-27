import 'package:flutter/material.dart';
import 'telas/pesquisar_produto_tela.dart';

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

class TelaInicial extends StatelessWidget {
  const TelaInicial({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consulta de Preço')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Pesquisar por EAN'),
                onPressed: () {
                  // Aqui vai entrar o leitor de código de barras
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Buscar por Produto'),
                onPressed: () {
                  Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PesquisarProdutoTela()),
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
