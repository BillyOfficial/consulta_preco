import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:consulta_preco/dados/notas_dao.dart';
import 'package:consulta_preco/dados/produtos_dao.dart';
import 'package:consulta_preco/dominio/ean.dart';

/// Assistente guiado de escaneamento: percorre os itens PENDENTES de uma nota
/// (um por vez), pedindo para escanear o código de barras de cada produto da
/// bolsa — ou marcá-lo como granel. O progresso é salvo a cada passo.
class EscanearBolsaTela extends StatefulWidget {
  final String chave;
  final String titulo;
  const EscanearBolsaTela({super.key, required this.chave, required this.titulo});

  @override
  State<EscanearBolsaTela> createState() => _EscanearBolsaTelaState();
}

class _EscanearBolsaTelaState extends State<EscanearBolsaTela> {
  final _notasDao = NotasDAO();
  final _produtosDao = ProdutosDAO();
  final _scanner = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: true,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );

  List<Map<String, dynamic>> _pendentes = [];
  int _idx = 0;
  bool _carregando = true;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final itens = await _notasDao.itensDaNota(widget.chave);
    final pend = itens.where((it) {
      final ean = (it['ean'] ?? '').toString();
      final granel = (it['sem_codigo'] as int? ?? 0) == 1;
      return ean.isEmpty && !granel;
    }).toList();
    if (!mounted) return;
    setState(() {
      _pendentes = pend;
      _carregando = false;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processando || _idx >= _pendentes.length) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && eanValido(raw)) {
        _processarLeitura(raw);
        return;
      }
    }
  }

  Future<void> _processarLeitura(String ean) async {
    if (_processando || _idx >= _pendentes.length) return;
    _processando = true;
    final pid = _pendentes[_idx]['produto_id'] as int;
    final ok = await _produtosDao.atualizarEan(id: pid, ean: ean);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esse EAN já está em outro produto.')),
      );
      _processando = false;
      return;
    }
    HapticFeedback.mediumImpact();
    _avancar();
    _processando = false;
  }

  void _avancar() => setState(() => _idx++);

  Future<void> _marcarGranel() async {
    if (_idx >= _pendentes.length) return;
    final pid = _pendentes[_idx]['produto_id'] as int;
    await _produtosDao.marcarSemCodigo(id: pid, valor: true);
    _avancar();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_idx >= _pendentes.length) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.titulo)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                _pendentes.isEmpty
                    ? 'Não havia itens pendentes.'
                    : 'Tudo escaneado!',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Concluir'),
              ),
            ],
          ),
        ),
      );
    }

    final atual = _pendentes[_idx];
    final qtd = (atual['qtd_na_nota'] as int? ?? 1);
    final nome =
        '${(atual['nome'] ?? '').toString()}${qtd > 1 ? ' (${qtd}x)' : ''}';
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Item ${_idx + 1} de ${_pendentes.length}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                const Text('Escaneie este produto:',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  nome,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: MobileScanner(
              controller: _scanner,
              fit: BoxFit.cover,
              onDetect: _onDetect,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _avancar,
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Pular'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _marcarGranel,
                      icon: const Icon(Icons.eco),
                      label: const Text('É granel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
