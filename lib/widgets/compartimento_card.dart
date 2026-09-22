import 'package:flutter/material.dart';
import '../models/compartimento_model.dart';

/// Tarjeta que representa visualmente un compartimento del pastillero.
///
/// Indicadores de color:
///   🟢 Verde  — pastilla tomada (sensor IR activo)
///   🔵 Azul   — pastilla liberada pero no confirmada como tomada
///   🔴 Rojo   — pastilla pendiente (ni liberada ni tomada)
class CompartimentoCard extends StatelessWidget {
  final CompartimentoModel compartimento;
  final VoidCallback onTap;

  const CompartimentoCard({
    super.key,
    required this.compartimento,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = compartimento;
    final estado = _calcularEstado(c);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // ── Indicador de compartimento ──
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: estado.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: estado.color, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${c.compartimentoId}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: estado.color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // ── Información central ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.medicamento.isEmpty
                          ? 'Sin medicamento asignado'
                          : c.medicamento,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: c.medicamento.isEmpty ? Colors.grey : null,
                        fontStyle: c.medicamento.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          c.horaFormateada,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(width: 12),
                        // Badge de estado
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: estado.color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            estado.etiqueta,
                            style: TextStyle(
                              fontSize: 11,
                              color: estado.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Iconos de estado IR / Liberación ──
              Column(
                children: [
                  _iconEstado(
                    icon: Icons.sensors,
                    activo: c.sensorIrActivo,
                    tooltip: c.sensorIrActivo ? 'IR: Tomada' : 'IR: Pendiente',
                  ),
                  const SizedBox(height: 4),
                  _iconEstado(
                    icon: Icons.lock_open,
                    activo: c.pastillaLiberada,
                    tooltip: c.pastillaLiberada
                        ? 'Liberada'
                        : 'No liberada',
                  ),
                ],
              ),

              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  _EstadoCompartimento _calcularEstado(CompartimentoModel c) {
    if (c.sensorIrActivo) {
      return _EstadoCompartimento(Colors.green, '✅ Tomada');
    } else if (c.pastillaLiberada) {
      return _EstadoCompartimento(Colors.blue, '🔵 Liberada');
    } else {
      return _EstadoCompartimento(Colors.red, '⏳ Pendiente');
    }
  }

  Widget _iconEstado({
    required IconData icon,
    required bool activo,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: 18,
        color: activo ? Colors.green : Colors.grey[400],
      ),
    );
  }
}

class _EstadoCompartimento {
  final Color color;
  final String etiqueta;
  const _EstadoCompartimento(this.color, this.etiqueta);
}
