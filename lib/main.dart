import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'services/notificacion_service.dart';
import 'services/monitor_pastilla_service.dart';
import 'services/firebase_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // El manejo de notificaciones en background iría aquí
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Arranca la UI inmediatamente
  runApp(const PastilleroApp());
}

class PastilleroApp extends StatefulWidget {
  const PastilleroApp({super.key});

  @override
  State<PastilleroApp> createState() => _PastilleroAppState();
}

class _PastilleroAppState extends State<PastilleroApp> {
  // Inicializador de Firebase
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pastillero DDP106',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
        useMaterial3: true,
      ),
      home: FutureBuilder(
        future: _initialization,
        builder: (context, snapshot) {
          // Si hay error al conectar Firebase, mostrarlo en pantalla
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text(
                  'Error de Firebase:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                ),
              ),
            );
          }

          // Si Firebase ya conectó, lanzar el resto de servicios e ir al Splash
          if (snapshot.connectionState == ConnectionState.done) {
            _iniciarServiciosSecundarios();
            return const SplashScreen();
          }

          // Mientras espera a Firebase, mostrar pantalla de carga
          return const Scaffold(
            backgroundColor: Color(0xFF1976D2),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        },
      ),
    );
  }

  void _iniciarServiciosSecundarios() {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    NotificacionService().inicializar();
    MonitorPastillaService().iniciar();
    FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) {
        FirebaseService().guardarTokenCuidador(token);
      }
    }).catchError((e) => debugPrint("Error token: $e"));
  }
}
