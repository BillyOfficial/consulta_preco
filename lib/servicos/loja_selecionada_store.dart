import 'package:flutter/foundation.dart';

import '../modelos/loja_model.dart';

class LojaSelecionadaStore extends ValueNotifier<LojaModel?> {
  LojaSelecionadaStore._() : super(null);

  static final LojaSelecionadaStore instance = LojaSelecionadaStore._();

  LojaModel? get lojaAtual => value;

  void atualizar(LojaModel? loja) => value = loja;

  void limpar() => value = null;
}
