/**
 * Cloud Function de Firebase — DDP106 Pastillero
 *
 * Esta función se dispara automáticamente cuando el ESP32 escribe un nuevo
 * evento en el nodo /alertas/ de Firebase Realtime Database.
 *
 * Flujo completo:
 *   ESP32 detecta pastilla ignorada
 *     → escribe en /pastillero/compartimento_N/pastilla_liberada = true
 *     → MonitorPastillaService (app Flutter) detecta el estado
 *     → escribe en /alertas/{push} el evento
 *     → ESTA FUNCIÓN se dispara
 *     → Lee el token FCM del cuidador desde /config/fcm_token_cuidador
 *     → Envía notificación push al dispositivo del cuidador
 *
 * INSTALACIÓN:
 *   1. Instalar Firebase CLI: npm install -g firebase-tools
 *   2. firebase login
 *   3. firebase init functions  (en la carpeta raíz del proyecto)
 *   4. Copiar este archivo a functions/index.js
 *   5. firebase deploy --only functions
 *
 * REQUISITO: Plan Firebase Blaze (pago por uso) para usar Cloud Functions.
 * El plan Spark (gratuito) NO admite Cloud Functions.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Se dispara cuando se crea un nuevo documento en /alertas/
 * (escrito por MonitorPastillaService cuando detecta pastilla ignorada).
 */
exports.notificarCuidador = functions.database
  .ref("/alertas/{alertaId}")
  .onCreate(async (snapshot, context) => {
    const alerta = snapshot.val();

    // Solo procesar alertas de pastilla ignorada
    if (alerta.estado !== "pastilla_ignorada") return null;

    // Leer el token FCM del cuidador registrado en la app
    const tokenSnapshot = await admin
      .database()
      .ref("/config/fcm_token_cuidador/token")
      .get();

    const tokenCuidador = tokenSnapshot.val();
    if (!tokenCuidador) {
      console.error("[FCM] No hay token de cuidador registrado.");
      return null;
    }

    // Construir el mensaje FCM
    const mensaje = {
      token: tokenCuidador,
      notification: {
        title: `⚠️ Pastilla ignorada — Compartimento ${alerta.compartimento_id}`,
        body:
          `${alerta.medicamento} (${alerta.hora_programada}) fue ignorada. ` +
          `Hace ${alerta.minutos_transcurridos} minutos. ` +
          `⚠️ La pastilla NO regresa automáticamente. Intervención requerida.`,
      },
      data: {
        compartimento_id: String(alerta.compartimento_id),
        medicamento: alerta.medicamento,
        hora: alerta.hora_programada,
        tipo: "pastilla_ignorada",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "pastillero_alertas",
          priority: "max",
          defaultSound: true,
          defaultVibrateTimings: true,
          color: "#FF0000",
          icon: "ic_launcher",
          // Título grande expandible
          bodyLocKey: "pastilla_ignorada",
        },
      },
    };

    try {
      const response = await admin.messaging().send(mensaje);
      console.log(`[FCM] Notificación enviada: ${response}`);

      // Marcar la alerta como notificada en Firebase
      await snapshot.ref.update({ notificado: true, fcm_response: response });

      return response;
    } catch (error) {
      console.error("[FCM] Error enviando notificación:", error);
      return null;
    }
  });

/**
 * Limpieza automática de alertas antiguas (cron — cada día a medianoche).
 * Mantiene la base de datos limpia eliminando alertas de más de 7 días.
 */
exports.limpiarAlertasAntiguas = functions.pubsub
  .schedule("0 0 * * *")
  .timeZone("America/Guatemala")
  .onRun(async (_context) => {
    const hace7Dias = Date.now() - 7 * 24 * 60 * 60 * 1000;
    const alertasRef = admin.database().ref("/alertas");

    const snapshot = await alertasRef
      .orderByChild("timestamp")
      .endAt(new Date(hace7Dias).toISOString())
      .get();

    if (!snapshot.exists()) return null;

    const eliminar = {};
    snapshot.forEach((child) => {
      eliminar[child.key] = null;
    });

    await alertasRef.update(eliminar);
    console.log(
      `[Limpieza] ${Object.keys(eliminar).length} alertas antiguas eliminadas.`
    );
    return null;
  });
