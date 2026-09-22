/**
 * DDP106 — Pastillero Inteligente
 * Firmware ESP32 con integración Firebase Realtime Database
 *
 * Librería requerida (instalar en Arduino IDE):
 *   Firebase-ESP-Client by Mobizt
 *   → Arduino IDE → Administrador de librerías → buscar "Firebase ESP Client"
 *
 * Mapeo Firebase ↔ ESP32:
 *   /pastillero/compartimento_N/medicamento          → medic[i].nombre
 *   /pastillero/compartimento_N/hora                 → medic[i].hora
 *   /pastillero/compartimento_N/minutos              → medic[i].minuto
 *   /pastillero/compartimento_N/sensor_ir_activo     → medic[i].agarrado
 *   /pastillero/compartimento_N/pastilla_liberada    → medic[i].dispensadoHoy
 *   /pastillero/compartimento_N/condiciones[0]/pregunta        → medic[i].msg_condi
 *   /pastillero/compartimento_N/condiciones[0]/respuesta_requerida → (siempre true = Sí)
 *   /pastillero/compartimento_N/tiempo_espera_minutos → wait_msg (global)
 *   /pastillero/compartimento_N/accion_por_defecto   → medic[i].dispensar_igual
 *     "dispensarPorImportancia" → dispensar_igual = true
 *     "cancelarDosis"           → dispensar_igual = false
 */

// ─────────────────────────────────────────────────────────────────────────────
// LIBRERÍAS
// ─────────────────────────────────────────────────────────────────────────────
#include <Stepper.h>
#include <ESP32Servo.h>
#include <time.h>
#include <WiFi.h>
#include <sntp.h>
#include <Firebase_ESP_Client.h>
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>

// ─────────────────────────────────────────────────────────────────────────────
// CREDENCIALES WiFi
// ─────────────────────────────────────────────────────────────────────────────
const char* ssid     = "CLARO1_F4DA59";
const char* password = "T1708mPoxS";

// ─────────────────────────────────────────────────────────────────────────────
// CREDENCIALES FIREBASE
// ─────────────────────────────────────────────────────────────────────────────
// Obtener desde: Consola Firebase → Configuración del proyecto → General
#define FIREBASE_API_KEY     "TU-API-KEY-AQUI"

// Obtener desde: Realtime Database → copiar la URL que aparece arriba de los datos
#define FIREBASE_DATABASE_URL "https://pastillero-XXXXX-default-rtdb.firebaseio.com/"

FirebaseData   fbdo;       // Objeto para leer/escribir datos
FirebaseAuth   auth;       // Sin login → se deja vacío (reglas públicas)
FirebaseConfig fbConfig;   // Configuración de Firebase

// ─────────────────────────────────────────────────────────────────────────────
// NTP — Hora de El Salvador (UTC-6, sin horario de verano)
// ─────────────────────────────────────────────────────────────────────────────
const char* ntpServer1        = "pool.ntp.org";
const char* ntpServer2        = "time.nist.gov";
const long  gmtOffset_sec     = -21600;  // UTC-6
const int   daylightOffset_sec = 0;

struct tm tiempoActual;

// ─────────────────────────────────────────────────────────────────────────────
// HARDWARE
// ─────────────────────────────────────────────────────────────────────────────

// Stepper 28BYJ-48 + ULN2003
const int IN1 = 13, IN2 = 12, IN3 = 14, IN4 = 27;
const int pasosPorRevolucion = 2048;
Stepper motor(pasosPorRevolucion, IN1, IN3, IN2, IN4);

// Servo
Servo servo;
const int servoPin = 26;

// Botones físicos (INPUT_PULLUP: LOW = presionado)
const int btnVerde = 33;   // Confirmar / Sí
const int btnRojo  = 25;   // Cancelar / No

// Sensor infrarrojo (HIGH = pastilla detectada/retirada)
const int sensorIR = 32;

// ─────────────────────────────────────────────────────────────────────────────
// MODELO DE DATOS — struct dosis
// Refleja exactamente los campos de Firebase para facilitar la sincronización
// ─────────────────────────────────────────────────────────────────────────────
struct dosis {
  String nombre;          // Firebase: medicamento
  int    hora;            // Firebase: hora   (int 0-23)
  int    minuto;          // Firebase: minutos (int 0-59)
  int    contenedor;      // Compartimento físico (1-7)

  // Estados — se sincronizan con Firebase
  bool dispensadoHoy;     // Firebase: pastilla_liberada
  bool agarrado;          // Firebase: sensor_ir_activo

  // Condición previa (Firebase: condiciones[0])
  bool   hay_condi;       // true si existe al menos una condición
  String msg_condi;       // Texto de la pregunta Sí/No
  int    intentos;        // Máx intentos antes de acción por defecto
  bool   dispensar_igual; // Firebase: accion_por_defecto
                          //   "dispensarPorImportancia" → true
                          //   "cancelarDosis"           → false

  // Variables de control internas (NO se sincronizan con Firebase)
  unsigned long proximaPregunta  = 0;
  int           intentosRealizados = 0;
  bool          esperandoRespuesta = false;
  bool          procesoActivo      = false;
};

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURACIÓN GLOBAL (se lee desde Firebase al iniciar)
// ─────────────────────────────────────────────────────────────────────────────
int  wait_msg        = 1;   // Minutos entre reintentos de condición
int  tiempoRespuesta = 5;   // Minutos para que el paciente responda

// ─────────────────────────────────────────────────────────────────────────────
// ARRAY DE DOSIS — valores por defecto (se sobreescriben con datos de Firebase)
// ─────────────────────────────────────────────────────────────────────────────
dosis medic[7] = {
  // nombre, hora, minuto, contenedor, dispensadoHoy, agarrado,
  // hay_condi, msg_condi, intentos, dispensar_igual
  {"Paracetamol",       8,  0,  1, false, false, true,  "¿Ya desayunaste?",         3, true },
  {"Vitamina D",        9,  30, 2, false, false, false, "",                          0, true },
  {"Ibuprofeno",       14,  58, 3, false, false, true,  "¿Ya comiste?",              2, false},
  {"Omeprazol",        14,  30, 4, false, false, false, "",                          0, true },
  {"Antibiotico",      15,  5,  5, false, false, true,  "¿Tomaste la dosis anterior?", 3, false},
  {"Vitamina B",       18,  30, 6, false, false, false, "",                          0, true },
  {"Medicamento noche", 21, 0,  7, false, false, true,  "¿Ya cenaste?",              2, true }
};

// Flags de control global
bool resetDiarioHecho = false;
bool pruebaHecha      = false;
bool firebaseListo    = false;

// ─────────────────────────────────────────────────────────────────────────────
// PROTOTIPOS
// ─────────────────────────────────────────────────────────────────────────────
void leerConfiguracionFirebase();
void escribirDispensado(int i);
void escribirAgarrado(int i);
void escribirIgnorada(int i);
void dispensar(int i);
void girarMotor(int pasos);
void abrirCompuerta();
void iniciarDosis(int i);
void revisarBtns(int i);
void resp_negativa(int i);
void resetVar(int horaActual, int minutoActual);
void verAgarrado(int i);   // ← FIX: ahora recibe índice como parámetro

// ─────────────────────────────────────────────────────────────────────────────
// SETUP
// ─────────────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);

  // ── WiFi ──
  Serial.print("Conectando a WiFi");
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi conectado! IP: " + WiFi.localIP().toString());

  // ── NTP ──
  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer1, ntpServer2);
  Serial.println("Sincronizando hora NTP...");
  while (!getLocalTime(&tiempoActual)) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\nHora sincronizada: %02d:%02d:%02d\n",
    tiempoActual.tm_hour, tiempoActual.tm_min, tiempoActual.tm_sec);

  // ── Firebase ──
  fbConfig.api_key       = FIREBASE_API_KEY;
  fbConfig.database_url  = FIREBASE_DATABASE_URL;

  // Sin autenticación (reglas públicas en modo prototipo)
  Firebase.signupWithEmailAndPassword(&fbConfig, &auth, "", "");

  fbConfig.token_status_callback = tokenStatusCallback;  // de TokenHelper.h
  Firebase.begin(&fbConfig, &auth);
  Firebase.reconnectWiFi(true);

  // Esperar conexión Firebase (máx 10 segundos)
  unsigned long inicio = millis();
  while (!Firebase.ready() && millis() - inicio < 10000) {
    delay(300);
    Serial.print(".");
  }

  if (Firebase.ready()) {
    firebaseListo = true;
    Serial.println("\nFirebase conectado!");
    leerConfiguracionFirebase();   // ← Cargar config de la app al ESP32
  } else {
    Serial.println("\nFirebase no disponible. Usando valores por defecto.");
  }

  // ── Hardware ──
  motor.setSpeed(5);
  servo.attach(servoPin);
  servo.write(0);
  pinMode(btnVerde, INPUT_PULLUP);
  pinMode(btnRojo,  INPUT_PULLUP);

  Serial.println("Sistema listo.");
}

// ─────────────────────────────────────────────────────────────────────────────
// LOOP
// ─────────────────────────────────────────────────────────────────────────────
void loop() {
  if (!getLocalTime(&tiempoActual)) return;

  int horaActual   = tiempoActual.tm_hour;
  int minutoActual = tiempoActual.tm_min;

  resetVar(horaActual, minutoActual);

  for (int i = 0; i < 7; i++) {

    // ── Verificar sensor IR continuamente ──
    verAgarrado(i);  // FIX: ahora recibe índice i

    // ── Hora exacta de dispensado ──
    if (medic[i].hora           == horaActual  &&
        medic[i].minuto         == minutoActual &&
        !medic[i].dispensadoHoy                &&
        !medic[i].procesoActivo) {
      iniciarDosis(i);
    }

    // ── Reintento de condición (tiempo de espera cumplido) ──
    // FIX: llamar a revisarBtns, no a iniciarDosis, para no repetir el mensaje
    if (medic[i].procesoActivo          &&
        !medic[i].esperandoRespuesta    &&
        millis() >= medic[i].proximaPregunta) {
      medic[i].esperandoRespuesta = true;
      pruebaHecha = false;
      Serial.println("Reintentando pregunta para: " + medic[i].nombre);
      revisarBtns(i);  // FIX: era iniciarDosis(i) — incorrecto
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE — LECTURA (App → ESP32)
// Lee la configuración que el cuidador definió en la app Android
// ─────────────────────────────────────────────────────────────────────────────
void leerConfiguracionFirebase() {
  Serial.println("[Firebase] Leyendo configuración...");

  for (int i = 0; i < 7; i++) {
    String base = "/pastillero/compartimento_" + String(i + 1);

    // Medicamento
    if (Firebase.RTDB.getString(&fbdo, base + "/medicamento")) {
      String med = fbdo.stringData();
      if (med.length() > 0) medic[i].nombre = med;
    }

    // Hora y minutos (int separados → sin problemas de formato)
    if (Firebase.RTDB.getInt(&fbdo, base + "/hora"))
      medic[i].hora = fbdo.intData();

    if (Firebase.RTDB.getInt(&fbdo, base + "/minutos"))
      medic[i].minuto = fbdo.intData();

    // Estado del día (si la app ya marcó como dispensado, el ESP32 no lo repite)
    if (Firebase.RTDB.getBool(&fbdo, base + "/pastilla_liberada"))
      medic[i].dispensadoHoy = fbdo.boolData();

    if (Firebase.RTDB.getBool(&fbdo, base + "/sensor_ir_activo"))
      medic[i].agarrado = fbdo.boolData();

    // Condición previa — se lee sólo la primera (condiciones[0])
    if (Firebase.RTDB.getString(&fbdo, base + "/condiciones/0/pregunta")) {
      String preg = fbdo.stringData();
      if (preg.length() > 0) {
        medic[i].hay_condi = true;
        medic[i].msg_condi = preg;
      } else {
        medic[i].hay_condi = false;
      }
    }

    // Tiempo de espera → se usa el del primer compartimento como global
    // (o se puede hacer por dosis, según preferencia)
    if (i == 0 && Firebase.RTDB.getInt(&fbdo, base + "/tiempo_espera_minutos"))
      wait_msg = fbdo.intData();

    // Acción por defecto
    if (Firebase.RTDB.getString(&fbdo, base + "/accion_por_defecto")) {
      medic[i].dispensar_igual =
        (fbdo.stringData() == "dispensarPorImportancia");
    }

    Serial.printf(
      "[Firebase] Comp %d: %s @ %02d:%02d | cond:%s | disp_igual:%d\n",
      i + 1, medic[i].nombre.c_str(),
      medic[i].hora, medic[i].minuto,
      medic[i].hay_condi ? medic[i].msg_condi.c_str() : "ninguna",
      medic[i].dispensar_igual
    );
  }

  Serial.println("[Firebase] Configuración cargada.");
}

// ─────────────────────────────────────────────────────────────────────────────
// FIREBASE — ESCRITURA (ESP32 → App Android)
// ─────────────────────────────────────────────────────────────────────────────

/// Marca la pastilla como dispensada en Firebase.
/// La app Android detecta el cambio y actualiza la UI en tiempo real.
void escribirDispensado(int i) {
  if (!firebaseListo) return;
  String path = "/pastillero/compartimento_" + String(medic[i].contenedor);

  Firebase.RTDB.setBool(&fbdo, path + "/pastilla_liberada", true);

  // Actualizar fecha del registro
  char fecha[11];
  strftime(fecha, sizeof(fecha), "%Y-%m-%d", &tiempoActual);
  Firebase.RTDB.setString(&fbdo, path + "/fecha_registro", String(fecha));

  Serial.println("[Firebase] pastilla_liberada = true → Compartimento " +
                 String(medic[i].contenedor));
}

/// Marca que el paciente tomó la pastilla (sensor IR la detectó retirada).
/// La app cambia el indicador a VERDE en tiempo real.
void escribirAgarrado(int i) {
  if (!firebaseListo) return;
  String path = "/pastillero/compartimento_" + String(medic[i].contenedor);

  Firebase.RTDB.setBool(&fbdo, path + "/sensor_ir_activo", true);

  Serial.println("[Firebase] sensor_ir_activo = true → Compartimento " +
                 String(medic[i].contenedor));
}

/// Registra en /alertas/ que la pastilla fue ignorada.
/// La Cloud Function detecta el nuevo nodo y envía notificación push al cuidador.
/// La notificación indica que NO hay devolución automática y se requiere
/// intervención del familiar.
void escribirIgnorada(int i) {
  if (!firebaseListo) return;

  char timestamp[20];
  strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M", &tiempoActual);

  char horaStr[6];
  snprintf(horaStr, sizeof(horaStr), "%02d:%02d", medic[i].hora, medic[i].minuto);

  // Escribir bajo /alertas/ con push (genera clave única automáticamente)
  String alertaPath = "/alertas";
  FirebaseJson alertaJson;
  alertaJson.set("compartimento_id",             medic[i].contenedor);
  alertaJson.set("medicamento",                  medic[i].nombre);
  alertaJson.set("hora_programada",              String(horaStr));
  alertaJson.set("minutos_transcurridos",        (int)(wait_msg * medic[i].intentos));
  alertaJson.set("accion_configurada",
    medic[i].dispensar_igual ? "dispensarPorImportancia" : "cancelarDosis");
  alertaJson.set("timestamp",                    String(timestamp));
  alertaJson.set("estado",                       "pastilla_ignorada");
  alertaJson.set("requiere_intervencion",        true);
  alertaJson.set("pastilla_regresa_automaticamente", false);

  if (Firebase.RTDB.pushJSON(&fbdo, alertaPath.c_str(), &alertaJson)) {
    Serial.println("[Firebase] Alerta de pastilla ignorada registrada.");
    Serial.println("           → La app enviará notificación al cuidador.");
  } else {
    Serial.println("[Firebase] Error al registrar alerta: " + fbdo.errorReason());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HARDWARE — DISPENSADO
// ─────────────────────────────────────────────────────────────────────────────

void dispensar(int i) {
  Serial.println("Dispensando: " + medic[i].nombre +
                 " (Compartimento " + String(medic[i].contenedor) + ")");

  int pasos = round((float)medic[i].contenedor * pasosPorRevolucion / 7);
  girarMotor(pasos);
  abrirCompuerta();
  girarMotor(-pasos);

  // Actualizar estado local
  medic[i].dispensadoHoy      = true;
  medic[i].procesoActivo      = false;
  medic[i].esperandoRespuesta = false;

  // Sincronizar con Firebase → App Android actualiza UI
  escribirDispensado(i);
}

void girarMotor(int pasos) {
  motor.step(pasos);
  delay(2000);
}

void abrirCompuerta() {
  servo.write(180);
  delay(2000);
  servo.write(0);
  delay(500);
}

// ─────────────────────────────────────────────────────────────────────────────
// LÓGICA DE DOSIS
// ─────────────────────────────────────────────────────────────────────────────

void iniciarDosis(int i) {
  Serial.println("\n=== Hora de dosis: " + medic[i].nombre + " ===");

  // Sin condición → dispensar directamente
  if (!medic[i].hay_condi) {
    Serial.println("Sin condición. Dispensando...");
    dispensar(i);
    return;
  }

  // Con condición → preguntar al paciente
  medic[i].procesoActivo      = true;
  medic[i].esperandoRespuesta = true;

  Serial.println("Condición: " + medic[i].msg_condi);
  Serial.println("Presiona VERDE (Sí) o ROJO (No)");

  revisarBtns(i);
}

void revisarBtns(int i) {
  Serial.println("Esperando respuesta...");

  unsigned long limiteEspera = millis() + ((unsigned long)tiempoRespuesta * 60000UL);

  while (medic[i].esperandoRespuesta && millis() < limiteEspera) {

    if (digitalRead(btnVerde) == LOW) {
      Serial.println("Respuesta: SÍ → Dispensando");
      delay(300);  // anti-rebote
      dispensar(i);
      return;
    }

    if (digitalRead(btnRojo) == LOW) {
      Serial.println("Respuesta: NO");
      delay(300);  // anti-rebote
      resp_negativa(i);
      return;
    }

    delay(50);  // pequeña pausa para no saturar el CPU
  }

  // Tiempo agotado sin respuesta → tratar como respuesta negativa
  if (medic[i].esperandoRespuesta) {
    Serial.println("Tiempo agotado sin respuesta.");
    resp_negativa(i);
  }
}

void resp_negativa(int i) {
  medic[i].intentosRealizados++;

  Serial.printf("Intento %d de %d\n",
    medic[i].intentosRealizados, medic[i].intentos);

  // Agotó todos los intentos
  if (medic[i].intentosRealizados >= medic[i].intentos) {

    if (medic[i].dispensar_igual) {
      Serial.println("Acción por defecto: Dispensar por importancia.");
      dispensar(i);
    } else {
      Serial.println("Acción por defecto: Cancelar dosis.");
      medic[i].dispensadoHoy      = false;  // No se dispensó
      medic[i].procesoActivo      = false;
      medic[i].esperandoRespuesta = false;

      // Notificar al cuidador que la pastilla fue ignorada
      escribirIgnorada(i);
    }
    return;  // FIX: faltaba ";" en Serial.println original
  }

  // Programar siguiente intento después de wait_msg minutos
  medic[i].proximaPregunta     = millis() + ((unsigned long)wait_msg * 60000UL);
  medic[i].esperandoRespuesta  = false;

  Serial.printf("Próxima pregunta en %d minuto(s).\n", wait_msg);
}

// ─────────────────────────────────────────────────────────────────────────────
// SENSOR IR — Detecta si el paciente retiró la pastilla
// FIX: ahora recibe `int i` como parámetro (antes usaba `i` sin definir)
// ─────────────────────────────────────────────────────────────────────────────
void verAgarrado(int i) {
  // Solo verificar si la pastilla fue dispensada pero aún no detectada
  if (!medic[i].dispensadoHoy || medic[i].agarrado) return;

  if (digitalRead(sensorIR) == HIGH) {
    medic[i].agarrado = true;
    Serial.println("✓ Pastilla retirada: " + medic[i].nombre);

    // Actualizar Firebase → app pone indicador VERDE
    escribirAgarrado(i);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RESET DIARIO — Medianoche (00:00)
// Reinicia variables de control y sincroniza con Firebase
// ─────────────────────────────────────────────────────────────────────────────
void resetVar(int horaActual, int minutoActual) {
  if (horaActual == 0 && minutoActual == 0 && !resetDiarioHecho) {
    Serial.println("=== Reset diario ===");

    for (int i = 0; i < 7; i++) {
      medic[i].dispensadoHoy       = false;
      medic[i].agarrado            = false;
      medic[i].proximaPregunta     = 0;
      medic[i].intentosRealizados  = 0;
      medic[i].esperandoRespuesta  = false;
      medic[i].procesoActivo       = false;
    }

    resetDiarioHecho = true;

    // Recargar configuración actualizada desde la app
    if (firebaseListo) {
      leerConfiguracionFirebase();
    }
  }

  if (horaActual != 0 || minutoActual != 0) {
    resetDiarioHecho = false;
  }
}
