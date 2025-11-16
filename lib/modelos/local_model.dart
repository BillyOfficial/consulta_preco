class LocalModel {
  final int? id;
  final String nome;
  final double latitude;
  final double longitude;
  final double raioMetros;
  final String? criadoEm;

  LocalModel({
    this.id,
    required this.nome,
    required this.latitude,
    required this.longitude,
    this.raioMetros = 150.0,
    this.criadoEm,
  });

  LocalModel copyWith({
    int? id,
    String? nome,
    double? latitude,
    double? longitude,
    double? raioMetros,
    String? criadoEm,
  }) {
    return LocalModel(
      id: id ?? this.id,
      nome: nome ?? this.nome,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      raioMetros: raioMetros ?? this.raioMetros,
      criadoEm: criadoEm ?? this.criadoEm,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'nome': nome,
        'latitude': latitude,
        'longitude': longitude,
        'raio_metros': raioMetros,
        if (criadoEm != null) 'criado_em': criadoEm,
      };

  factory LocalModel.fromMap(Map<String, dynamic> m) => LocalModel(
        id: m['id'] as int?,
        nome: m['nome'] as String,
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        raioMetros: (m['raio_metros'] as num).toDouble(),
        criadoEm: m['criado_em'] as String?,
      );
}
