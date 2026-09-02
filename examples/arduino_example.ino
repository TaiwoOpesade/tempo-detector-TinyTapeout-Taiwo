/*
 * Hardware Audio Tempo Detector - Arduino/RP2040 integration example
 * -------------------------------------------------------------------
 * Reads an electret microphone through the ADC, reduces it to an
 * amplitude envelope at ~100 Hz, and drives it into the TinyTapeout
 * chip's ui_in/uio_in pins. Reads back bpm_estimate and tempo_locked
 * and prints them over Serial.
 *
 * Wiring (adjust pin numbers for your board):
 *   ui_in[7:0]   -> AUDIO_PIN[0..7]   (8 GPIO pins, sample value)
 *   uio_in[0]    -> SAMPLE_VALID_PIN
 *   uio_in[1]    -> FRAME_RESET_PIN
 *   uo_out[7:0]  -> BPM_PIN[0..7]     (8 GPIO pins, read as input)
 *   uio_out[2]   -> BEAT_PULSE_PIN    (input)
 *   uio_out[3]   -> TEMPO_LOCKED_PIN  (input)
 *   uio_out[7:6] -> CONFIDENCE_PIN[0..1] (input)
 */

const int MIC_ADC_PIN = A0;

const int AUDIO_PIN[8]   = {2, 3, 4, 5, 6, 7, 8, 9};
const int SAMPLE_VALID_PIN = 10;
const int FRAME_RESET_PIN  = 11;

const int BPM_PIN[8]        = {22, 23, 24, 25, 26, 27, 28, 29};
const int BEAT_PULSE_PIN    = 30;
const int TEMPO_LOCKED_PIN  = 31;
const int CONFIDENCE_PIN[2] = {32, 33};

const unsigned long SAMPLE_INTERVAL_US = 10000;  // 100 Hz, matches
                                                  // NUMERATOR=6000 in
                                                  // the chip's divider

int envelope = 0;
unsigned long lastSampleTime = 0;

void setup() {
  Serial.begin(115200);

  for (int i = 0; i < 8; i++) {
    pinMode(AUDIO_PIN[i], OUTPUT);
    pinMode(BPM_PIN[i], INPUT);
  }
  pinMode(SAMPLE_VALID_PIN, OUTPUT);
  pinMode(FRAME_RESET_PIN, OUTPUT);
  pinMode(BEAT_PULSE_PIN, INPUT);
  pinMode(TEMPO_LOCKED_PIN, INPUT);
  pinMode(CONFIDENCE_PIN[0], INPUT);
  pinMode(CONFIDENCE_PIN[1], INPUT);

  digitalWrite(SAMPLE_VALID_PIN, LOW);
  digitalWrite(FRAME_RESET_PIN, LOW);

  // Pulse frame_reset once at startup so we don't inherit stale state.
  digitalWrite(FRAME_RESET_PIN, HIGH);
  delayMicroseconds(20);
  digitalWrite(FRAME_RESET_PIN, LOW);
}

// Very simple rectify + peak-decay envelope follower on the host side.
int updateEnvelope(int rawAdc) {
  static int peak = 0;
  int centered = abs(rawAdc - 512);      // assumes 10-bit ADC, 0-1023
  int scaled = constrain(centered / 2, 0, 255);

  if (scaled > peak) {
    peak = scaled;                        // attack: track instantly
  } else {
    peak = (peak * 15) / 16;              // decay: same 1/16 time
                                           // constant as the chip's
                                           // own envelope, for
                                           // consistent dynamics
  }
  return peak;
}

void writeAudioSample(uint8_t value) {
  for (int i = 0; i < 8; i++) {
    digitalWrite(AUDIO_PIN[i], (value >> i) & 0x01);
  }
}

void pulseSampleValid() {
  digitalWrite(SAMPLE_VALID_PIN, HIGH);
  delayMicroseconds(2);   // hold comfortably longer than one chip clock
  digitalWrite(SAMPLE_VALID_PIN, LOW);
}

uint8_t readBpmEstimate() {
  uint8_t value = 0;
  for (int i = 0; i < 8; i++) {
    if (digitalRead(BPM_PIN[i])) value |= (1 << i);
  }
  return value;
}

uint8_t readConfidence() {
  uint8_t value = 0;
  if (digitalRead(CONFIDENCE_PIN[0])) value |= 0x01;
  if (digitalRead(CONFIDENCE_PIN[1])) value |= 0x02;
  return value;
}

void loop() {
  unsigned long now = micros();
  if (now - lastSampleTime < SAMPLE_INTERVAL_US) {
    return;
  }
  lastSampleTime = now;

  int rawAdc = analogRead(MIC_ADC_PIN);
  envelope = updateEnvelope(rawAdc);

  writeAudioSample((uint8_t)envelope);
  pulseSampleValid();

  bool locked = digitalRead(TEMPO_LOCKED_PIN);
  if (locked) {
    uint8_t bpm = readBpmEstimate();
    uint8_t confidence = readConfidence();
    Serial.print("BPM: ");
    Serial.print(bpm);
    Serial.print("  confidence: ");
    Serial.println(confidence);
  } else {
    Serial.println("locking...");
  }
}
