import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

/// Pantalla de Reportes e Historial de toma de medicamentos.
///
/// Lee en tiempo real `/pastillero/eventos/historial` y `/pastillero/eventos/ultimo_evento`
/// para mostrar estadísticas de cumplimiento (dispensado, retirado, ignorado) y la
/// bitácora cronológica de eventos enviados por el ESP32.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final DatabaseReference _eventosRef =
      FirebaseDatabase.instance.ref('pastillero/eventos');

  String _filtroTipo = 'todos';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assessment_outlined),
            SizedBox(width: 8),
            Text('Reportes e Historial'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Limpiar historial',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmarLimpiarHistorial,
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _eventosRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error al cargar historial: ${snapshot.error}'),
            );
          }

          final rawData = snapshot.data?.snapshot.value;
          Map<dynamic, dynamic> eventosMap = {};
          if (rawData is Map) {
            eventosMap = Map<dynamic, dynamic>.from(rawData);
          }

          // Extraer ultimo_evento
          Map<dynamic, dynamic>? ultimoEvento;
          if (eventosMap['ultimo_evento'] is Map) {
            ultimoEvento =
                Map<dynamic, dynamic>.from(eventosMap['ultimo_evento'] as Map);
          }

          // Extraer lista de historial
          final List<Map<String, dynamic>> listaHistorial = [];
          if (eventosMap['historial'] is Map) {
            final histMap =
                Map<dynamic, dynamic>.from(eventosMap['historial'] as Map);
            histMap.forEach((key, value) {
              if (value is Map) {
                final item = Map<String, dynamic>.from(
                  value.map((k, v) => MapEntry(k.toString(), v)),
                );
                item['id'] = key.toString();
                listaHistorial.add(item);
              }
            });
          }

          // Ordenar del más reciente al más antiguo
          listaHistorial.sort((a, b) {
            final tsA = (a['timestamp'] as String?) ?? '';
            final tsB = (b['timestamp'] as String?) ?? '';
            return tsB.compareTo(tsA);
          });

          // Contabilizar estadísticas
          int totalDispensados = 0;
          int totalRetirados = 0;
          int totalIgnorados = 0;

          for (final item in listaHistorial) {
            final t = ((item['tipo'] as String?) ?? '').toLowerCase();
            if (t.startsWith('dispensad')) {
              totalDispensados++;
            } else if (t.startsWith('retirad')) {
              totalRetirados++;
            } else if (t.startsWith('ignorad')) {
              totalIgnorados++;
            }
          }

          final int totalDecisiones = totalRetirados + totalIgnorados;
          final double porcentajeCumplimiento = totalDecisiones > 0
              ? (totalRetirados / totalDecisiones) * 100
              : 0.0;

          // Filtrar lista según pestaña seleccionada
          final listaFiltrada = listaHistorial.where((item) {
            if (_filtroTipo == 'todos') return true;
            final t = ((item['tipo'] as String?) ?? '').toLowerCase();
            return t.startsWith(_filtroTipo);
          }).toList();

          return Column(
            children: [
              // Tarjeta de resumen estadístico
              _buildResumenEstadistico(
                theme: theme,
                dispensados: totalDispensados,
                retirados: totalRetirados,
                ignorados: totalIgnorados,
                cumplimiento: porcentajeCumplimiento,
                hayDecisiones: totalDecisiones > 0,
              ),

              // Tarjeta del último evento en vivo del ESP32
              if (ultimoEvento != null) _buildTarjetaUltimoEvento(ultimoEvento),

              // Filtros por tipo de evento
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFiltroChip('todos', 'Todos (${listaHistorial.length})'),
                      const SizedBox(width: 8),
                      _buildFiltroChip(
                          'dispensad', 'Dispensados ($totalDispensados)'),
                      const SizedBox(width: 8),
                      _buildFiltroChip(
                          'retirad', 'Retirados ($totalRetirados)'),
                      const SizedBox(width: 8),
                      _buildFiltroChip(
                          'ignorad', 'Ignorados ($totalIgnorados)'),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1),

              // Lista de eventos del historial
              Expanded(
                child: listaFiltrada.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off,
                                  size: 56, color: Colors.grey),
                              SizedBox(height: 12),
                              Text(
                                'Aún no hay eventos registrados en este filtro.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: listaFiltrada.length,
                        itemBuilder: (context, index) {
                          return _buildItemHistorial(listaFiltrada[index]);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildResumenEstadistico({
    required ThemeData theme,
    required int dispensados,
    required int retirados,
    required int ignorados,
    required double cumplimiento,
    required bool hayDecisiones,
  }) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatBox(
                icon: Icons.medication_liquid,
                valor: '$dispensados',
                etiqueta: 'Dispensados',
                color: Colors.blue,
              ),
              _buildStatBox(
                icon: Icons.check_circle_outline,
                valor: '$retirados',
                etiqueta: 'Retirados',
                color: Colors.green,
              ),
              _buildStatBox(
                icon: Icons.warning_amber_rounded,
                valor: '$ignorados',
                etiqueta: 'Ignorados',
                color: Colors.red,
              ),
            ],
          ),
          if (hayDecisiones) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Cumplimiento de toma:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: cumplimiento / 100,
                      minHeight: 8,
                      backgroundColor: Colors.red.withOpacity(0.25),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${cumplimiento.toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required IconData icon,
    required String valor,
    required String etiqueta,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(etiqueta, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildTarjetaUltimoEvento(Map<dynamic, dynamic> ultimo) {
    final tipo = ((ultimo['tipo'] as String?) ?? '').trim();
    final med = ((ultimo['medicamento'] as String?) ?? '').trim();
    final comp =
        (ultimo['compartimiento'] ?? ultimo['compartimento'] ?? '-').toString();

    final info = _obtenerEstiloEvento(tipo);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Card(
        elevation: 0,
        color: info.color.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: info.color.withOpacity(0.4)),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(info.icono, color: info.color),
          title: Text(
            'Último estado del ESP32: ${info.titulo}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: info.color,
              fontSize: 13,
            ),
          ),
          subtitle: Text(
            'Pastilla: ${med.isEmpty ? "Sin nombre" : med} • Compartimento $comp',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildFiltroChip(String clave, String texto) {
    final seleccionado = _filtroTipo == clave;
    return ChoiceChip(
      label: Text(texto, style: const TextStyle(fontSize: 12)),
      selected: seleccionado,
      onSelected: (_) => setState(() => _filtroTipo = clave),
    );
  }

  Widget _buildItemHistorial(Map<String, dynamic> item) {
    final tipo = ((item['tipo'] as String?) ?? '').trim();
    final med = ((item['medicamento'] as String?) ?? 'Medicamento').trim();
    final comp =
        (item['compartimiento'] ?? item['compartimento'] ?? '-').toString();
    final fecha = (item['fecha'] as String?) ?? '';
    final hora = (item['hora'] as String?) ?? '';

    final info = _obtenerEstiloEvento(tipo);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: info.color.withOpacity(0.15),
          child: Icon(info.icono, color: info.color),
        ),
        title: Text(
          'La pastilla $med fue ${info.participio}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text('Compartimento $comp • $fecha $hora'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: info.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            info.titulo,
            style: TextStyle(
              color: info.color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  _EstiloEvento _obtenerEstiloEvento(String tipo) {
    final t = tipo.toLowerCase();
    if (t.startsWith('dispensad')) {
      return const _EstiloEvento(
        titulo: 'Dispensado',
        participio: 'dispensada',
        icono: Icons.medication_liquid,
        color: Colors.blue,
      );
    } else if (t.startsWith('retirad')) {
      return const _EstiloEvento(
        titulo: 'Retirado',
        participio: 'retirada',
        icono: Icons.check_circle,
        color: Colors.green,
      );
    } else if (t.startsWith('ignorad')) {
      return const _EstiloEvento(
        titulo: 'Ignorado',
        participio: 'ignorada',
        icono: Icons.error_outline,
        color: Colors.red,
      );
    }
    return _EstiloEvento(
      titulo: tipo.isEmpty ? 'Desconocido' : tipo,
      participio: 'registrada ($tipo)',
      icono: Icons.info_outline,
      color: Colors.grey,
    );
  }

  Future<void> _confirmarLimpiarHistorial() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar historial'),
        content: const Text(
          '¿Deseas borrar los registros guardados en /pastillero/eventos/historial?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _eventosRef.child('historial').remove();
    }
  }
}

class _EstiloEvento {
  final String titulo;
  final String participio;
  final IconData icono;
  final Color color;

  const _EstiloEvento({
    required this.titulo,
    required this.participio,
    required this.icono,
    required this.color,
  });
}
