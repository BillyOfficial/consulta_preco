import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:consulta_preco/dados/produtos_dao.dart';
import 'package:consulta_preco/telas/produto_detalhe_tela.dart';

class PesquisarEanTela extends StatefulWidget {
  const PesquisarEanTela({super.key});

  @override
  State<PesquisarEanTela> createState() => _PesquisarEanTelaState();
}

class _PesquisarEanTelaState extends State<PesquisarEanTela> {
  final _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    autoStart: true,
  );
  final _dao = ProdutosDAO();

  bool _processando = false;
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _processarCodigo(String codigo) async {
    if (_processando) return;
    setState(() {
      _processando = true;
      _erro = null;
    });

    final ean = codigo.trim();
    if (ean.isEmpty) {
      if (mounted) {
        setState(() {
          _processando = false;
          _erro = 'Código inválido';
        });
      }
      return;
    }

    try {
      int produtoId;
      final existente = await _dao.buscarPorEan(ean);
      if (existente != null) {
        produtoId = existente['id'] as int;
        if (mounted) {
          final nome = (existente['nome'] ?? ean).toString();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Produto encontrado: $nome')),
          );
        }
      } else {
        final nome = await _solicitarNome(ean);
        if (!mounted) return;
        if (nome == null) {
          setState(() => _processando = false);
          return;
        }
        produtoId = await _dao.inserir(ean: ean, nome: nome.isEmpty ? ean : nome);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Produto criado com EAN $ean')),
        );
      }

      await _controller.stop();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProdutoDetalheTela(produtoId: produtoId),
        ),
      );
      if (!mounted) return;
      await _controller.start();
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = 'Erro ao processar código: $e');
    } finally {
      if (mounted) {
        setState(() => _processando = false);
      }
    }
  }

  Future<String?> _solicitarNome(String ean) async {
    final ctrl = TextEditingController(text: ean);
    try {
      return await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Novo produto'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome do produto',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesquisar por EAN'),
        actions: [
          ValueListenableBuilder<TorchState>(
            valueListenable: _controller.torchState,
            builder: (context, state, _) {
              final ligado = state == TorchState.on;
              return IconButton(
                tooltip: ligado ? 'Desligar flash' : 'Ligar flash',
                icon: Icon(ligado ? Icons.flash_on : Icons.flash_off),
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: (capture) {
              if (_processando) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _processarCodigo(raw);
                  break;
                }
              }
            },
          ),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _processando
                        ? 'Processando código...'
                        : 'Aponte a câmera para o código de barras',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _erro!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
