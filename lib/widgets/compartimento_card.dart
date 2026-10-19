import 'package:flutter/material.dart';
import '../models/compartimento_model.dart';

/// Tarjeta que representa visualmente un compartimento del pastillero.
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
    final color = c.hayCondicion
        ? (c.liberarPorEmergencia ? Colors.green : Colors.blue)
        : Colors.grey;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Indicador numérico del compartimento
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${c.compartimentoId}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Información central (expandible)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre del medicamento
                    Text(
                      c.medicamento.isEmpty
                          ? 'Sin medicamento'
                          : c.medicamento,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: c.medicamento.isEmpty ? Colors.grey : null,
                        fontStyle: c.medicamento.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Hora
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          c.horaFormateada,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),

                    // Badges en segunda línea (solo si hay algo que mostrar)
                    if (c.hayCondicion || c.liberarPorEmergencia || c.intentos > 0) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (c.hayCondicion)
                            _badge('Condición', Colors.blue, Icons.help_outline),
                          if (c.liberarPorEmergencia)
                            _badge('Emergencia', Colors.red, Icons.warning_amber_rounded),
                          if (c.intentos > 0)
                            _badge('${c.intentos} intentos', Colors.orange, Icons.repeat),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  /// Badge compacto con ícono y texto.
  Widget _badge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
