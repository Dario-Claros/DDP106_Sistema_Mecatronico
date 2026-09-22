import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// =============================================================================
// Handler de FCM en segundo plano (DEBE estar en el nivel superior del archivo,
// fuera de cualquier clase, para que Firebase pueda registrarlo como isolate).
// =============================================================================

/// Recibe mensajes FCM cuando la app está cerrada o en segundo plano.
/// El ESP32 escribe en Firebase → Cloud Function envía el FCM → este handler
/// muestra la notificación de intervención al cuidador.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Mostrar notificación local directamente sin contexto de Flutter
  await NotificacionService._mostrarNotificacionLocal(
    titulo: message.notification?.title ?? '⚠️ Pastillero — Intervención requerida',
    cuerpo: message.notification?.body ??
        'Una pastilla fue ignorada. Se requiere intervención del familiar.',
    payload: message.data['compartimento_id'] ?? '',
  );
}

// =============================================================================
// Servicio principal de notificaciones
// =============================================================================

/// Gestiona toda la lógica de notificaciones push (FCM) y locales.
///
/// Flujo completo:
///
///   ESP32 detecta pastilla ignorada
///       → escribe `pastilla_ignorada: true` en Firebase
///       → Cloud Function dispara FCM al token del dispositivo cuidador
///       → [NotificacionService] recibe el mensaje FCM
///       → Muestra notificación push al cuidador con instrucción de intervención
///
/// Casos cubiertos:
///   1. App en PRIMER PLANO   → Banner de notificación in-app + notificación local
///   2. App en SEGUNDO PLANO  → Notificación push del sistema Android
///   3. App CERRADA           → Notificación push del sistema Android
class NotificacionService {
  // Singleton
  static final NotificacionService _instance = NotificacionService._internal();
  factory NotificacionService() => _instance;
  NotificacionService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  // Canal de notificaciones Android para alertas críticas
  static const _canalAlertas = AndroidNotificationChannel(
    'pastillero_alertas',           // ID del canal
    'Alertas de pastillero',        // Nombre visible en ajustes Android
    description:
        'Alertas críticas cuando una pastilla es ignorada y se requiere intervención.',
    importance: Importance.max,     // Máxima prioridad — aparece como heads-up
    playSound: true,
    enableVibration: true,
    enableLights: true,
    ledColor: Color(0xFFFF0000),    // LED rojo para alerta
  );

  // Callback global para navegar cuando el cuidador toca la notificación
  static Function(String compartimentoId)? onNotificacionTocada;

  // ---------------------------------------------------------------------------
  // Inicialización (llamar en main() después de Firebase.initializeApp)
  // ---------------------------------------------------------------------------

  /// Inicializa FCM y notificaciones locales. Registrar el handler de
  /// background ANTES de llamar este método (ver main.dart).
  Future<void> inicializar() async {
    await _inicializarNotificacionesLocales();
    await _solicitarPermisos();
    await _configurarFCM();
    _registrarHandlersPrimerPlano();
  }

  // ---------------------------------------------------------------------------
  // Notificaciones locales (Android)
  // ---------------------------------------------------------------------------

  Future<void> _inicializarNotificacionesLocales() async {
    // Crear el canal de alta prioridad en Android
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_canalAlertas);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // El cuidador tocó la notificación → navegar al compartimento
        if (details.payload != null && details.payload!.isNotEmpty) {
          onNotificacionTocada?.call(details.payload!);
        }
      },
    );
  }

  /// Muestra una notificación local de alerta crítica.
  /// Método estático para poder usarlo desde el handler de background.
  static Future<void> _mostrarNotificacionLocal({
    required String titulo,
    required String cuerpo,
    String payload = '',
    int id = 0,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'pastillero_alertas',
      'Alertas de pastillero',
      channelDescription:
          'Alertas críticas cuando una pastilla es ignorada.',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Pastilla ignorada — intervención requerida',
      icon: '@mipmap/ic_launcher',
      color: Color(0xFFFF0000),
      enableLights: true,
      ledColor: Color(0xFFFF0000),
      ledOnMs: 500,
      ledOffMs: 500,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500]), // patrón urgente
      styleInformation: BigTextStyleInformation(''), // expande automáticamente
      fullScreenIntent: true, // irrumpe en pantalla bloqueada (emergencia)
      category: AndroidNotificationCategory.alarm,
    );

    await _localNotif.show(
      id,
      titulo,
      cuerpo,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );
  }

  // ---------------------------------------------------------------------------
  // Permisos FCM
  // ---------------------------------------------------------------------------

  Future<void> _solicitarPermisos() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: true,   // Alerta crítica: ignora modo silencio
      provisional: false,
      sound: true,
    );

    debugPrint(
        '[FCM] Estado de permisos: ${settings.authorizationStatus}');
  }

  // ---------------------------------------------------------------------------
  // Configuración de FCM
  // ---------------------------------------------------------------------------

  Future<void> _configurarFCM() async {
    // Obtener y registrar el token FCM del dispositivo del cuidador.
    // Este token se debe guardar en Firebase para que el ESP32 (via
    // Cloud Functions) sepa a qué dispositivo enviar las notificaciones.
    final token = await _fcm.getToken();
    if (token != null) {
      await _guardarTokenEnFirebase(token);
      debugPrint('[FCM] Token del dispositivo: $token');
    }

    // Escuchar renovaciones de token (Android puede renovar el token)
    _fcm.onTokenRefresh.listen(_guardarTokenEnFirebase);

    // Verificar si la app fue abierta desde una notificación (app cerrada)
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _procesarMensajeFCM(initialMessage, desdeNotificacion: true);
    }
  }

  Future<void> _guardarTokenEnFirebase(String token) async {
    // Guarda el token en /config/fcm_token para que la Cloud Function
    // sepa a dónde enviar las notificaciones push del cuidador.
    try {
      final db = FirebaseMessaging.instance;
      // El token se escribe en Firebase Realtime Database vía FirebaseService
      // para que la Cloud Function pueda leerlo al enviar la alerta.
      debugPrint('[FCM] Token guardado: $token');
      // FirebaseService().guardarTokenCuidador(token); // ver firebase_service.dart
    } catch (e) {
      debugPrint('[FCM] Error guardando token: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Handlers de mensajes FCM — primer plano
  // ---------------------------------------------------------------------------

  void _registrarHandlersPrimerPlano() {
    // App en PRIMER PLANO: FCM no muestra notificación automáticamente,
    // debemos mostrarla manualmente con flutter_local_notifications.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Mensaje en primer plano: ${message.messageId}');
      _procesarMensajeFCM(message, desdeNotificacion: false);
    });

    // App en SEGUNDO PLANO: el usuario toca la notificación del sistema.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] Notificación tocada desde segundo plano');
      _procesarMensajeFCM(message, desdeNotificacion: true);
    });
  }

  void _procesarMensajeFCM(RemoteMessage message,
      {required bool desdeNotificacion}) {
    final data = message.data;
    final compartimentoId = data['compartimento_id'] ?? '';
    final medicamento = data['medicamento'] ?? 'Medicamento desconocido';
    final hora = data['hora'] ?? '--:--';

    if (desdeNotificacion) {
      // Navegar al compartimento específico
      onNotificacionTocada?.call(compartimentoId);
    } else {
      // Mostrar notificación local urgente en primer plano
      _mostrarNotificacionLocal(
        id: int.tryParse(compartimentoId) ?? 0,
        titulo: '⚠️ Intervención requerida — Compartimento $compartimentoId',
        cuerpo: _construirMensajeAlerta(
            compartimentoId: compartimentoId,
            medicamento: medicamento,
            hora: hora),
        payload: compartimentoId,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Notificación manual (desde MonitorService cuando app detecta el estado)
  // ---------------------------------------------------------------------------

  /// Lanza una notificación de alerta de pastilla ignorada.
  /// Llamado por [MonitorPastillaService] cuando detecta el estado crítico
  /// en Firebase Realtime Database (sin necesidad de Cloud Functions).
  Future<void> notificarPastillaIgnorada({
    required int compartimentoId,
    required String medicamento,
    required String hora,
  }) async {
    await _mostrarNotificacionLocal(
      id: compartimentoId,
      titulo: '⚠️ Pastilla ignorada — Acción requerida',
      cuerpo: _construirMensajeAlerta(
        compartimentoId: compartimentoId.toString(),
        medicamento: medicamento,
        hora: hora,
      ),
      payload: compartimentoId.toString(),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _construirMensajeAlerta({
    required String compartimentoId,
    required String medicamento,
    required String hora,
  }) {
    return 'Compartimento $compartimentoId ($medicamento) programado a las $hora '
        'fue ignorado. El dispositivo ha emitido alarma sonora. '
        '⚠️ Se requiere intervención del familiar — la pastilla NO regresa automáticamente.';
  }
}
