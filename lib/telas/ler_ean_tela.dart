import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:consulta_preco/dominio/ean.dart';

/// Tela simples de leitura de código de barras de produto.
/// Ao ler um EAN/UPC válido, retorna o código via `Navigator.pop`.
class LerEanTela extends StatefulWidget {
  const LerEanTela({super.key});

  @override
  State<LerEanTela> createState() => _LerEanTelaState();
}

class _LerEanTelaState extends State<LerEanTela> {
  final _controller = MobileScannerController(
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
  bool _concluido = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_concluido) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && eanValido(raw)) {
        _concluido = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear código de barras')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, fit: BoxFit.cover, onDetect: _onDetect),
          Positioned(
            bottom: 32,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Aponte para o código de barras do produto',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
