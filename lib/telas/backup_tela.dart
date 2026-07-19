import 'package:flutter/material.dart';

import '../servicos/backup_service.dart';

/// Tela de exportação/importação do banco de dados entre celulares.
class BackupTela extends StatefulWidget {
  const BackupTela({super.key});

  @override
  State<BackupTela> createState() => _BackupTelaState();
}

class _BackupTelaState extends State<BackupTela> {
  final _service = BackupService();
  bool _ocupado = false;

  Future<void> _exportar() async {
    setState(() => _ocupado = true);
    try {
      final nome = await _service.exportar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup pronto para envio: $nome')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _importar() async {
    final arquivo = await _service.escolherArquivo();
    if (arquivo == null || !mounted) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Substituir todos os dados?'),
        content: Text(
          'Importar "${arquivo.name}" vai APAGAR os dados atuais deste '
          'celular e colocar os do backup no lugar.\n\n'
          'Use esta opção no celular que deve receber os dados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _ocupado = true);
    try {
      await _service.importar(arquivo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados importados com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao importar: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup dos Dados')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Todos os produtos, preços, lojas e notas ficam num único '
                  'arquivo neste celular.\n\n'
                  'No celular PRINCIPAL, use "Exportar" e envie o arquivo '
                  '(WhatsApp, OneDrive...). No outro celular, abra esta tela '
                  'e use "Importar" para receber tudo.',
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar (enviar meus dados)'),
              onPressed: _ocupado ? null : _exportar,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Importar (receber dados)'),
              onPressed: _ocupado ? null : _importar,
            ),
            if (_ocupado) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
