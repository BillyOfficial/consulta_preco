import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:consulta_preco/modelos/nota_fiscal_model.dart';
import 'package:consulta_preco/servicos/loja_selecionada_store.dart';
import 'package:consulta_preco/servicos/nfce_service.dart';
import 'package:consulta_preco/servicos/importar_nota_service.dart';
import 'package:consulta_preco/telas/historico_notas_tela.dart';

enum _Fase { escaneando, web, salvando, erro }

class EscanearNotaTela extends StatefulWidget {
  const EscanearNotaTela({super.key});

  @override
  State<EscanearNotaTela> createState() => _EscanearNotaTelaState();
}

class _EscanearNotaTelaState extends State<EscanearNotaTela> {
  final _scanner = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: true,
    formats: const [BarcodeFormat.qrCode],
  );
  final _nfceService = NfceService();
  final _importador = ImportarNotaService();

  _Fase _fase = _Fase.escaneando;
  String _mensagemErro = '';
  String _urlAtual = '';
  WebViewController? _web;
  Timer? _poll;
  bool _extraindo = false;
  bool _precisaInteracao = false; // mostra o WebView se a SEFAZ pedir verificação
  int _tentativas = 0;

  @override
  void dispose() {
    _poll?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  // ---- Etapa 1: escanear QR ----

  void _onDetect(BarcodeCapture capture) {
    if (_fase != _Fase.escaneando) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      if (NfceService.pareceNfce(raw)) {
        _abrirNota(raw);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR Code não é de uma nota fiscal (NFC-e).')),
        );
      }
      break;
    }
  }

  // ---- Etapa 2: carregar a página no WebView ----

  Future<void> _abrirNota(String url) async {
    await _scanner.stop();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _iniciarPolling()),
      )
      ..loadRequest(Uri.parse(url));

    setState(() {
      _urlAtual = url;
      _web = controller;
      _fase = _Fase.web;
      _precisaInteracao = false;
    });
  }

  void _iniciarPolling() {
    _poll?.cancel();
    _tentativas = 0;
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _tentativas++;
      // Após ~20s sem itens, provavelmente há uma verificação a concluir.
      if (_tentativas >= 13 && !_precisaInteracao && mounted) {
        setState(() => _precisaInteracao = true);
      }
      _tentarExtrair(automatico: true);
    });
  }

  Future<String?> _htmlAtual() async {
    final web = _web;
    if (web == null) return null;
    final res = await web.runJavaScriptReturningResult(
      'document.documentElement.outerHTML',
    );
    var html = res.toString();
    // O Android costuma devolver a string em formato JSON (com aspas/escapes).
    if (html.startsWith('"') && html.endsWith('"')) {
      try {
        html = jsonDecode(html) as String;
      } catch (_) {/* mantém como está */}
    }
    return html;
  }

  Future<void> _tentarExtrair({required bool automatico}) async {
    if (_extraindo || _fase != _Fase.web) return;
    _extraindo = true;
    try {
      final html = await _htmlAtual();
      if (html == null) return;
      if (automatico && !NfceService.temItens(html)) return;

      final nota = _nfceService.notaDeHtml(html, _urlAtual);
      _poll?.cancel();
      if (!mounted) return;
      await _importarEAbrirRevisao(nota);
    } on NfceException catch (e) {
      if (automatico) return; // segue tentando no automático
      _poll?.cancel();
      if (!mounted) return;
      setState(() {
        _mensagemErro = e.mensagem;
        _fase = _Fase.erro;
      });
    } catch (_) {
      if (!automatico) {
        _poll?.cancel();
        if (!mounted) return;
        setState(() {
          _mensagemErro = 'Não foi possível ler os itens desta página.';
          _fase = _Fase.erro;
        });
      }
    } finally {
      _extraindo = false;
    }
  }

  // ---- Etapa 3: salvar e abrir a revisão ----

  Future<void> _importarEAbrirRevisao(NotaFiscal nota) async {
    setState(() => _fase = _Fase.salvando);
    final loja = LojaSelecionadaStore.instance.value;
    try {
      await _importador.importar(nota, loja: loja);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mensagemErro = 'Erro ao salvar os itens: $e';
        _fase = _Fase.erro;
      });
      return;
    }
    if (!mounted) return;

    final notaMap = <String, dynamic>{
      'chave': nota.chaveAcesso,
      'emitente': nota.emitente,
      'importada_em': DateTime.now().toIso8601String(),
      'total': nota.total,
      'qtd_itens': nota.itens.length,
    };
    // Substitui esta tela (câmera/WebView) pela revisão — assim a câmera é
    // liberada antes de o assistente guiado abrir a sua.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => NotaDetalheTela(nota: notaMap)),
    );
  }

  Future<void> _abrirNoNavegador() async {
    final uri = Uri.tryParse(_urlAtual);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _reiniciarScanner() {
    _poll?.cancel();
    setState(() {
      _fase = _Fase.escaneando;
      _web = null;
      _mensagemErro = '';
      _precisaInteracao = false;
    });
    _scanner.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler Nota Fiscal')),
      body: switch (_fase) {
        _Fase.escaneando => _buildScanner(),
        _Fase.web => _buildWeb(),
        _Fase.salvando => _buildLoading('Salvando os itens...'),
        _Fase.erro => _buildErro(),
      },
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(controller: _scanner, fit: BoxFit.cover, onDetect: _onDetect),
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
              'Aponte para o QR Code da nota fiscal (NFC-e)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading(String texto) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(texto, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildWeb() {
    return Stack(
      children: [
        if (_web != null) Positioned.fill(child: WebViewWidget(controller: _web!)),

        // Enquanto lê automaticamente, cobre tudo com um loading amigável.
        if (!_precisaInteracao)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 24),
                  Text('Lendo a sua nota...',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Buscando os produtos na SEFAZ. Leva alguns segundos.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (_precisaInteracao) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.amber.shade100,
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(Icons.touch_app, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Conclua a verificação na tela. Os itens aparecem sozinhos.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reiniciarScanner,
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _tentarExtrair(automatico: false),
                      child: const Text('Tentar de novo'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErro() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_mensagemErro, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_urlAtual.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _abrirNoNavegador,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir nota no navegador'),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _reiniciarScanner,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
