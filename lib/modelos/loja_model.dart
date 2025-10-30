class LojaModel {
  final int? id;
  final int localId;
  final String nome;
  final String? criadoEm;

  LojaModel({
    this.id,
    required this.localId,
    required this.nome,
    this.criadoEm,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'local_id': localId,
        'nome': nome,
        if (criadoEm != null) 'criado_em': criadoEm,
      };

  factory LojaModel.fromMap(Map<String, dynamic> m) => LojaModel(
        id: m['id'] as int?,
        localId: m['local_id'] as int,
        nome: m['nome'] as String,
        criadoEm: m['criado_em'] as String?,
      );
}
