import 'package:flutter/material.dart';
import '../models/compartimento_model.dart';
import '../services/firebase_service.dart';
import 'detalle_compartimento_screen.dart';
import 'historial_screen.dart';
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
          TextButton.icon(
            onPressed: _abrirHistorial,
            icon: const Icon(Icons.assessment_outlined),
            label: const Text('Reportes'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<CompartimentoModel>>(
        stream: _firebaseService.watchCompartimentos(),
        builder: (context, snapshot) {
          // Estado de carga
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Conectando con Firebase...'),
                ],
              ),
            );
          }

          // Estado de error
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

          // Resumen del estado
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
    final configurados = lista.where((c) => c.medicamento.isNotEmpty).length;
    final conCondicion = lista.where((c) => c.hayCondicion).length;
    final emergencia = lista.where((c) => c.liberarPorEmergencia).length;

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statChip(Icons.medication, '$configurados', 'Configurados', Colors.blue),
          _statChip(Icons.help_outline, '$conCondicion', 'Con condición', Colors.orange),
          _statChip(Icons.warning_amber, '$emergencia', 'Emergencia', Colors.red),
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
  // Navegación
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

  void _abrirHistorial() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const HistorialScreen(),
      ),
    );
  }
}
