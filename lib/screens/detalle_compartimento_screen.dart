import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/compartimento_model.dart';
import '../services/firebase_service.dart';

/// Pantalla de detalle para editar un compartimento individual.
///
/// Permite modificar: medicamento, hora, minutos, condición previa,
/// mensaje de condición, liberar por emergencia, e intentos.
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

  static const List<String> _opcionesPregunta = [
    '¿Ya desayunaste?',
    '¿Ya almorzaste?',
    '¿Ya cenaste?',
    '¿Ya comiste?',
  ];

  late TextEditingController _medicamentoController;
  late TextEditingController _horaController;
  late TextEditingController _minutosController;
  late TextEditingController _intentosController;

  late int _hora;
  late int _minutos;
  late bool _hayCondicion;
  late String _preguntaSeleccionada;
  late bool _liberarPorEmergencia;
  late int _intentos;

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final comp = widget.compartimento;
    _medicamentoController = TextEditingController(text: comp.medicamento);
    _hora = comp.hora.clamp(0, 23);
    _minutos = comp.minutos.clamp(0, 59);
    _hayCondicion = comp.hayCondicion;

    // Si tiene condición, aseguramos que la pregunta esté dentro de las opciones
    // y que el mínimo de intentos sea 1 (como pidió Isel).
    if (_opcionesPregunta.contains(comp.msgCondicion.trim())) {
      _preguntaSeleccionada = comp.msgCondicion.trim();
    } else {
      _preguntaSeleccionada = _opcionesPregunta.first;
    }

    _liberarPorEmergencia = _hayCondicion ? comp.liberarPorEmergencia : false;
    _intentos = _hayCondicion
        ? (comp.intentos < 1 ? 1 : comp.intentos.clamp(1, 10))
        : 0;

    _horaController =
        TextEditingController(text: _hora.toString().padLeft(2, '0'));
    _minutosController =
        TextEditingController(text: _minutos.toString().padLeft(2, '0'));
    _intentosController = TextEditingController(
        text: (_intentos < 1 ? 1 : _intentos).toString().padLeft(2, '0'));
  }

  @override
  void dispose() {
    _medicamentoController.dispose();
    _horaController.dispose();
    _minutosController.dispose();
    _intentosController.dispose();
    super.dispose();
  }

  void _actualizarHora(int nuevaHora, {bool actualizarTexto = true}) {
    final valor = nuevaHora.clamp(0, 23);
    setState(() {
      _hora = valor;
      if (actualizarTexto) {
        _horaController.text = valor.toString().padLeft(2, '0');
      }
    });
  }

  void _actualizarMinutos(int nuevosMinutos, {bool actualizarTexto = true}) {
    final valor = nuevosMinutos.clamp(0, 59);
    setState(() {
      _minutos = valor;
      if (actualizarTexto) {
        _minutosController.text = valor.toString().padLeft(2, '0');
      }
    });
  }

  void _actualizarIntentos(int nuevosIntentos, {bool actualizarTexto = true}) {
    final valor = nuevosIntentos.clamp(1, 10);
    setState(() {
      _intentos = valor;
      if (actualizarTexto) {
        _intentosController.text = valor.toString().padLeft(2, '0');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final comp = widget.compartimento;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Compartimento ${comp.compartimentoId}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            _buildEncabezado(comp, theme),
            const SizedBox(height: 20),

            // Medicamento
            _buildSeccionTitulo('Medicamento', Icons.medication),
            const SizedBox(height: 8),
            TextField(
              controller: _medicamentoController,
              decoration: const InputDecoration(
                hintText: 'Ej: Ibuprofeno 400mg',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 20),

            // Hora programada (con teclado numérico + botones sin overflow)
            _buildSeccionTitulo('Hora programada (formato 24h)', Icons.schedule),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _buildSelectorNumeroEditable(
                        label: 'Hora (0-23)',
                        valor: _hora,
                        minimo: 0,
                        maximo: 23,
                        controller: _horaController,
                        onStepChanged: (v) => _actualizarHora(v),
                        onTextChanged: (v) =>
                            _actualizarHora(v, actualizarTexto: false),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        ':',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      child: _buildSelectorNumeroEditable(
                        label: 'Min (0-59)',
                        valor: _minutos,
                        minimo: 0,
                        maximo: 59,
                        controller: _minutosController,
                        onStepChanged: (v) => _actualizarMinutos(v),
                        onTextChanged: (v) =>
                            _actualizarMinutos(v, actualizarTexto: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Condición previa
            _buildSeccionTitulo('Condición previa', Icons.help_outline),
            const SizedBox(height: 8),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('¿Tiene condición?'),
                    subtitle: Text(
                      _hayCondicion
                          ? 'El ESP32 preguntará si ya comió antes de dispensar'
                          : 'Dispensar directamente cuando llegue la hora',
                    ),
                    value: _hayCondicion,
                    activeColor: Colors.blue,
                    onChanged: (v) => setState(() {
                      _hayCondicion = v;
                      if (v) {
                        if (_intentos < 1) {
                          _intentos = 1;
                          _intentosController.text = '01';
                        }
                      } else {
                        _liberarPorEmergencia = false;
                        _intentos = 0;
                      }
                    }),
                    secondary: Icon(
                      _hayCondicion ? Icons.quiz : Icons.quiz_outlined,
                      color: _hayCondicion ? Colors.blue : Colors.grey,
                    ),
                  ),
                  if (_hayCondicion) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Selecciona la pregunta para la pantalla LCD:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            value: _preguntaSeleccionada,
                            decoration: const InputDecoration(
                              labelText: 'Pregunta al paciente',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.chat_bubble_outline),
                            ),
                            items: _opcionesPregunta
                                .map((pregunta) => DropdownMenuItem<String>(
                                      value: pregunta,
                                      child: Text(pregunta),
                                    ))
                                .toList(),
                            onChanged: (nueva) {
                              if (nueva != null) {
                                setState(() => _preguntaSeleccionada = nueva);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Liberar por emergencia e Intentos SOLO aparecen si tiene condición
            if (_hayCondicion) ...[
              const SizedBox(height: 16),
              _buildSeccionTitulo(
                  'Liberación de emergencia', Icons.warning_amber),
              const SizedBox(height: 8),
              Card(
                child: SwitchListTile(
                  title: const Text('Liberar por emergencia'),
                  subtitle: Text(
                    _liberarPorEmergencia
                        ? 'Se dispensará como último recurso si agota los intentos'
                        : 'No se dispensará si el paciente dice NO en todos los intentos',
                  ),
                  value: _liberarPorEmergencia,
                  activeColor: Colors.red,
                  onChanged: (v) => setState(() => _liberarPorEmergencia = v),
                  secondary: Icon(
                    _liberarPorEmergencia
                        ? Icons.emergency
                        : Icons.emergency_outlined,
                    color: _liberarPorEmergencia ? Colors.red : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildSeccionTitulo(
                  'Intentos de confirmación (mínimo 1)', Icons.repeat),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 180,
                      child: _buildSelectorNumeroEditable(
                        label: 'Intentos (1-10)',
                        valor: _intentos < 1 ? 1 : _intentos,
                        minimo: 1,
                        maximo: 10,
                        controller: _intentosController,
                        onStepChanged: (v) => _actualizarIntentos(v),
                        onTextChanged: (v) =>
                            _actualizarIntentos(v, actualizarTexto: false),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // Botón Guardar
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
                label: Text(_guardando ? 'Guardando...' : 'Guardar'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
        Expanded(
          child: Text(
            titulo,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  /// Selector numérico compacto que permite tanto usar los botones (-) y (+)
  /// como tocar el número para escribirlo directamente con el teclado.
  Widget _buildSelectorNumeroEditable({
    required String label,
    required int valor,
    required int minimo,
    required int maximo,
    required TextEditingController controller,
    required ValueChanged<int> onStepChanged,
    required ValueChanged<int> onTextChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: valor > minimo ? () => onStepChanged(valor - 1) : null,
            ),
            SizedBox(
              width: 54,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: (texto) {
                  if (texto.isEmpty) return;
                  final parsed = int.tryParse(texto);
                  if (parsed != null) {
                    onTextChanged(parsed.clamp(minimo, maximo));
                  }
                },
                onSubmitted: (texto) {
                  final parsed = int.tryParse(texto) ?? minimo;
                  onStepChanged(parsed.clamp(minimo, maximo));
                },
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.add_circle_outline),
              onPressed: valor < maximo ? () => onStepChanged(valor + 1) : null,
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
    // Asegurar que cualquier número escrito manualmente quede validado
    final horaFinal =
        (int.tryParse(_horaController.text) ?? _hora).clamp(0, 23);
    final minutosFinal =
        (int.tryParse(_minutosController.text) ?? _minutos).clamp(0, 59);
    final intentosFinal = _hayCondicion
        ? (int.tryParse(_intentosController.text) ?? _intentos).clamp(1, 10)
        : 0;

    setState(() => _guardando = true);

    final now = DateTime.now();
    final fechaHoy =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final actualizado = widget.compartimento.copyWith(
      medicamento: _medicamentoController.text.trim(),
      hora: horaFinal,
      minutos: minutosFinal,
      hayCondicion: _hayCondicion,
      msgCondicion: _hayCondicion ? _preguntaSeleccionada : '',
      liberarPorEmergencia: _hayCondicion ? _liberarPorEmergencia : false,
      intentos: intentosFinal,
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
