import 'package:flutter/material.dart';
import '../models/compartimento_model.dart';
import '../services/firebase_service.dart';
import 'configuracion_horario_screen.dart';


/// Pantalla de detalle y edición de un compartimento del pastillero.
///
/// Permite al usuario:
/// - Editar el nombre del medicamento
/// - Configurar hora y minutos de la alarma
/// - Ver y sobrescribir manualmente el estado del sensor IR
/// - Ordenar la liberación manual de la pastilla
class DetalleCompartimentoScreen extends StatefulWidget {
  final CompartimentoModel compartimento;

  const DetalleCompartimentoScreen({
    super.key,
    required this.compartimento,
  });

  @override
  State<DetalleCompartimentoScreen> createState() =>
      _DetalleCompartimentoScreenState();
}

class _DetalleCompartimentoScreenState
    extends State<DetalleCompartimentoScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  late TextEditingController _medicamentoController;
  late int _hora;
  late int _minutos;
  late bool _sensorIr;
  late bool _liberada;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final c = widget.compartimento;
    _medicamentoController = TextEditingController(text: c.medicamento);
    _hora = c.hora;
    _minutos = c.minutos;
    _sensorIr = c.sensorIrActivo;
    _liberada = c.pastillaLiberada;
  }

  @override
  void dispose() {
    _medicamentoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comp = widget.compartimento;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Compartimento ${comp.compartimentoId}'),
        backgroundColor: theme.colorScheme.primaryContainer,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Encabezado ──
            _buildEncabezado(comp, theme),
            const SizedBox(height: 24),

            // ── Medicamento ──
            _buildSeccionTitulo('Medicamento', Icons.medication),
            const SizedBox(height: 8),
            TextFormField(
              controller: _medicamentoController,
              decoration: const InputDecoration(
                labelText: 'Nombre del medicamento',
                hintText: 'Ej: Omeprazol 20mg',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.medication_liquid),
              ),
            ),
            const SizedBox(height: 24),

            // ── Horario ──
            _buildSeccionTitulo('Horario de dosis', Icons.schedule),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildSelectorNumero(
                    label: 'Hora',
                    valor: _hora,
                    minimo: 0,
                    maximo: 23,
                    onChanged: (v) => setState(() => _hora = v),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSelectorNumero(
                    label: 'Minutos',
                    valor: _minutos,
                    minimo: 0,
                    maximo: 59,
                    paso: 5,
                    onChanged: (v) => setState(() => _minutos = v),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  '⏰ Hora programada: ',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ),
            Center(
              child: Text(
                '${_hora.toString().padLeft(2, '0')}:${_minutos.toString().padLeft(2, '0')}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Estado del Sensor IR ──
            _buildSeccionTitulo('Sensor Infrarrojo', Icons.sensors),
            Card(
              child: SwitchListTile(
                title: const Text('Sensor IR activo'),
                subtitle: Text(
                  _sensorIr
                      ? '✅ Pastilla detectada como tomada'
                      : '⏳ No se ha detectado toma',
                ),
                value: _sensorIr,
                activeColor: Colors.green,
                onChanged: (v) async {
                  setState(() => _sensorIr = v);
                  await _firebaseService.actualizarSensorIR(
                      comp.compartimentoId, v);
                },
                secondary: Icon(
                  _sensorIr ? Icons.sensors : Icons.sensors_off,
                  color: _sensorIr ? Colors.green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Estado de Liberación ──
            _buildSeccionTitulo('Liberación de pastilla', Icons.lock_open),
            Card(
              child: SwitchListTile(
                title: const Text('Pastilla liberada'),
                subtitle: Text(
                  _liberada
                      ? '✅ El mecanismo dispensó la pastilla hoy'
                      : '🔒 Pastilla aún no dispensada',
                ),
                value: _liberada,
                activeColor: Colors.blue,
                onChanged: (v) async {
                  setState(() => _liberada = v);
                  await _firebaseService.actualizarLiberacion(
                      comp.compartimentoId, v);
                },
                secondary: Icon(
                  _liberada ? Icons.lock_open : Icons.lock,
                  color: _liberada ? Colors.blue : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Botón Guardar ──
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardarCambios,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando…' : 'Guardar en Firebase'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Botón de configuración avanzada de horario ──
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConfiguracionHorarioScreen(
                        compartimento: widget.compartimento,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.tune),
                label: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Configurar horario avanzado',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Condiciones previas · Tiempo de espera · Acción por defecto',
                        style: TextStyle(fontSize: 11)),
                  ],
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  alignment: Alignment.centerLeft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // Widgets auxiliares
  // ---------------------------------------------------------------------------

  Widget _buildEncabezado(CompartimentoModel comp, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              '${comp.compartimentoId}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            comp.medicamento.isEmpty ? 'Sin medicamento' : comp.medicamento,
            style: theme.textTheme.titleMedium,
          ),
          Text(
            'Última actualización: ${comp.fechaRegistro}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionTitulo(String titulo, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          titulo,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorNumero({
    required String label,
    required int valor,
    required int minimo,
    required int maximo,
    required ValueChanged<int> onChanged,
    int paso = 1,
  }) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: valor > minimo
                  ? () => onChanged(valor - paso < minimo ? minimo : valor - paso)
                  : null,
            ),
            SizedBox(
              width: 48,
              child: Text(
                valor.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: valor < maximo
                  ? () => onChanged(valor + paso > maximo ? maximo : valor + paso)
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Lógica de guardado
  // ---------------------------------------------------------------------------

  Future<void> _guardarCambios() async {
    setState(() => _guardando = true);

    final now = DateTime.now();
    final fechaHoy =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final actualizado = widget.compartimento.copyWith(
      medicamento: _medicamentoController.text.trim(),
      hora: _hora,
      minutos: _minutos,
      sensorIrActivo: _sensorIr,
      pastillaLiberada: _liberada,
      fechaRegistro: fechaHoy,
    );

    try {
      await _firebaseService.updateCompartimento(actualizado);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Compartimento ${actualizado.compartimentoId} guardado'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}
