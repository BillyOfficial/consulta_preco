import 'dart:math';
import '../modelos/local_model.dart';
import 'banco_dados.dart';

class LocaisDAO {
  Future<int> inserir(LocalModel local) async {
    final db = await BancoDados().banco;
    return db.insert('locais', local.toMap());
  }

  Future<LocalModel?> buscarPorId(int id) async {
    final db = await BancoDados().banco;
    final res = await db.query(
      'locais',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return LocalModel.fromMap(res.first);
  }

  Future<List<LocalModel>> listarTodos() async {
    final db = await BancoDados().banco;
    final res = await db.query('locais', orderBy: 'id DESC');
    return res.map((m) => LocalModel.fromMap(m)).toList();
  }

  Future<void> atualizarNome(int id, String novoNome) async {
    final db = await BancoDados().banco;
    await db.update(
      'locais',
      {'nome': novoNome},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Retorna o primeiro Local cujo centro esteja a até `raio_metros` do ponto atual.
  Future<LocalModel?> acharLocalPorGPS({
    required double latitudeAtual,
    required double longitudeAtual,
  }) async {
    final todos = await listarTodos();
    for (final loc in todos) {
      final d = _distanciaMetros(
        latitudeAtual,
        longitudeAtual,
        loc.latitude,
        loc.longitude,
      );
      if (d <= loc.raioMetros) return loc;
    }
    return null;
  }

  // Haversine aproximado em metros
  double _distanciaMetros(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // raio da Terra (m)
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
}
