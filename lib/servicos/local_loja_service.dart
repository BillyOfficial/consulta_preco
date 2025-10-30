import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../dados/locais_dao.dart';
import '../dados/lojas_dao.dart';
import '../modelos/local_model.dart';
import '../modelos/loja_model.dart';

class LocalLojaService {
  final _locaisDAO = LocaisDAO();
  final _lojasDAO = LojasDAO();

  /// Garante permissão e retorna posição atual.
  Future<Position> _pegarPosicao() async {
    bool servicoHabilitado = await Geolocator.isLocationServiceEnabled();
    if (!servicoHabilitado) {
      throw Exception('Serviço de localização desabilitado.');
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      throw Exception('Permissão de localização negada.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('Permissão de localização negada permanentemente.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Tenta obter um nome amigável pelo geocoding (bairro/rua/cidade).
  Future<String> _nomeAmigavelPorGeocoding(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        // monta algo curto e útil
        final pedaco =
            [
                  p.subLocality, // bairro
                  p.thoroughfare, // rua
                  p.locality, // cidade
                ]
                .where((e) => e != null && e.trim().isNotEmpty)
                .map((e) => e!.trim())
                .toList();
        return pedaco.take(2).join(' - '); // ex.: "Centro - Av. Brasil"
      }
    } catch (_) {}
    return 'Local ${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
  }

  /// Se existir um Local no raio, retorna. Senão cria um.
  Future<LocalModel> acharOuCriarLocal({
    double? latitude,
    double? longitude,
    double raioPadrao = 150,
  }) async {
    final pos = (latitude != null && longitude != null)
        ? Position(
            latitude: latitude,
            longitude: longitude,
            timestamp: DateTime.now(),
            accuracy: 5,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0.0, // ✅ novo obrigatório
            headingAccuracy: 0.0, // ✅ novo obrigatório
          )
        : await _pegarPosicao();

    final existente = await _locaisDAO.acharLocalPorGPS(
      latitudeAtual: pos.latitude,
      longitudeAtual: pos.longitude,
    );
    if (existente != null) return existente;

    final nome = await _nomeAmigavelPorGeocoding(pos.latitude, pos.longitude);
    final novo = LocalModel(
      nome: nome,
      latitude: pos.latitude,
      longitude: pos.longitude,
      raioMetros: raioPadrao,
    );
    final id = await _locaisDAO.inserir(novo);
    final criado = await _locaisDAO.buscarPorId(id);
    return criado!;
  }

  /// Se marcar “Local com 1 loja?”, cria/retorna a loja padrão do Local.
  Future<LojaModel> getOuCriarLojaUnica(
    int localId, {
    String nome = 'Loja Única',
  }) async {
    return _lojasDAO.getOrCreate(localId: localId, nome: nome);
  }

  /// Lista lojas de um local.
  Future<List<LojaModel>> listarLojasDoLocal(int localId) =>
      _lojasDAO.listarPorLocal(localId);

  /// Cria loja manualmente com nome.
  Future<LojaModel> criarLoja(int localId, String nome) async {
    final id = await _lojasDAO.inserir(LojaModel(localId: localId, nome: nome));
    final lista = await _lojasDAO.listarPorLocal(localId);
    return lista.firstWhere((l) => l.id == id);
  }
}
