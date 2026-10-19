/// Modelo de datos para un compartimento del pastillero inteligente.
///
/// Estructura sincronizada con Firebase Realtime Database en:
///   /pastillero/compartimento_N
///
/// Campos que lee/escribe el ESP32 de Isel:
///   medicamento, hora, minutos, compartimento_id,
///   hay_condicion, msg_condicion, liberar_por_emergencia, intentos
class CompartimentoModel {
  /// Número identificador del compartimento (1 al 7).
  final int compartimentoId;

  /// Nombre del medicamento asignado a este compartimento.
  final String medicamento;

  /// Hora programada para liberar la pastilla (formato 24h, 0–23).
  final int hora;

  /// Minutos de la hora programada (0–59).
  final int minutos;

  /// Indica si este compartimento tiene una condición previa (pregunta Sí/No)
  /// que el paciente debe confirmar antes de recibir la pastilla.
  final bool hayCondicion;

  /// Texto de la condición/pregunta que se le muestra al paciente.
  /// Ejemplo: "¿Ya cenaste?"
  final String msgCondicion;

  /// Si es true, el pastillero liberará la pastilla de todas formas
  /// (por importancia médica) cuando el paciente no responda.
  final bool liberarPorEmergencia;

  /// Número de intentos que ha hecho el sistema para dispensar.
  final int intentos;

  /// Fecha del último registro en formato `yyyy-MM-dd`.
  final String fechaRegistro;

  const CompartimentoModel({
    required this.compartimentoId,
    required this.medicamento,
    required this.hora,
    required this.minutos,
    this.hayCondicion = false,
    this.msgCondicion = '',
    this.liberarPorEmergencia = false,
    this.intentos = 0,
    this.fechaRegistro = '',
  });

  // ---------------------------------------------------------------------------
  // Serialización / Deserialización
  // ---------------------------------------------------------------------------

  factory CompartimentoModel.fromMap(Map<dynamic, dynamic> map) {
    return CompartimentoModel(
      compartimentoId: (map['compartimento_id'] as num?)?.toInt() ?? 0,
      medicamento: (map['medicamento'] as String?) ?? '',
      hora: (map['hora'] as num?)?.toInt() ?? 0,
      minutos: (map['minutos'] as num?)?.toInt() ?? 0,
      hayCondicion: (map['hay_condicion'] as bool?) ?? false,
      msgCondicion: (map['msg_condicion'] as String?) ?? '',
      liberarPorEmergencia: (map['liberar_por_emergencia'] as bool?) ?? false,
      intentos: (map['intentos'] as num?)?.toInt() ?? 0,
      fechaRegistro: (map['fecha_registro'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'compartimento_id': compartimentoId,
      'medicamento': medicamento,
      'hora': hora,
      'minutos': minutos,
      'hay_condicion': hayCondicion,
      'msg_condicion': msgCondicion,
      'liberar_por_emergencia': liberarPorEmergencia,
      'intentos': intentos,
      'fecha_registro': fechaRegistro,
    };
  }

  CompartimentoModel copyWith({
    int? compartimentoId,
    String? medicamento,
    int? hora,
    int? minutos,
    bool? hayCondicion,
    String? msgCondicion,
    bool? liberarPorEmergencia,
    int? intentos,
    String? fechaRegistro,
  }) {
    return CompartimentoModel(
      compartimentoId: compartimentoId ?? this.compartimentoId,
      medicamento: medicamento ?? this.medicamento,
      hora: hora ?? this.hora,
      minutos: minutos ?? this.minutos,
      hayCondicion: hayCondicion ?? this.hayCondicion,
      msgCondicion: msgCondicion ?? this.msgCondicion,
      liberarPorEmergencia: liberarPorEmergencia ?? this.liberarPorEmergencia,
      intentos: intentos ?? this.intentos,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get horaFormateada {
    final h = hora.toString().padLeft(2, '0');
    final m = minutos.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get firebaseKey => 'compartimento_$compartimentoId';

  @override
  String toString() {
    return 'CompartimentoModel(id: $compartimentoId, med: $medicamento, '
        'hora: $horaFormateada, condicion: $hayCondicion, intentos: $intentos)';
  }
}
