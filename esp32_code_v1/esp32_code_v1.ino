#include <Stepper.h>
#include <ESP32Servo.h>
#include <time.h>
#include <WiFi.h>
#include <sntp.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Arduino.h>
#include "tomarMedicamento.h"
#include "condicion.h"

LiquidCrystal_I2C lcd(0x27, 20, 4);


#define API_KEY "AIzaSyDmLD2-nflUfOczydE4ckOpy-QkG9HD4Uk"
#define DATA_BASE_URL "https://pastillero-18645-default-rtdb.firebaseio.com/"

FirebaseData fdbo;
FirebaseData stream;
FirebaseAuth auth;
FirebaseConfig config;
bool signUpOK=false;

//Conexion a internet
const char* ssid = "CLARO1_F4DA59";
const char* password = "T1708mPoxS";

//Hora servidor
const char* ntpServer1 = "pool.ntp.org";
const char* ntpServer2 = "time.nist.gov";

// Configuracion El Salvador
const long gmtOffset_sec = -21600;
const int daylightOffset_sec = 0;

struct tm tiempoActual;

// 28BYJ-48 + ULN2003 (Stepper aspas)
const int IN1 = 26;
const int IN2 = 33;
const int IN3 = 27;
const int IN4 = 14;
const int pasosPorRevolucion = 2048;
Stepper motor(pasosPorRevolucion, IN1, IN3, IN2, IN4);

//notificacion
//"dispensado", "retirado", "ignorado"

//SERVO
Servo servo;
const int servoPin = 13;

//Botones
const int btnVerde = 35;
const int btnRojo = 32;

//infrarrojo
const int sensorIR = 34;

//pantalla
const int SDA_LCD = 21;
const int SCL_LCD = 22; 

//pam
const int pinAudio = 25;   // DAC del ESP32

//DOSIS
struct dosis {

  //--------Configuracion de usuario---------
  String nombre; 

  //Hora programada
  int hora; 
  int minuto;

  int contenedor; //numero de contenedor en el que esta la pastilla, igual queda en el array(i+1) pero me gusta mas asi

  //condicion para toma
  bool hay_condi; //para verificar si hay o no condicion, si no hay la pastilla solo se dispensa a la hora
  String msg_condi; //mensaje de condicion para antes de tomar la pastilla, ej. ¿Ya desayunaste?
  bool dispensar_igual; //si es true, la pastilla se dispensa aunque la condicion no se cumpla como ultimo recurso
  int intentos; //numero de intentos de confirmacion de condi

  //----------estado de la dosis--------------------
  bool dispensadoHoy;
  bool agarrado; //sensor infrarrojo detecta que la pastilla fue agarrada


  //--------------Variables de control------------------
  unsigned long proximaPregunta; //cuanto para saber cuando hacerla
  int intentosRealizados=0; //usuario respondio NO 
  bool esperandoRespuesta=false; //Estoy revisando si ha respondido los botones
  bool procesoActivo=false; 
  //Control del sensor IR después de dispensar
  bool esperandoRetiro = false;
  unsigned long limiteRetiro = 0;

};

//configuracion general 
  int wait_msg=1; //cuanto tiempo en minutos se va a esperar para volver a preguntar si la persona responde no
  int tiempoRespuesta=5; // minutos que tiene el usuario para responder

  bool resetDiarioHecho = false; //reseteo de las variables de control
  bool pruebaHecha = false;

  bool actualizarMedicamentos = false;

dosis medic[7]; 

void setup() {

  Serial.begin(115200);

  //pedirHoraPrueba();

   // Conectarse al WiFi
  WiFi.begin(ssid, password);
    while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
    Serial.println();
  Serial.println("WiFi conectado!");

  //Obtener hora
    configTime(
    gmtOffset_sec,
    daylightOffset_sec,
    ntpServer1,
    ntpServer2
  );

  // Stepper
  motor.setSpeed(5);

  // Servo
  servo.attach(servoPin);
  servo.write(0);

  //Botones
  pinMode(btnVerde, INPUT_PULLUP);
  pinMode(btnRojo, INPUT_PULLUP);

  //IR
  pinMode(sensorIR, INPUT);

  //pantalla 
  Wire.begin(SDA_LCD, SCL_LCD);

  lcd.init();
  lcd.backlight();

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Pastillero");

  config.api_key = API_KEY;
  config.database_url = DATA_BASE_URL;

  if(Firebase.signUp(&config, &auth, "", "")){
     Serial.println("Conexión a firebase, signUp OK");
     signUpOK = true;
  }else{
    Serial.printf("%s\n", config.signer.signupError.message.c_str());
  }

  config.token_status_callback = tokenStatusCallback;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  if(!Firebase.RTDB.beginStream(&stream, "/pastillero")){
  Serial.println("No se pudo iniciar stream");
  Serial.println(stream.errorReason());
  }

  Firebase.RTDB.setStreamCallback(
    &stream,
    streamCallback,
    streamTimeoutCallback
  );

  

}

void loop(){

  if(actualizarMedicamentos && Firebase.ready()){

    actualizarMedicamentos = false;

    Serial.println("Actualizando medicamentos...");
    cargarTodosMedicamentos();
  }


  if(getLocalTime(&tiempoActual)){

    int horaActual = tiempoActual.tm_hour;
    int minutoActual = tiempoActual.tm_min;

    resetVar(horaActual, minutoActual);

    for(int i = 0; i < 7; i++){

      verAgarrado(i);
      
      if(medic[i].hora == horaActual &&
         medic[i].minuto == minutoActual &&
         medic[i].dispensadoHoy == false &&
         medic[i].procesoActivo == false){
          iniciarDosis(i);
        }
      if(medic[i].procesoActivo == true &&
         medic[i].esperandoRespuesta == false &&
         millis() >= medic[i].proximaPregunta){
          medic[i].esperandoRespuesta=true;
          pruebaHecha = false;
          iniciarDosis(i);
         }
         
    }


  }
}

//FUNCIONES

void dispensar(int i){
  lcd.clear();
  lcd.print("Dispensando");
  Serial.println(medic[i].contenedor);
  int pasos = round((float)medic[i].contenedor*pasosPorRevolucion/7);
  Serial.println(pasos);
  girarMotor(pasos);
  abrirCompuerta();
  girarMotor(-pasos);

  reproducirAudio(audioTomar, audioTomarLongitud);

  medic[i].dispensadoHoy=true;
  medic[i].procesoActivo=false;
  medic[i].esperandoRespuesta=false;
  
  enviarEventoFirebase(i, "dispensado");
  
  // Empieza a esperar que retiren la pastilla
  Serial.println("Estoy esperando que IR detecte");
  esperandoRetiroLCD(i);
  medic[i].agarrado = false;
  medic[i].esperandoRetiro = true;
  medic[i].limiteRetiro = millis() + (5 * 60000UL); // se han puesto 5 minutos de tiempo antes de asumir que no
}

//Gira el stepper para las aspas
void girarMotor(int pasos){
  motor.step(pasos);
  delay(2000);
}

//Abre compuerta de dispensación
void abrirCompuerta(){
  servo.write(180);
  delay(2000);
  servo.write(0);
  delay(500);
}

void iniciarDosis(int i){

  Serial.print("Dosis: ");
  Serial.println(medic[i].nombre);

  if(medic[i].hay_condi == false){
    Serial.println("Esta dosis no tiene condicion. Dispensando...");

    dispensar(i);

    return;
  }

  medic[i].procesoActivo = true;
  medic[i].esperandoRespuesta = true;

  Serial.println("Esta dosis tiene una condicion.");
  Serial.print("Pregunta: ");
  Serial.println(medic[i].msg_condi);
  reproducirAudio(audioCondicion, audioCondicionLongitud);
  revisarBtns(i);


}

void revisarBtns(int i){
  unsigned long inicio = millis();
  Serial.println("Llegue a revisarbtns");
  mostrarCondicion(i);
  while(medic[i].esperandoRespuesta == true && millis() - inicio < tiempoRespuesta * 60000UL) { 
    
    if(digitalRead(btnVerde)==LOW){
      Serial.println("entre al verde");
      dispensar(i);
      delay(300);
      medic[i].esperandoRespuesta = false;
      
      return;
      
    }

    if(digitalRead(btnRojo)==LOW){
      Serial.println("entre al rojo");
      resp_negativa(i);
      
      return;
      
    }
    
  }

  resp_negativa(i);
}

void resp_negativa(int i){
      medic[i].intentosRealizados++;

      if(medic[i].intentosRealizados >= medic[i].intentos){
        if(medic[i].dispensar_igual == true){
          dispensar(i);
          
        }

        medic[i].procesoActivo = false;
        medic[i].esperandoRespuesta = false;

        enviarEventoFirebase(i, "ignorado");
        Serial.println("Ya no voy a dispensar");
        return;
      }

      Serial.print("Intento ");
      Serial.print(medic[i].intentosRealizados);
      Serial.print(" de ");
      Serial.println(medic[i].intentos);

      //Espera
      medic[i].proximaPregunta = millis() + (wait_msg * 60000UL);
      medic[i].esperandoRespuesta = false;

      delay(300);
      return;
}

void resetVar(int horaActual, int minutoActual){

    if (horaActual == 0 && minutoActual == 0 && !resetDiarioHecho) {

      for (int i = 0; i < 7; i++) {

        medic[i].dispensadoHoy = false;
        medic[i].agarrado = false;

        medic[i].proximaPregunta = 0;
        medic[i].intentosRealizados = 0;
        medic[i].esperandoRespuesta = false;
        medic[i].procesoActivo = false;

        medic[i].esperandoRetiro = false;
        medic[i].limiteRetiro = 0;
      }

      resetDiarioHecho = true;
    }

    // Cuando ya pasó la medianoche,
    // dejamos lista la bandera para el próximo día
    if (horaActual != 0 || minutoActual != 0) {
      resetDiarioHecho = false;
    }
}

void verAgarrado(int i){
  
  // Si esta dosis no está esperando retiro, no hacemos nada
  if(medic[i].esperandoRetiro == false){
    return;
  }

  // La pastilla fue retirada
  if(digitalRead(sensorIR) == LOW){

    medic[i].agarrado = true;
    medic[i].esperandoRetiro = false;

    Serial.print("La pastilla fue retirada: ");
    Serial.println(medic[i].nombre);

    enviarEventoFirebase(i, "retirado");
    lcd.clear();
    return;
  }

  // Pasaron los 5 minutos y nunca se detectó el retiro
  if(millis() >= medic[i].limiteRetiro){

    medic[i].agarrado = false;
    medic[i].esperandoRetiro = false;

    Serial.print("NO se retiro la pastilla: ");
    Serial.println(medic[i].nombre);

      enviarEventoFirebase(i, "ignorado");

    return;
  }

}

void pedirHoraPrueba() {

  Serial.println("Ingrese la hora para medic[0] (0-23):");

  while (Serial.available() == 0) {
    // Esperar a que el usuario escriba
  }

  medic[0].hora = Serial.parseInt();

  // Limpiar lo que quede en el buffer
  while (Serial.available() > 0) {
    Serial.read();
  }


  Serial.println("Ingrese los minutos para medic[0] (0-59):");

  while (Serial.available() == 0) {
    // Esperar a que el usuario escriba
  }

  medic[0].minuto = Serial.parseInt();

  while (Serial.available() > 0) {
    Serial.read();
  }


  Serial.println("Hora configurada para medic[0]:");

  Serial.print(medic[0].hora);
  Serial.print(":");

  if (medic[0].minuto < 10) {
    Serial.print("0");
  }

  Serial.println(medic[0].minuto);
}

void cargarTodosMedicamentos(){
  for(int i=0; i<7; i++){
    cargarmedicamento(i);
  }
}

void cargarmedicamento(int i){

    
    String ruta = "/pastillero/compartimento_" + String(i+1);

  if(Firebase.RTDB.getJSON(&fdbo, ruta)){

    FirebaseJson &json = fdbo.jsonObject();

    FirebaseJsonData dato;

    // NOMBRE
    json.get(dato, "medicamento");
    if(dato.success){
      medic[i].nombre = dato.stringValue;
    }

    // HORA
    json.get(dato, "hora");
    if(dato.success){
      medic[i].hora = dato.intValue;
    }

    // MINUTO
    json.get(dato, "minutos");
    if(dato.success){
      medic[i].minuto = dato.intValue;
    }

    // CONTENEDOR
    json.get(dato, "compartimento_id");
    if(dato.success){
      medic[i].contenedor = dato.intValue;
    }

    // HAY CONDICION
    json.get(dato, "hay_condicion");
    if(dato.success){
      medic[i].hay_condi = dato.boolValue;
    }

    // MENSAJE CONDICION
    json.get(dato, "msg_condicion");
    if(dato.success){
      medic[i].msg_condi = dato.stringValue;
    }

    // DISPENSAR IGUAL
    json.get(dato, "liberar_por_emergencia");
    if(dato.success){
      medic[i].dispensar_igual = dato.boolValue;
    }

    // INTENTOS
    json.get(dato, "intentos");
    if(dato.success){
      medic[i].intentos = dato.intValue;
    }


    Serial.print("Medicamento ");
    Serial.print(i);
    Serial.println(" cargado correctamente");

  }else{

    Serial.print("Error leyendo medicamento ");
    Serial.println(i);

    Serial.println(fdbo.errorReason());
  }
}

void streamCallback(FirebaseStream data){

  String ruta = data.dataPath();

  Serial.println("Hubo un cambio en Firebase");
  Serial.print("Ruta: ");
  Serial.println(ruta);

  // "/" = datos iniciales completos del stream
  // "/compartimento_X/..." = cambio en configuración
  if(ruta == "/" || ruta.startsWith("/compartimento_")){
    actualizarMedicamentos = true;
  }
}

void streamTimeoutCallback(bool timeout){

  if(timeout){
    Serial.println("Stream timeout");
  }
}

void enviarEventoFirebase(int i, String tipo){

  FirebaseJson json;

  json.set("tipo", tipo);
  json.set("medicamento", medic[i].nombre);
  json.set("compartimiento", medic[i].contenedor);

  if(Firebase.RTDB.setJSON(
      &fdbo,
      "/pastillero/eventos/ultimo_evento",
      &json
  )){
    Serial.println("Evento enviado");
  }else{
    Serial.println(fdbo.errorReason());
  }

  return;
}

void mostrarCondicion(int i) {

  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print(medic[i].nombre);

  lcd.setCursor(0, 1);
  lcd.print(medic[i].msg_condi);

  lcd.setCursor(0, 3);
  lcd.print("SI: Verde  NO: Rojo");

  return;
}

void esperandoRetiroLCD(int i){

  lcd.clear();

  lcd.setCursor(0, 0);
  lcd.print(medic[i].nombre);

  lcd.setCursor(0, 1);
  lcd.print("TU PASTILLA FUE");

  lcd.setCursor(0, 2);
  lcd.print("DISPENSADA!");

  lcd.setCursor(0, 3);
  lcd.print("PUEDES TOMARLA");

  return;

}

void reproducirAudio(const uint8_t* audio, unsigned int longitud) {

  float volumen = 0.35; // 50%
  for (unsigned int i = 0; i < longitud; i++) {
    uint8_t muestra = pgm_read_byte(&audio[i]);

    int salida = 128 + (muestra - 128) * volumen;

    dacWrite(pinAudio, salida);
    delayMicroseconds(125);   // 8000 Hz = 125 us por muestra
  }

  // dejar el DAC en punto medio al terminar
  dacWrite(pinAudio, 128);
}




