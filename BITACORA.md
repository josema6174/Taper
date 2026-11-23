# Bitácora de desarrollo — TAPER (grabador de 4 pistas)

Registro cronológico de las decisiones y cambios hechos en esta sesión (21–23 de noviembre de 2026).

> **Nota:** el entorno de trabajo no tenía Xcode instalado, por lo que ningún cambio se compiló ni probó desde aquí. Todo se verificó compilando y probando en el equipo del usuario.

---

## Archivos tocados

| Archivo | Rol |
|---|---|
| `Models/Track.swift` | Modelo de pista (EQ, reverb, solo) |
| `Models/TapeProject.swift` | Modelo de proyecto |
| `AudioEngine/AudioManager.swift` | Grafo de audio, DSP, transporte, exportación |
| `Views/ContentView.swift` | UI: strips, ventana FX, knob |

---

## 1. EQ por pista + Reverb master (21/11)

**Pedido:** EQ de 3 bandas por pista (`AVAudioUnitEQ`) y un reverb global (`AVAudioUnitReverb`), con persistencia y soporte en el mixdown offline.

**Modelo**
- `Track`: `eqLow`, `eqMid`, `eqHigh` (dB, −12…12, default 0).
- `TapeProject`: `masterReverbMix` (0…100).
- `init(from:)` personalizado con `decodeIfPresent` para que los `tapes.json` viejos carguen sin error. En `Track` se puso en una extensión para conservar el `Track(id:name:)`.

**Audio**
- 4 `eqNodes` con bandas: Low = lowShelf 100 Hz, Mid = parametric 1 kHz (bandwidth 1.0), High = highShelf 8 kHz.
- Cadena inicial: `Player → EQ → MainMixer → Reverb → Output`.
- Funciones: `setEQ`, `resetEQ`, `setMasterReverb`; `applyMixState()` vuelca el estado del modelo a los nodos (se llama en `loadTape`, `createNewTape`, `setupAudioGraph` y antes del render offline).
- Exportación: cola extra de 3 s si hay reverb, para que no se corte el decaimiento.

**UI:** botón "EQ" por strip con cajón inline y slider de reverb master sobre el transporte.

> Decisión: la app usa strips verticales, no filas, así que el cajón se adaptó a un único panel bajo los strips.

---

## 2. Bug: sin grabación, sin VU, sin monitoreo (21/11)

**Síntoma:** tras el cambio anterior, la app no grababa, los VU no se movían y el monitoreo no sonaba.

**Causa probable:** la conexión `mainMixerNode → reverbNode` se hizo con un formato que podía no coincidir con el del hardware de salida (ej. 44.1 vs 48 kHz). Los efectos no convierten sample rate, así que `engine.start()` fallaba y todo quedaba mudo.

**Corrección:** conectar el bus master con el formato de `engine.outputNode.outputFormat(forBus: 0)` (con respaldo 44.1 kHz estéreo).

**Descartado:** el permiso de micrófono (`NSMicrophoneUsageDescription`) sí estaba configurado en el proyecto.

---

## 3. UX: EQ en ventana a pantalla completa con doble tap (23/11)

**Pedido:** eliminar el botón EQ; abrir el menú con doble tap sobre la pista, en una ventana de pantalla completa pensada para crecer como menú de efectos.

**Implementación**
- `fullScreenCover` con la vista `TrackFXView` (título "TRACK FX", botón ✕, sección de EQ con RESET).
- El doble tap solo está en la parte superior del strip (nombre + VU + porcentaje). El fader usa un drag con `minimumDistance: 0` y los botones ARM/M/S se activarían dos veces, por eso no se aplicó a todo el strip.

---

## 4. Reverb individual por pista (23/11)

**Pedido:** reemplazar el reverb master por un reverb por pista.

**Cambios**
- `Track.reverbMix` (0…100) persistido, con `decodeIfPresent`.
- Se eliminó `masterReverbMix` de `TapeProject` y del `AudioManager`.
- Nueva cadena por pista: `Player → EQ → Reverb → MainMixer → Output`.
- Nuevas funciones: `setReverb(for:mix:)` y `resetFX(for:)` (reinicia EQ y reverb).
- `mainMixerNode → outputNode` se reconecta explícitamente con el formato del hardware.
- Etiqueta blanca "FX" en el encabezado del strip cuando hay EQ o reverb ≠ 0 (reemplaza el botón eliminado).

> Decisión: se mantuvo la ventana fullscreen con doble tap (última decisión de UX) en lugar del botón "FX" + cajón inline que mencionaba el nuevo pedido.

---

## 5. Botón S (Solo) funcional (23/11)

- `Track.isSoloed` (efímero, no se persiste).
- `effectiveVolume(i)`: 0 si la pista está muteada, o si hay algún solo y la pista no es solo; si no, `volume`.
- `toggleSolo(for:)` y `applyTrackVolumes()`; se permiten varios solos a la vez.
- Todos los puntos donde se asignaba el volumen del player (play, overdub, export, load/create, fader, mute, VU) ahora usan `effectiveVolume`.
- Efecto colateral: el mixdown respeta el solo activo en el momento de exportar.

---

## 6. STOP durante la reproducción (23/11)

**Síntoma:** el botón STOP solo se habilitaba al grabar.

**Causa:** `scheduleFile` usaba el completion handler por defecto, que puede dispararse cuando el audio ya se entregó al motor (no cuando terminó de sonar). Eso ponía `isMasterPlaying = false` mientras aún sonaba.

**Corrección**
- `completionCallbackType: .dataPlayedBack` en los dos `scheduleFile` de transporte.
- STOP también se habilita si alguna pista tiene `isPlaying == true`.

**Error de compilación derivado:** la primera edición dejó `{ _ in [weak self] in`; se corrigió a `{ [weak self] _ in`.

---

## 7. Consulta: el EQ se siente muy leve (23/11)

Solo diagnóstico, sin cambios de código. Causas probables:
- Shelves en 100 Hz y 8 kHz: el micrófono del teléfono tiene poca energía en esos extremos.
- Parametric de 1 kHz con bandwidth de 1 octava: poco selectivo.
- Altavoz del iPhone sin graves; procesamiento del micrófono (AGC, reducción de ruido).
- Cambios de tono son menos perceptibles que cambios de volumen.

Ajustes posibles si se quiere más efecto: bandwidth más estrecho en MID, mover LOW a 150–200 Hz y HIGH a 4–5 kHz, o ampliar el rango a ±18/±24 dB.

---

## 8. Potenciómetro circular para el reverb (23/11)

- Nuevo componente reutilizable `KnobView(value: Binding<Double>, range:)`.
- Arco de 270° (riel gris + arco blanco), cuerpo circular e indicador rotatorio.
- Gesto: arrastre vertical (150 pt = recorrido completo); doble tap = reset al mínimo.
- Reemplaza el slider REV en `TrackFXView`, con lectura de porcentaje debajo.

---

## Pendientes / ideas

- [ ] Compilar y probar todo en dispositivo real (micrófono y monitoreo en simulador son poco fiables).
- [ ] Confirmar que el STOP funciona en reproducción tras el cambio de `.dataPlayedBack`.
- [ ] Decidir si el EQ también pasa a knobs.
- [ ] Ajustar frecuencias/bandwidth del EQ si se quiere un efecto más marcado.
- [ ] Guardar `tapes.json` solo al soltar el slider (hoy se guarda en cada movimiento).
- [ ] Persistir o no el estado de Solo entre sesiones (hoy no).
- [ ] Indicador visual de EQ/FX más detallado en el strip, si se desea.

