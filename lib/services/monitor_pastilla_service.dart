import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/compartimento_model.dart';
import 'notificacion_service.dart';

/// Servicio que monitorea en tiempo real Firebase Realtime Database
/// para detectar pastillas ignoradas y disparar notificaciones al cuidador.
///
/// Condición de "pastilla ignorada":
///   pastilla_liberada == true  (el ESP32 abrió el compartimento)
///   AND sensor_ir_activo == false  (el sensor IR NO detectó que se tomó)
///   AND han pasado >= [tiempoEsperaMinutos] desde la hora programada
///
/// Nota: El ESP32 NO regresa la pastilla automáticamente. El cuidador
/// DEBE intervenir físicamente. La notificación lo indica explícitamente.
class MonitorPastillaService {
  // Singleton
  static final MonitorPastillaService _instance =
      MonitorPastillaService._internal();
  factory MonitorPastillaService() => _instance;
  MonitorPastillaService._internal();

  final DatabaseReference _dbRef =
      FirebaseDatabase.instance.ref('pastillero');
  final NotificacionService _notifService = NotificacionService();

  StreamSubscription<DatabaseEvent>? _subscription;

  // Registro de alertas ya enviadas en el día para no duplicar notificaciones.
  // Clave: 'compartimento_N_yyyy-MM-dd'
  final Set<String> _alertasEnviadas = {};

  // ---------------------------------------------------------------------------
  // Control del monitor
  // ---------------------------------------------------------------------------

  /// Inicia el monitoreo en tiempo real.
  /// Llamar desde [main()] después de inicializar Firebase y notificaciones.
  void iniciar() {
    _subscription?.cancel();
    _subscription = _dbRef.onValue.listen(
      _evaluarEstado,
      onError: (e) => debugPrint('[Monitor] Error en stream: $e'),
    );
    debugPrint('[Monitor] Monitoreo de pastillas iniciado.');
  }

  /// Detiene el monitoreo. Llamar en dispose() si es necesario.
  void detener() {
    _subscription?.cancel();
    _subscription = null;
    debugPrint('[Monitor] Monitoreo detenido.');
  }

  /// Limpia el registro de alertas (llamar al inicio de cada nuevo día).
  void limpiarAlertas() => _alertasEnviadas.clear();

  // ---------------------------------------------------------------------------
  // Lógica de evaluación
  // ---------------------------------------------------------------------------

  Future<void> _evaluarEstado(DatabaseEvent event) async {
    final data = event.snapshot.value;
    if (data == null) return;

    final map = Map<dynamic, dynamic>.from(data as Map);
    final ahora = DateTime.now();

    for (int i = 1; i <= 7; i++) {
      final key = 'compartimento_$i';
      if (!map.containsKey(key)) continue;

      final compMap = Map<dynamic, dynamic>.from(map[key] as Map);
      final comp = CompartimentoModel.fromMap(compMap);

      _verificarIgnorada(comp, ahora);
    }
  }

  void _verificarIgnorada(CompartimentoModel comp, DateTime ahora) {
    // ── Condición 1: la pastilla fue liberada pero NO tomada ──
    if (!comp.pastillaLiberada || comp.sensorIrActivo) return;

    // ── Condición 2: el registro es de hoy ──
    if (!comp.esDeHoy) return;

    // ── Condición 3: ya pasó el tiempo de espera desde la hora programada ──
    final horaLiberacion = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      comp.hora,
      comp.minutos,
    );
    final minutosTranscurridos =
        ahora.difference(horaLiberacion).inMinutes;

    if (minutosTranscurridos < comp.tiempoEsperaMinutos) return;

    // ── Condición 4: aún no enviamos alerta para este compartimento hoy ──
    final claveAlerta =
        'comp_${comp.compartimentoId}_${comp.fechaRegistro}';
    if (_alertasEnviadas.contains(claveAlerta)) return;

    // ── ¡Disparar alerta! ──
    _alertasEnviadas.add(claveAlerta);
    _dispararAlerta(comp, minutosTranscurridos);
  }

  Future<void> _dispararAlerta(
      CompartimentoModel comp, int minutosTranscurridos) async {
    debugPrint(
        '[Monitor] ⚠️ Pastilla ignorada detectada — Compartimento ${comp.compartimentoId}');

    await _notifService.notificarPastillaIgnorada(
      compartimentoId: comp.compartimentoId,
      medicamento: comp.medicamento.isEmpty
          ? 'Medicamento ${comp.compartimentoId}'
          : comp.medicamento,
      hora: comp.horaFormateada,
    );

    // Registrar el evento en Firebase para historial / Cloud Functions
    await _registrarAlertaEnFirebase(comp, minutosTranscurridos);
  }

  Future<void> _registrarAlertaEnFirebase(
      CompartimentoModel comp, int minutosTranscurridos) async {
    try {
      final ahora = DateTime.now();
      final timestamp =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-'
          '${ahora.day.toString().padLeft(2, '0')}T'
          '${ahora.hour.toString().padLeft(2, '0')}:'
          '${ahora.minute.toString().padLeft(2, '0')}';

      // Escribe el evento en /alertas/ → la Cloud Function lo usa para
      // enviar el FCM push al token del cuidador (dispositivos en segundo plano)
      await FirebaseDatabase.instance.ref('alertas').push().set({
        'compartimento_id': comp.compartimentoId,
        'medicamento': comp.medicamento,
        'hora_programada': comp.horaFormateada,
        'minutos_transcurridos': minutosTranscurridos,
        'accion_configurada': comp.accionPorDefecto.firebaseValue,
        'timestamp': timestamp,
        'estado': 'pastilla_ignorada',
        'requiere_intervencion': true,
        'pastilla_regresa_automaticamente': false,
      });

      debugPrint('[Monitor] Alerta registrada en Firebase /alertas/');
    } catch (e) {
      debugPrint('[Monitor] Error registrando alerta: $e');
    }
  }
}
