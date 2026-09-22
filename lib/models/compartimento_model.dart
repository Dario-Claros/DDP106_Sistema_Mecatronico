// =============================================================================
// Modelo: Condición previa de toma (respuesta Sí/No)
// =============================================================================

/// Representa una condición previa que el paciente debe cumplir antes de
/// tomar su medicamento. Sólo acepta respuestas cerradas (Sí / No) para
/// mantener compatibilidad con la interfaz física del pastillero (2 botones).
///
/// Ejemplo Firebase:
/// {
///   "pregunta": "¿Ya desayunaste?",
///   "respuesta_requerida": true
/// }
class CondicionModel {
  /// Pregunta que se mostrará al paciente en la pantalla del pastillero físico.
  /// Debe ser breve y formularse para respuesta Sí/No.
  final String pregunta;

  /// Respuesta necesaria para permitir la toma.
  /// - `true`  → el paciente debe responder **Sí** para habilitar la dispensación.
  /// - `false` → el paciente debe responder **No** para habilitar la dispensación.
  final bool respuestaRequerida;

  const CondicionModel({
    required this.pregunta,
    required this.respuestaRequerida,
  });

  factory CondicionModel.fromMap(Map<dynamic, dynamic> map) {
    return CondicionModel(
      pregunta: (map['pregunta'] as String?) ?? '',
      respuestaRequerida: (map['respuesta_requerida'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'pregunta': pregunta,
        'respuesta_requerida': respuestaRequerida,
      };

  CondicionModel copyWith({String? pregunta, bool? respuestaRequerida}) =>
      CondicionModel(
        pregunta: pregunta ?? this.pregunta,
        respuestaRequerida: respuestaRequerida ?? this.respuestaRequerida,
      );
}

// =============================================================================
// Enum: Acción por defecto si no se cumplen las condiciones
// =============================================================================

/// Define qué debe hacer el pastillero si el paciente no responde a las
/// condiciones previas dentro del tiempo de espera configurado.
enum AccionPorDefecto {
  /// El dispensador libera la pastilla de todas formas por su importancia médica.
  dispensarPorImportancia,

  /// Se cancela la dosis del día para ese compartimento.
  cancelarDosis,
}

/// Extensión para serializar/deserializar el enum hacia Firebase como String.
extension AccionPorDefectoX on AccionPorDefecto {
  String get firebaseValue => name; // 'dispensarPorImportancia' | 'cancelarDosis'

  static AccionPorDefecto fromString(String? value) {
    switch (value) {
      case 'dispensarPorImportancia':
        return AccionPorDefecto.dispensarPorImportancia;
      case 'cancelarDosis':
        return AccionPorDefecto.cancelarDosis;
      default:
        return AccionPorDefecto.dispensarPorImportancia;
    }
  }

  String get etiqueta {
    switch (this) {
      case AccionPorDefecto.dispensarPorImportancia:
        return 'Dispensar por importancia';
      case AccionPorDefecto.cancelarDosis:
        return 'Cancelar dosis';
    }
  }

  String get descripcion {
    switch (this) {
      case AccionPorDefecto.dispensarPorImportancia:
        return 'El pastillero dispensará aunque no se hayan cumplido las condiciones.';
      case AccionPorDefecto.cancelarDosis:
        return 'La dosis se omitirá y se registrará como no tomada.';
    }
  }
}

// =============================================================================
// Modelo principal actualizado
// =============================================================================

/// Modelo de datos para un compartimento del pastillero inteligente.
///
/// Estructura que se sincroniza con Firebase Realtime Database en el nodo:
///   /pastillero/compartimento_N
///
/// La app Android escribe en Firebase; el ESP32 lee desde Firebase.
class CompartimentoModel {
  /// Número identificador del compartimento (1 al 7).
  final int compartimentoId;

  /// Nombre del medicamento asignado a este compartimento.
  final String medicamento;

  /// Hora programada para liberar la pastilla (formato 24h, 0–23).
  final int hora;

  /// Minutos de la hora programada (0–59).
  final int minutos;

  /// Estado del sensor infrarrojo del compartimento.
  final bool sensorIrActivo;

  /// Indica si el mecanismo físico liberó la pastilla en el día actual.
  final bool pastillaLiberada;

  /// Fecha del último registro en formato `yyyy-MM-dd`.
  final String fechaRegistro;

  // ── Nuevos campos de configuración avanzada ──────────────────────────────

  /// Lista de condiciones previas que el paciente debe confirmar (Sí/No)
  /// antes de recibir la pastilla. Máximo recomendado: 3 condiciones.
  final List<CondicionModel> condiciones;

  /// Tiempo de espera en minutos (15–30) antes de ejecutar [accionPorDefecto]
  /// si el paciente no responde a las condiciones.
  final int tiempoEsperaMinutos;

  /// Acción que tomará el pastillero si el paciente no responde dentro de
  /// [tiempoEsperaMinutos] tras la hora programada.
  final AccionPorDefecto accionPorDefecto;

  const CompartimentoModel({
    required this.compartimentoId,
    required this.medicamento,
    required this.hora,
    required this.minutos,
    required this.sensorIrActivo,
    required this.pastillaLiberada,
    required this.fechaRegistro,
    this.condiciones = const [],
    this.tiempoEsperaMinutos = 15,
    this.accionPorDefecto = AccionPorDefecto.dispensarPorImportancia,
  });

  // ---------------------------------------------------------------------------
  // Serialización / Deserialización
  // ---------------------------------------------------------------------------

  factory CompartimentoModel.fromMap(Map<dynamic, dynamic> map) {
    // Parsear lista de condiciones desde Firebase
    List<CondicionModel> condiciones = [];
    if (map['condiciones'] != null) {
      final condMap = map['condiciones'];
      if (condMap is List) {
        condiciones = condMap
            .whereType<Map>()
            .map((c) => CondicionModel.fromMap(c))
            .toList();
      } else if (condMap is Map) {
        // Firebase puede guardar listas como mapas con índices numéricos
        condiciones = condMap.values
            .whereType<Map>()
            .map((c) => CondicionModel.fromMap(c))
            .toList();
      }
    }

    return CompartimentoModel(
      compartimentoId: (map['compartimento_id'] as num?)?.toInt() ?? 0,
      medicamento: (map['medicamento'] as String?) ?? '',
      hora: (map['hora'] as num?)?.toInt() ?? 0,
      minutos: (map['minutos'] as num?)?.toInt() ?? 0,
      sensorIrActivo: (map['sensor_ir_activo'] as bool?) ?? false,
      pastillaLiberada: (map['pastilla_liberada'] as bool?) ?? false,
      fechaRegistro: (map['fecha_registro'] as String?) ?? '',
      condiciones: condiciones,
      tiempoEsperaMinutos:
          (map['tiempo_espera_minutos'] as num?)?.toInt() ?? 15,
      accionPorDefecto: AccionPorDefectoX.fromString(
          map['accion_por_defecto'] as String?),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'compartimento_id': compartimentoId,
      'medicamento': medicamento,
      'hora': hora,
      'minutos': minutos,
      'sensor_ir_activo': sensorIrActivo,
      'pastilla_liberada': pastillaLiberada,
      'fecha_registro': fechaRegistro,
      'condiciones': condiciones.map((c) => c.toMap()).toList(),
      'tiempo_espera_minutos': tiempoEsperaMinutos,
      'accion_por_defecto': accionPorDefecto.firebaseValue,
    };
  }

  CompartimentoModel copyWith({
    int? compartimentoId,
    String? medicamento,
    int? hora,
    int? minutos,
    bool? sensorIrActivo,
    bool? pastillaLiberada,
    String? fechaRegistro,
    List<CondicionModel>? condiciones,
    int? tiempoEsperaMinutos,
    AccionPorDefecto? accionPorDefecto,
  }) {
    return CompartimentoModel(
      compartimentoId: compartimentoId ?? this.compartimentoId,
      medicamento: medicamento ?? this.medicamento,
      hora: hora ?? this.hora,
      minutos: minutos ?? this.minutos,
      sensorIrActivo: sensorIrActivo ?? this.sensorIrActivo,
      pastillaLiberada: pastillaLiberada ?? this.pastillaLiberada,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      condiciones: condiciones ?? this.condiciones,
      tiempoEsperaMinutos: tiempoEsperaMinutos ?? this.tiempoEsperaMinutos,
      accionPorDefecto: accionPorDefecto ?? this.accionPorDefecto,
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

  bool get esDeHoy {
    final hoy = DateTime.now();
    final fechaHoy =
        '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
    return fechaRegistro == fechaHoy;
  }

  String get firebaseKey => 'compartimento_$compartimentoId';

  @override
  String toString() {
    return 'CompartimentoModel(id: $compartimentoId, med: $medicamento, '
        'hora: $horaFormateada, ir: $sensorIrActivo, liberada: $pastillaLiberada, '
        'condiciones: ${condiciones.length}, accion: ${accionPorDefecto.etiqueta})';
  }
}
