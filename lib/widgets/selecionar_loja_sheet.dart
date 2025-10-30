import 'package:flutter/material.dart';
import '../dados/lojas_dao.dart';
import '../modelos/loja_model.dart';

class SelecionarLojaSheet extends StatefulWidget {
  final int localId;
  final void Function(LojaModel loja) onSelecionar;

  const SelecionarLojaSheet({
    super.key,
    required this.localId,
    required this.onSelecionar,
  });

  @override
  State<SelecionarLojaSheet> createState() => _SelecionarLojaSheetState();
}

class _SelecionarLojaSheetState extends State<SelecionarLojaSheet> {
  final _dao = LojasDAO();
  final _ctrlNome = TextEditingController();
  List<LojaModel> _lojas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final ls = await _dao.listarPorLocal(widget.localId);
    setState(() {
      _lojas = ls;
      _carregando = false;
    });
  }

  Future<void> _adicionar() async {
    final nome = _ctrlNome.text.trim();
    if (nome.isEmpty) return;
    setState(() => _carregando = true);
    final id = await _dao.inserir(LojaModel(localId: widget.localId, nome: nome));
    _ctrlNome.clear();
    final ls = await _dao.listarPorLocal(widget.localId);
    setState(() {
      _lojas = ls;
      _carregando = false;
    });
    final selecionada = _lojas.firstWhere((l) => l.id == id);
    widget.onSelecionar(selecionada);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Selecionar Loja', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_carregando) const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
            if (!_carregando) ...[
              if (_lojas.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Nenhuma loja cadastrada neste local.'),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _lojas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final loja = _lojas[i];
                      return ListTile(
                        title: Text(loja.nome),
                        onTap: () {
                          widget.onSelecionar(loja);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
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
          ],
        ),
      ),
    );
  }
}
