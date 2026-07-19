import 'dart:math';

import 'package:flutter/material.dart';
import '../dados/locais_dao.dart';
import '../dados/lojas_dao.dart';
import '../modelos/local_model.dart';
import '../modelos/loja_model.dart';

class SelecionarLojaSheet extends StatefulWidget {
  final LocalModel local;
  final void Function(LojaModel loja) onSelecionar;

  const SelecionarLojaSheet({
    super.key,
    required this.local,
    required this.onSelecionar,
  });

  @override
  State<SelecionarLojaSheet> createState() => _SelecionarLojaSheetState();
}

class _SelecionarLojaSheetState extends State<SelecionarLojaSheet> {
  final _lojasDao = LojasDAO();
  final _locaisDao = LocaisDAO();
  final _ctrlNome = TextEditingController();
  late LocalModel _localAtual;
  List<_LojaListItem> _lojas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _localAtual = widget.local;
    _carregar();
  }

  @override
  void dispose() {
    _ctrlNome.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    if (mounted) {
      setState(() => _carregando = true);
    }
    final locais = await _locaisDao.listarTodos();
    final itens = <_LojaListItem>[];
    for (final local in locais) {
      if (local.id == null) continue;
      final lojas = await _lojasDao.listarPorLocal(local.id!);
      final distancia = _distanciaMetros(
        _localAtual.latitude,
        _localAtual.longitude,
        local.latitude,
        local.longitude,
      );
      for (final loja in lojas) {
        itens.add(
          _LojaListItem(
            loja: loja,
            local: local,
            distanciaMetros: distancia,
          ),
        );
      }
    }
    itens.sort((a, b) => a.distanciaMetros.compareTo(b.distanciaMetros));
    if (!mounted) return;
    setState(() {
      _lojas = itens;
      _carregando = false;
    });
  }

  Future<void> _adicionar() async {
    final nome = _ctrlNome.text.trim();
    if (nome.isEmpty) return;
    final localId = _localAtual.id;
    if (localId == null) return;
    final id = await _lojasDao.inserir(LojaModel(localId: localId, nome: nome));
    _ctrlNome.clear();
    // Seleciona a loja recém-criada diretamente (sem depender de recarregar a lista).
    widget.onSelecionar(LojaModel(id: id, localId: localId, nome: nome));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _editarNomeLocal() async {
    final ctrl = TextEditingController(text: _localAtual.nome);
    final novoNome = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar nome do local'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome do local',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
    if (novoNome == null) return;
    final texto = novoNome.trim();
    if (texto.isEmpty || texto == _localAtual.nome) return;
    await _locaisDao.atualizarNome(_localAtual.id!, texto);
    if (!mounted) return;
    setState(() => _localAtual = _localAtual.copyWith(nome: texto));
  }

  String _formatarDistancia(double metros) {
    if (metros >= 1000) {
      return '${(metros / 1000).toStringAsFixed(1)} km';
    }
    return '${metros.toStringAsFixed(0)} m';
  }

  double _distanciaMetros(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
            cos(_deg2rad(lat1)) *
                cos(_deg2rad(lat2)) *
                sin(dLon / 2) *
                sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180.0);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Selecionar Loja', style: tema.textTheme.titleLarge),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local detectado',
                          style: tema.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _localAtual.nome,
                          style: tema.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _editarNomeLocal,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_carregando)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_lojas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Nenhuma loja cadastrada ainda.'),
                )
              else ...[
                Text(
                  'Lojas ordenadas por proximidade',
                  style: tema.textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _lojas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = _lojas[i];
                      final isLocalAtual = item.local.id == _localAtual.id;
                      final destaque =
                          isLocalAtual ? tema.colorScheme.primary : null;
                      return ListTile(
                        leading: Icon(Icons.storefront, color: destaque),
                        title: Text(item.loja.nome),
                        subtitle: Text(
                          '${item.local.nome} • ${_formatarDistancia(item.distanciaMetros)}',
                        ),
                        onTap: () {
                          widget.onSelecionar(item.loja);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrlNome,
                      decoration: const InputDecoration(
                        labelText: 'Adicionar nova loja',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _adicionar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _adicionar,
                    child: const Text('Adicionar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LojaListItem {
  final LojaModel loja;
  final LocalModel local;
  final double distanciaMetros;

  _LojaListItem({
    required this.loja,
    required this.local,
    required this.distanciaMetros,
  });
}
