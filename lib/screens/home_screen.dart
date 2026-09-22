import 'package:flutter/material.dart';
import '../models/compartimento_model.dart';
import '../services/firebase_service.dart';
import 'detalle_compartimento_screen.dart';
import '../widgets/compartimento_card.dart';

/// Pantalla principal — muestra los 7 compartimentos del pastillero
/// en tiempo real usando un Stream de Firebase.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    // Inicializar los 7 compartimentos en Firebase si no existen
    _firebaseService.inicializarCompartimentos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medical_services_outlined),
            SizedBox(width: 8),
            Text('Pastillero DDP106'),
          ],
        ),
        actions: [
          // Botón para reiniciar estados diarios manualmente
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reiniciar estados del día',
            onPressed: _confirmarReinicio,
          ),
        ],
      ),
      body: StreamBuilder<List<CompartimentoModel>>(
        stream: _firebaseService.watchCompartimentos(),
        builder: (context, snapshot) {
          // ── Estado de carga ──
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Conectando con Firebase…'),
                ],
              ),
            );
          }

          // ── Estado de error ──
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error de conexión\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final compartimentos = snapshot.data ?? [];

          // ── Resumen del estado ──
          return Column(
            children: [
              _buildResumenBar(compartimentos),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: compartimentos.length,
                  itemBuilder: (context, index) {
                    final comp = compartimentos[index];
                    return CompartimentoCard(
                      compartimento: comp,
                      onTap: () => _abrirDetalle(comp),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets auxiliares
  // ---------------------------------------------------------------------------

  /// Barra superior con estadísticas del día.
  Widget _buildResumenBar(List<CompartimentoModel> lista) {
    final tomadas = lista.where((c) => c.sensorIrActivo).length;
    final liberadas = lista.where((c) => c.pastillaLiberada).length;
    final pendientes = 7 - tomadas;

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip(Icons.check_circle, '$tomadas', 'Tomadas', Colors.green),
          _statChip(Icons.lock_open, '$liberadas', 'Liberadas', Colors.blue),
          _statChip(Icons.pending, '$pendientes', 'Pendientes', Colors.orange),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String count, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        Text(count,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Navegación y diálogos
  // ---------------------------------------------------------------------------

  void _abrirDetalle(CompartimentoModel compartimento) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DetalleCompartimentoScreen(compartimento: compartimento),
      ),
    );
  }

  void _confirmarReinicio() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reiniciar estados'),
        content: const Text(
          '¿Reiniciar sensor IR y liberación de los 7 compartimentos?\n'
          'Esto marca el inicio de un nuevo día.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _firebaseService.reiniciarEstadosDiarios();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('✅ Estados reiniciados para hoy')),
              );
            },
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
  }
}
