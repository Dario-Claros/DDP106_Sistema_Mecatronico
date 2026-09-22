import 'package:flutter/material.dart';
import '../models/compartimento_model.dart';
import '../services/firebase_service.dart';

/// Pantalla de configuración avanzada de horario y condiciones previas
/// para un compartimento específico del pastillero.
///
/// Funcionalidad:
/// - Selector de hora y minutos (int) para el dispensado
/// - Condiciones previas Sí/No (ej. ¿Ya desayunaste?)
/// - Tiempo de espera (15–30 min) antes de acción por defecto
/// - Acción por defecto: "Dispensar por importancia" o "Cancelar dosis"
///
/// Toda la configuración se escribe en Firebase → el ESP32 la lee.
class ConfiguracionHorarioScreen extends StatefulWidget {
  final CompartimentoModel compartimento;

  const ConfiguracionHorarioScreen({
    super.key,
    required this.compartimento,
  });

  @override
  State<ConfiguracionHorarioScreen> createState() =>
      _ConfiguracionHorarioScreenState();
}

class _ConfiguracionHorarioScreenState
    extends State<ConfiguracionHorarioScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  late int _hora;
  late int _minutos;
  late List<CondicionModel> _condiciones;
  late int _tiempoEspera;
  late AccionPorDefecto _accionPorDefecto;
  bool _guardando = false;

  // Preguntas sugeridas para condiciones (el cuidador puede personalizarlas)
  static const List<String> _preguntasSugeridas = [
    '¿Ya desayunaste?',
    '¿Ya almorzaste?',
    '¿Ya cenaste?',
    '¿Tomaste agua en las últimas 2 horas?',
    '¿Te sientes bien hoy?',
    '¿Ya te levantaste de la cama?',
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.compartimento;
    _hora = c.hora;
    _minutos = c.minutos;
    _condiciones = List.from(c.condiciones);
    _tiempoEspera = c.tiempoEsperaMinutos;
    _accionPorDefecto = c.accionPorDefecto;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Configurar Compartimento ${widget.compartimento.compartimentoId}'),
        backgroundColor: theme.colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Ayuda',
            onPressed: _mostrarAyuda,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info del medicamento ──
            _buildInfoChip(theme),
            const SizedBox(height: 20),

            // ── 1. Selector de hora ──
            _buildSeccion(
              icono: Icons.schedule,
              titulo: 'Hora de dispensado',
              subtitulo: 'El pastillero liberará la pastilla a esta hora exacta.',
              child: _buildSelectorHora(theme),
            ),
            const SizedBox(height: 20),

            // ── 2. Condiciones previas ──
            _buildSeccion(
              icono: Icons.quiz_outlined,
              titulo: 'Condiciones previas de toma',
              subtitulo:
                  'El pastillero físico preguntará esto al paciente antes de dispensar. '
                  'Solo acepta respuesta Sí (✓) o No (✗) con los botones físicos.',
              child: _buildCondiciones(theme),
            ),
            const SizedBox(height: 20),

            // ── 3. Tiempo de espera ──
            _buildSeccion(
              icono: Icons.timer_outlined,
              titulo: 'Tiempo de espera',
              subtitulo:
                  'Si el paciente no responde a las condiciones, '
                  'esperar este tiempo antes de actuar automáticamente.',
              child: _buildSelectorTiempoEspera(theme),
            ),
            const SizedBox(height: 20),

            // ── 4. Acción por defecto ──
            _buildSeccion(
              icono: Icons.settings_suggest_outlined,
              titulo: 'Acción por defecto (sin respuesta)',
              subtitulo:
                  'Define qué debe hacer el pastillero si el paciente '
                  'no responde las condiciones tras el tiempo de espera.',
              child: _buildAccionPorDefecto(theme),
            ),
            const SizedBox(height: 32),

            // ── Botón Guardar ──
            _buildBotonGuardar(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGETS DE SECCIÓN
  // ===========================================================================

  Widget _buildInfoChip(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary,
            radius: 20,
            child: Text(
              '${widget.compartimento.compartimentoId}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.compartimento.medicamento.isEmpty
                      ? 'Sin medicamento'
                      : widget.compartimento.medicamento,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Horario actual: ${widget.compartimento.horaFormateada}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Wrapper visual estándar para cada sección de configuración.
  Widget _buildSeccion({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(titulo,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitulo,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  // ===========================================================================
  // 1. SELECTOR DE HORA
  // ===========================================================================

  Widget _buildSelectorHora(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            // Display grande de la hora
            Text(
              '${_hora.toString().padLeft(2, '0')}:${_minutos.toString().padLeft(2, '0')}',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Selector de horas
                Expanded(
                  child: _buildRueda(
                    label: 'HORA',
                    valor: _hora,
                    min: 0,
                    max: 23,
                    onChanged: (v) => setState(() => _hora = v),
                    formatear: (v) => v.toString().padLeft(2, '0'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(':',
                      style: theme.textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                // Selector de minutos (saltos de 5)
                Expanded(
                  child: _buildRueda(
                    label: 'MIN',
                    valor: _minutos,
                    min: 0,
                    max: 55,
                    paso: 5,
                    onChanged: (v) => setState(() => _minutos = v),
                    formatear: (v) => v.toString().padLeft(2, '0'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Botón para abrir el TimePicker nativo de Android
            OutlinedButton.icon(
              icon: const Icon(Icons.access_time),
              label: const Text('Abrir selector de hora del sistema'),
              onPressed: _abrirTimePicker,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRueda({
    required String label,
    required int valor,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    required String Function(int) formatear,
    int paso = 1,
  }) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: Colors.grey)),
        const SizedBox(height: 4),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 32),
          onPressed: () {
            int nuevo = valor + paso;
            if (nuevo > max) nuevo = min;
            onChanged(nuevo);
          },
        ),
        Text(formatear(valor),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () {
            int nuevo = valor - paso;
            if (nuevo < min) nuevo = max;
            onChanged(nuevo);
          },
        ),
      ],
    );
  }

  Future<void> _abrirTimePicker() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hora, minute: _minutos),
      helpText: 'Selecciona la hora de dispensado',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _hora = picked.hour;
        _minutos = picked.minute;
      });
    }
  }

  // ===========================================================================
  // 2. CONDICIONES PREVIAS
  // ===========================================================================

  Widget _buildCondiciones(ThemeData theme) {
    return Column(
      children: [
        // Lista de condiciones actuales
        if (_condiciones.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey, size: 18),
                SizedBox(width: 8),
                Text(
                  'Sin condiciones. La pastilla se dispensará\ndirectamente a la hora programada.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...List.generate(_condiciones.length, (i) {
            return _buildCondicionItem(i, theme);
          }),

        const SizedBox(height: 10),

        // Botón agregar condición
        if (_condiciones.length < 3)
          FilledButton.tonalIcon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar condición'),
            onPressed: _agregarCondicion,
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Máximo 3 condiciones permitidas.',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
          ),
      ],
    );
  }

  Widget _buildCondicionItem(int index, ThemeData theme) {
    final condicion = _condiciones[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    condicion.pregunta.isEmpty
                        ? 'Pregunta vacía'
                        : condicion.pregunta,
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Editar pregunta',
                  onPressed: () => _editarCondicion(index),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  tooltip: 'Eliminar',
                  onPressed: () =>
                      setState(() => _condiciones.removeAt(index)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Toggle Sí / No — respuesta requerida para permitir toma
            Row(
              children: [
                Text('Respuesta requerida:',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(width: 8),
                _buildBotonRespuesta(
                  label: 'Sí',
                  activo: condicion.respuestaRequerida,
                  color: Colors.green,
                  onTap: () => setState(() {
                    _condiciones[index] =
                        condicion.copyWith(respuestaRequerida: true);
                  }),
                ),
                const SizedBox(width: 6),
                _buildBotonRespuesta(
                  label: 'No',
                  activo: !condicion.respuestaRequerida,
                  color: Colors.red,
                  onTap: () => setState(() {
                    _condiciones[index] =
                        condicion.copyWith(respuestaRequerida: false);
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotonRespuesta({
    required String label,
    required bool activo,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: activo ? color : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: activo ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Future<void> _agregarCondicion() async {
    String? pregunta = await _mostrarDialogoPregunta();
    if (pregunta != null && pregunta.trim().isNotEmpty) {
      setState(() {
        _condiciones.add(CondicionModel(
          pregunta: pregunta.trim(),
          respuestaRequerida: true,
        ));
      });
    }
  }

  Future<void> _editarCondicion(int index) async {
    String? pregunta = await _mostrarDialogoPregunta(
        inicial: _condiciones[index].pregunta);
    if (pregunta != null && pregunta.trim().isNotEmpty) {
      setState(() {
        _condiciones[index] =
            _condiciones[index].copyWith(pregunta: pregunta.trim());
      });
    }
  }

  Future<String?> _mostrarDialogoPregunta({String inicial = ''}) async {
    final controller = TextEditingController(text: inicial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Condición previa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escribe una pregunta de Sí/No que se mostrará al paciente:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                hintText: 'Ej: ¿Ya desayunaste?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            // Sugerencias rápidas
            const Text('Sugerencias rápidas:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _preguntasSugeridas
                  .map((s) => ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 11)),
                        onPressed: () => controller.text = s,
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. TIEMPO DE ESPERA
  // ===========================================================================

  Widget _buildSelectorTiempoEspera(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_tiempoEspera minutos',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary)),
                Row(
                  children: [
                    _buildChipTiempo(15),
                    const SizedBox(width: 6),
                    _buildChipTiempo(20),
                    const SizedBox(width: 6),
                    _buildChipTiempo(30),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: _tiempoEspera.toDouble(),
              min: 15,
              max: 30,
              divisions: 3,
              label: '$_tiempoEspera min',
              onChanged: (v) => setState(() => _tiempoEspera = v.round()),
            ),
            Text(
              'El pastillero esperará $_tiempoEspera minutos después de la hora '
              'programada antes de ejecutar la acción por defecto.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipTiempo(int minutos) {
    final activo = _tiempoEspera == minutos;
    return ChoiceChip(
      label: Text('${minutos}m'),
      selected: activo,
      onSelected: (_) => setState(() => _tiempoEspera = minutos),
    );
  }

  // ===========================================================================
  // 4. ACCIÓN POR DEFECTO
  // ===========================================================================

  Widget _buildAccionPorDefecto(ThemeData theme) {
    return Column(
      children: AccionPorDefecto.values.map((accion) {
        final seleccionada = _accionPorDefecto == accion;
        final color = accion == AccionPorDefecto.dispensarPorImportancia
            ? Colors.blue
            : Colors.red;
        final icono = accion == AccionPorDefecto.dispensarPorImportancia
            ? Icons.medication_outlined
            : Icons.cancel_outlined;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: seleccionada ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: RadioListTile<AccionPorDefecto>(
            value: accion,
            groupValue: _accionPorDefecto,
            onChanged: (v) => setState(() => _accionPorDefecto = v!),
            activeColor: color,
            title: Row(
              children: [
                Icon(icono, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  accion.etiqueta,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: seleccionada ? color : null),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(accion.descripcion,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ===========================================================================
  // BOTÓN GUARDAR
  // ===========================================================================

  Widget _buildBotonGuardar() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _guardando ? null : _guardarConfiguracion,
        icon: _guardando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.cloud_upload_outlined),
        label: Text(_guardando ? 'Guardando en Firebase…' : 'Guardar configuración'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _guardarConfiguracion() async {
    setState(() => _guardando = true);
    try {
      final actualizado = widget.compartimento.copyWith(
        hora: _hora,
        minutos: _minutos,
        condiciones: _condiciones,
        tiempoEsperaMinutos: _tiempoEspera,
        accionPorDefecto: _accionPorDefecto,
      );
      await _firebaseService.updateCompartimento(actualizado);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Compartimento ${actualizado.compartimentoId} configurado'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ===========================================================================
  // DIÁLOGO DE AYUDA
  // ===========================================================================

  void _mostrarAyuda() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('¿Cómo funciona?'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AyudaItem(
                icono: Icons.schedule,
                titulo: 'Hora de dispensado',
                detalle:
                    'El pastillero físico abrirá el compartimento a esta hora exacta.',
              ),
              _AyudaItem(
                icono: Icons.quiz_outlined,
                titulo: 'Condiciones previas',
                detalle:
                    'Antes de abrir, el display del pastillero mostrará cada pregunta. '
                    'El paciente responde con los botones físicos: ✓ (Sí) o ✗ (No). '
                    'Si la respuesta no coincide con la requerida, el pastillero esperará.',
              ),
              _AyudaItem(
                icono: Icons.timer_outlined,
                titulo: 'Tiempo de espera',
                detalle:
                    'Si el paciente no responde en este tiempo, se ejecuta la acción por defecto.',
              ),
              _AyudaItem(
                icono: Icons.settings_suggest_outlined,
                titulo: 'Acción por defecto',
                detalle:
                    '"Dispensar por importancia": abre el compartimento aunque no se cumplan las condiciones.\n'
                    '"Cancelar dosis": no dispensa y registra la toma como omitida.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Widget auxiliar para el diálogo de ayuda
// ===========================================================================

class _AyudaItem extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;

  const _AyudaItem({
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: Colors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(detalle, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
