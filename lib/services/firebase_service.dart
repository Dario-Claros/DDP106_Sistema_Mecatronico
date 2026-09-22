import 'package:firebase_database/firebase_database.dart';
import '../models/compartimento_model.dart';

/// Servicio que encapsula toda la comunicación con Firebase Realtime Database.
///
/// Arquitectura de datos:
///   Firebase (intermediario)
///       ↑ escribe              ↓ lee
///   App Android           ESP32/Arduino
///
/// Nodo raíz en Firebase: `/pastillero`
/// Nodo de alertas:       `/alertas`
/// Nodo de configuración: `/config`
class FirebaseService {
  // Singleton
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final DatabaseReference _dbRef =
      FirebaseDatabase.instance.ref('pastillero');

  // ---------------------------------------------------------------------------
  // Lectura en tiempo real (Stream)
  // ---------------------------------------------------------------------------

  /// Retorna un [Stream] que emite la lista de los 7 compartimentos
  /// cada vez que Firebase detecta un cambio.
  Stream<List<CompartimentoModel>> watchCompartimentos() {
    return _dbRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return _compartimentosVacios();

      final map = Map<dynamic, dynamic>.from(data as Map);
      final List<CompartimentoModel> lista = [];

      for (int i = 1; i <= 7; i++) {
        final key = 'compartimento_$i';
        if (map.containsKey(key)) {
          final compMap = Map<dynamic, dynamic>.from(map[key] as Map);
          lista.add(CompartimentoModel.fromMap(compMap));
        } else {
          lista.add(_compartimentoVacio(i));
        }
      }

      return lista;
    });
  }

  // ---------------------------------------------------------------------------
  // Escritura — la App Android escribe; el ESP32 lee
  // ---------------------------------------------------------------------------

  /// Actualiza todos los campos de un [CompartimentoModel] en Firebase.
  Future<void> updateCompartimento(CompartimentoModel compartimento) async {
    await _dbRef
        .child(compartimento.firebaseKey)
        .set(compartimento.toMap());
  }

  /// Actualiza únicamente el campo [sensorIrActivo].
  Future<void> actualizarSensorIR(int compartimentoId, bool estado) async {
    await _dbRef
        .child('compartimento_$compartimentoId')
        .update({'sensor_ir_activo': estado});
  }

  /// Actualiza únicamente el campo [pastillaLiberada].
  Future<void> actualizarLiberacion(int compartimentoId, bool liberada) async {
    await _dbRef
        .child('compartimento_$compartimentoId')
        .update({'pastilla_liberada': liberada});
  }

  /// Reinicia los estados diarios de todos los compartimentos.
  Future<void> reiniciarEstadosDiarios() async {
    final hoy = _fechaHoy();
    final Map<String, dynamic> updates = {};

    for (int i = 1; i <= 7; i++) {
      updates['compartimento_$i/sensor_ir_activo'] = false;
      updates['compartimento_$i/pastilla_liberada'] = false;
      updates['compartimento_$i/fecha_registro'] = hoy;
    }

    await _dbRef.update(updates);
  }

  /// Inicializa los 7 compartimentos en Firebase con valores por defecto
  /// si aún no existen en la base de datos.
  Future<void> inicializarCompartimentos() async {
    final snapshot = await _dbRef.get();
    if (snapshot.exists) return;

    final hoy = _fechaHoy();
    final Map<String, dynamic> datos = {};

    for (int i = 1; i <= 7; i++) {
      datos['compartimento_$i'] = {
        'compartimento_id': i,
        'medicamento': '',
        'hora': 8,
        'minutos': 0,
        'sensor_ir_activo': false,
        'pastilla_liberada': false,
        'fecha_registro': hoy,
        'condiciones': [],
        'tiempo_espera_minutos': 15,
        'accion_por_defecto': 'dispensarPorImportancia',
      };
    }

    await _dbRef.set(datos);
  }

  // ---------------------------------------------------------------------------
  // Gestión del token FCM del cuidador
  // ---------------------------------------------------------------------------

  /// Guarda el token FCM del dispositivo del cuidador en Firebase.
  /// La Cloud Function lo leerá para enviar la notificación push cuando
  /// el ESP32 detecte una pastilla ignorada.
  Future<void> guardarTokenCuidador(String token) async {
    await FirebaseDatabase.instance.ref('config/fcm_token_cuidador').set({
      'token': token,
      'actualizado': _fechaHoy(),
    });
    // ignore: avoid_print
    print('[Firebase] Token FCM del cuidador guardado.');
  }

  /// Lee el token FCM actual del cuidador (para debugging).
  Future<String?> leerTokenCuidador() async {
    final snapshot =
        await FirebaseDatabase.instance.ref('config/fcm_token_cuidador/token').get();
    return snapshot.value as String?;
  }

  // ---------------------------------------------------------------------------
  // Helpers privados
  // ---------------------------------------------------------------------------

  String _fechaHoy() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  CompartimentoModel _compartimentoVacio(int id) {
    return CompartimentoModel(
      compartimentoId: id,
      medicamento: '',
      hora: 8,
      minutos: 0,
      sensorIrActivo: false,
      pastillaLiberada: false,
      fechaRegistro: _fechaHoy(),
    );
  }

  List<CompartimentoModel> _compartimentosVacios() {
    return List.generate(7, (i) => _compartimentoVacio(i + 1));
  }
}
