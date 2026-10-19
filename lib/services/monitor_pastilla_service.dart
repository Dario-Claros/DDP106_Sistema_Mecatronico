import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'notificacion_service.dart';

/// Servicio que monitorea en tiempo real el nodo `/pastillero/eventos/ultimo_evento`
/// actualizado por el ESP32 de Isel y genera tanto la notificación push local
/// como el registro en `/pastillero/eventos/historial`.
///
/// Valores enviados por el ESP32 en `tipo`:
///   - "dispensado"
///   - "retirado"
///   - "ignorado"
class MonitorPastillaService {
  // Singleton
  static final MonitorPastillaService _instance =
      MonitorPastillaService._internal();
  factory MonitorPastillaService() => _instance;
  MonitorPastillaService._internal();

  final DatabaseReference _ultimoEventoRef =
      FirebaseDatabase.instance.ref('pastillero/eventos/ultimo_evento');

  StreamSubscription<DatabaseEvent>? _subscription;

  bool _primeraLectura = true;
  String _ultimoEventoProcesado = '';

  // ---------------------------------------------------------------------------
  // Control del monitor
  // ---------------------------------------------------------------------------

  /// Inicia el monitoreo en tiempo real del último evento del ESP32.
  void iniciar() {
    _subscription?.cancel();
    _primeraLectura = true;
    _subscription = _ultimoEventoRef.onValue.listen(
      _evaluarUltimoEvento,
      onError: (e) => debugPrint('[Monitor] Error en stream de eventos: $e'),
    );
    debugPrint('[Monitor] Monitoreo de /pastillero/eventos/ultimo_evento iniciado.');
  }

  /// Detiene el monitoreo.
  void detener() {
    _subscription?.cancel();
    _subscription = null;
    debugPrint('[Monitor] Monitoreo detenido.');
  }

  /// Limpia el estado del último evento procesado.
  void limpiarAlertas() {
    _ultimoEventoProcesado = '';
  }

  // ---------------------------------------------------------------------------
  // Lógica de evaluación del Bus de Eventos (ESP32 -> App -> Historial)
  // ---------------------------------------------------------------------------

  Future<void> _evaluarUltimoEvento(DatabaseEvent event) async {
    final data = event.snapshot.value;
    if (data == null || data is! Map) {
      _primeraLectura = false;
      return;
    }

    final ultimoEvento = Map<dynamic, dynamic>.from(data);

    final tipo = (ultimoEvento['tipo'] as String?)?.trim() ?? '';
    final compartimentoId =
        (ultimoEvento['compartimiento'] as num?)?.toInt() ??
        (ultimoEvento['compartimento'] as num?)?.toInt() ??
        0;
    final medicamentoRaw = (ultimoEvento['medicamento'] as String?)?.trim() ?? '';
    final medicamento =
        medicamentoRaw.isEmpty ? 'Compartimento $compartimentoId' : medicamentoRaw;

    if (tipo.isEmpty) {
      _primeraLectura = false;
      return;
    }

    final firmaActual = '${compartimentoId}_${medicamento}_$tipo';

    // Ignorar el valor que ya estaba guardado en Firebase al abrir la app
    // para no disparar una notificación vieja al iniciar.
    if (_primeraLectura) {
      _primeraLectura = false;
      _ultimoEventoProcesado = firmaActual;
      debugPrint('[Monitor] Evento inicial en Firebase ignorado: $firmaActual');
      return;
    }

    // Disparamos la notificación y guardamos en el historial
    _ultimoEventoProcesado = firmaActual;
    await _procesarNuevoEvento(
      compartimentoId: compartimentoId,
      medicamento: medicamento,
      tipo: tipo,
    );
  }

  Future<void> _procesarNuevoEvento({
    required int compartimentoId,
    required String medicamento,
    required String tipo,
  }) async {
    debugPrint(
        '[Monitor] 🔔 Nuevo evento del ESP32: tipo="$tipo", med="$medicamento", comp=$compartimentoId');

    final tipoLower = tipo.toLowerCase();
    String titulo = 'Pastillero DDP106';
    String cuerpo =
        'La pastilla $medicamento (Comp. $compartimentoId) registró el evento: $tipo.';

    if (tipoLower.startsWith('dispensad')) {
      titulo = '💊 Pastilla dispensada';
      cuerpo =
          'La pastilla $medicamento (Compartimento $compartimentoId) fue dispensada.';
    } else if (tipoLower.startsWith('retirad')) {
      titulo = '✅ Pastilla retirada';
      cuerpo =
          'La pastilla $medicamento (Compartimento $compartimentoId) fue retirada por el paciente.';
    } else if (tipoLower.startsWith('ignorad')) {
      titulo = '🚨 Pastilla ignorada';
      cuerpo =
          'La pastilla $medicamento (Compartimento $compartimentoId) fue ignorada. Requiere atención.';
    }

    await NotificacionService.mostrarNotificacionLocal(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      titulo: titulo,
      cuerpo: cuerpo,
      payload: 'comp_$compartimentoId',
    );

    await _guardarEnHistorialFirebase(
      compartimentoId: compartimentoId,
      medicamento: medicamento,
      tipo: tipoLower,
    );
  }

  Future<void> _guardarEnHistorialFirebase({
    required int compartimentoId,
    required String medicamento,
    required String tipo,
  }) async {
    try {
      final ahora = DateTime.now();
      final fecha =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}';
      final hora =
          '${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}';
      final timestamp = '${fecha}T$hora';

      // Guardamos en /pastillero/eventos/historial como pidió Isel
      await FirebaseDatabase.instance
          .ref('pastillero/eventos/historial')
          .push()
          .set({
        'compartimiento': compartimentoId,
        'medicamento': medicamento,
        'tipo': tipo,
        'fecha': fecha,
        'hora': hora,
        'timestamp': timestamp,
      });

      debugPrint('[Monitor] Evento guardado en /pastillero/eventos/historial');
    } catch (e) {
      debugPrint('[Monitor] Error guardando en historial: $e');
    }
  }
}
