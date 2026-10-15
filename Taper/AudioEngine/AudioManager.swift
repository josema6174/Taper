//
//  AudioManager.swift
//  Taper
//
//  Created by Jose maria Martinez marconi on 21/08/2026.
//

import Foundation
import AVFoundation
import Accelerate
import Combine

/// Número total de pistas del grabador.
private let trackCount = 4

class AudioManager: ObservableObject {
    
    // MARK: - Audio Engine
    
    /// Motor principal de audio.
    let engine = AVAudioEngine()
    
    /// Un playerNode por pista — todos conectados al mainMixerNode.
    /// Permite reproducción simultánea de múltiples pistas.
    let playerNodes: [AVAudioPlayerNode] = (0..<trackCount).map { _ in AVAudioPlayerNode() }
    
    /// Nodo mixer dedicado para monitorear en tiempo real la señal del micrófono hacia los auriculares.
    let monitorMixerNode = AVAudioMixerNode()
    
    // MARK: - Published State
    
    /// Estado del engine (hardware de audio activo o inactivo).
    @Published var isRunning: Bool = false
    
    /// Array de 4 Tracks con su estado individual.
    /// La UI observa este array para reflejar arm, grabación, reproducción y disponibilidad.
    @Published var tracks: [Track] = (0..<trackCount).map { i in
        Track(id: i, name: "T\(i + 1)")
    }
    
    /// `true` cuando el Master Transport está en modo reproducción.
    @Published var isMasterPlaying: Bool = false
    
    /// `true` cuando el Master Transport está en modo grabación/overdub.
    @Published var isMasterRecording: Bool = false
    
    /// `true` cuando el monitoreo de entrada (Input Monitoring) está activo.
    @Published var isMonitoringEnabled: Bool = false
    
    /// `true` cuando se intenta activar el monitoreo sin auriculares conectados (alerta al usuario).
    @Published var showMonitoringWarning: Bool = false
    
    /// Calcula la latencia total de ida y vuelta (RTL) del hardware de audio.
    /// Suma latencia de entrada, salida y duración del buffer I/O. Si el cálculo da 0, se usa un fallback de 15 ms.
    var roundTripLatencySeconds: TimeInterval {
        let session = AVAudioSession.sharedInstance()
        let total = session.inputLatency + session.outputLatency + session.ioBufferDuration
        return total > 0 ? total : 0.015
    }
    
    // MARK: - Headphone & Route Detection
    
    /// Indica si hay auriculares conectados (cable o Bluetooth).
    /// El monitoreo en tiempo real requiere auriculares para prevenir acople acústico (feedback).
    var areHeadphonesConnected: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { port in
            port.portType == .headphones ||
            port.portType == .bluetoothA2DP ||
            port.portType == .bluetoothHFP ||
            port.portType == .bluetoothLE
        }
    }
    
    // MARK: - Private State
    
    /// Handle del archivo WAV donde se escriben los buffers del micrófono.
    private var audioFile: AVAudioFile?
    
    /// Índice de la pista que está grabando actualmente, o nil si ninguna.
    private var recordingTrackIndex: Int? = nil
    
    // MARK: - Init & Deinit
    
    init() {
        setupAudioSession()
        setupAudioGraph()
        setupRouteChangeObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Audio Graph
    
    /// Configura el grafo de audio:
    /// - Inicializa el inputNode (micrófono) sin conectarlo al mixer (evita acople).
    /// - Adjunta y conecta los 4 playerNodes al mainMixerNode.
    private func setupAudioGraph() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // 1. Monitoreo de entrada: conectar micrófono a través de monitorMixerNode
        // Silenciado por defecto (0.0) para prevenir acople accidental por altavoces.
        engine.attach(monitorMixerNode)
        engine.connect(inputNode, to: monitorMixerNode, format: inputFormat)
        engine.connect(monitorMixerNode, to: engine.mainMixerNode, format: inputFormat)
        monitorMixerNode.outputVolume = 0.0
        print("Nodo monitorMixerNode adjuntado y conectado al mainMixerNode (volumen: 0.0).")
        
        // 2. Adjuntar y conectar los 4 playerNodes al mainMixerNode
        for (index, player) in playerNodes.enumerated() {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: inputFormat)
            player.volume = tracks[index].isMuted ? 0.0 : tracks[index].volume
            print("PlayerNode[\(index)] adjuntado y conectado al mixer.")
        }
        
        print("Grafo configurado: \(trackCount) pistas + monitorMixer conectados al mixer.")
    }
    
    // MARK: - Engine Control
    
    /// Arranca o detiene el engine. Si hay transporte activo, se detiene primero.
    func toggleEngine() {
        if engine.isRunning {
            stopMasterTransport()
            engine.stop()
            isRunning = false
            print("Engine detenido.")
        } else {
            do {
                try engine.start()
                isRunning = true
                print("Engine arrancado correctamente.")
            } catch {
                isRunning = false
                print("Error al arrancar el engine: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Track Arming
    
    /// Arma o desarma la pista indicada.
    ///
    /// Reglas:
    /// - No se puede cambiar el estado de arm mientras se está grabando.
    /// - Solo una pista puede estar armada a la vez (exclusividad de micrófono).
    ///   Armar una pista desarma automáticamente cualquier otra que estuviera armada.
    /// - Parameter trackIndex: Índice de la pista (0-3).
    func toggleArm(for trackIndex: Int) {
        guard (0..<trackCount).contains(trackIndex) else { return }
        guard !isMasterRecording else {
            print("No se puede cambiar el arm mientras se está grabando.")
            return
        }
        
        let wasArmed = tracks[trackIndex].isArmed
        
        // Desarmar todas las pistas (exclusividad)
        for i in 0..<trackCount {
            tracks[i].isArmed = false
        }
        
        // Si la pista no estaba armada, la armamos. Si ya estaba, queda desarmada.
        if !wasArmed {
            tracks[trackIndex].isArmed = true
            print("Pista \(trackIndex + 1) armada.")
        } else {
            print("Pista \(trackIndex + 1) desarmada.")
        }
    }
    
    // MARK: - Master Transport
    
    /// Inicia la reproducción sincronizada de todas las pistas con audio.
    ///
    /// Todas las pistas con `hasAudio == true` arrancan en el mismo instante
    /// usando un `AVAudioTime` común calculado ligeramente en el futuro,
    /// garantizando sincronía sample-accurate.
    func startMasterPlay() {
        guard engine.isRunning else {
            print("Error: El engine no está corriendo.")
            return
        }
        
        // Detener cualquier transporte activo antes de arrancar
        stopMasterTransport()
        
        // Calcular tiempo de inicio común compensando la latencia de hardware (RTL)
        let startTime = makeStartTime(offsetSeconds: roundTripLatencySeconds)
        
        var playingAny = false
        
        for i in 0..<trackCount {
            guard tracks[i].hasAudio else { continue }
            guard let fileURL = tracks[i].fileURL else { continue }
            
            let player = playerNodes[i]
            
            do {
                let file = try AVAudioFile(forReading: fileURL)
                
                player.stop()
                player.removeTap(onBus: 0)
                
                // Instalar tap de medición pre-reproducción
                installMeterTap(on: player, trackIndex: i)
                
                // Agendar archivo con inicio sincronizado
                player.scheduleFile(file, at: nil) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if self.tracks[i].isPlaying {
                            self.playerNodes[i].removeTap(onBus: 0)
                            self.tracks[i].isPlaying = false
                            self.tracks[i].meterLevel = 0.0
                            print("Reproducción de pista \(i + 1) finalizada.")
                            // Si todas las pistas terminaron, apagamos el master play
                            if !self.tracks.contains(where: { $0.isPlaying }) {
                                self.isMasterPlaying = false
                            }
                        }
                    }
                }
                
                player.volume = tracks[i].isMuted ? 0.0 : tracks[i].volume
                player.prepare(withFrameCount: 8192)
                player.play(at: startTime)
                tracks[i].isPlaying = true
                playingAny = true
                print("Pista \(i + 1) agendada para reproducción sincronizada.")
                
            } catch {
                print("Error al cargar pista \(i + 1): \(error.localizedDescription)")
            }
        }
        
        if playingAny {
            isMasterPlaying = true
            print("Master Play iniciado.")
        } else {
            print("No hay pistas con audio para reproducir.")
        }
    }
    
    /// Inicia la grabación en la pista armada y reproduce simultáneamente
    /// las demás pistas con audio (overdub / punch-in estilo Portastudio).
    ///
    /// Requiere que el engine esté corriendo y que haya exactamente una pista armada.
    func startMasterRecord() {
        guard engine.isRunning else {
            print("Error: El engine no está corriendo.")
            return
        }
        guard let armedIndex = tracks.firstIndex(where: { $0.isArmed }) else {
            print("Error: No hay ninguna pista armada.")
            return
        }
        
        // Detener cualquier transporte activo antes de arrancar
        stopMasterTransport()
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Preparar archivo WAV de destino
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = documentsURL.appendingPathComponent("Track\(armedIndex + 1)_\(timestamp).wav")
        
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
            print("Archivo de grabación creado: \(fileURL.lastPathComponent)")
        } catch {
            print("Error al crear archivo de grabación: \(error.localizedDescription)")
            return
        }
        
        tracks[armedIndex].fileURL = fileURL
        
        // Instalar tap de captura + medición en el input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                print("Error al escribir buffer: \(error.localizedDescription)")
            }
            let level = self.calculateNormalizedLevel(from: buffer)
            DispatchQueue.main.async {
                self.tracks[armedIndex].meterLevel = level
            }
        }
        
        tracks[armedIndex].isRecording = true
        recordingTrackIndex = armedIndex
        isMasterRecording = true
        
        // Calcular tiempo de inicio sincronizado compensando la latencia de hardware (RTL)
        let startTime = makeStartTime(offsetSeconds: roundTripLatencySeconds)
        
        // Reproducir simultáneamente las pistas que tienen audio (excepto la que graba)
        var playingAny = false
        for i in 0..<trackCount {
            guard i != armedIndex, tracks[i].hasAudio else { continue }
            guard let fileURL = tracks[i].fileURL else { continue }
            
            let player = playerNodes[i]
            
            do {
                let file = try AVAudioFile(forReading: fileURL)
                
                player.stop()
                player.removeTap(onBus: 0)
                installMeterTap(on: player, trackIndex: i)
                
                player.scheduleFile(file, at: nil) { [weak self] in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if self.tracks[i].isPlaying {
                            self.playerNodes[i].removeTap(onBus: 0)
                            self.tracks[i].isPlaying = false
                            self.tracks[i].meterLevel = 0.0
                            print("Reproducción de pista \(i + 1) finalizada (overdub).")
                        }
                    }
                }
                
                player.volume = tracks[i].isMuted ? 0.0 : tracks[i].volume
                player.prepare(withFrameCount: 8192)
                player.play(at: startTime)
                tracks[i].isPlaying = true
                playingAny = true
                print("Pista \(i + 1) reproduciendo durante overdub.")
                
            } catch {
                print("Error al cargar pista \(i + 1) para overdub: \(error.localizedDescription)")
            }
        }
        
        if playingAny {
            isMasterPlaying = true
        }
        
        print("Master Record iniciado en pista \(armedIndex + 1).")
    }
    
    /// Detiene completamente el transporte: grabación, reproducción, taps y meters.
    func stopMasterTransport() {
        // 1. Detener grabación activa
        if let recIdx = recordingTrackIndex {
            engine.inputNode.removeTap(onBus: 0)
            audioFile = nil
            tracks[recIdx].isRecording = false
            tracks[recIdx].meterLevel = 0.0
            recordingTrackIndex = nil
            print("Grabación detenida en pista \(recIdx + 1).")
        }
        
        // 2. Detener todos los players y remover sus taps
        for i in 0..<trackCount {
            let player = playerNodes[i]
            player.removeTap(onBus: 0)
            player.stop()
            tracks[i].isPlaying = false
            tracks[i].meterLevel = 0.0
        }
        
        isMasterPlaying = false
        isMasterRecording = false
        print("Master Transport detenido.")
    }
    
    // MARK: - Volume & Mute
    
    /// Actualiza el volumen de la pista indicada y lo aplica al nodo de reproducción.
    ///
    /// Si la pista está muteada, el nodo mantiene su volumen en 0.0 hasta que se desmutee.
    /// - Parameters:
    ///   - trackIndex: Índice de la pista (0-3).
    ///   - volume: Nuevo valor de volumen (0.0 – 1.0).
    func setVolume(for trackIndex: Int, volume: Float) {
        guard (0..<trackCount).contains(trackIndex) else { return }
        tracks[trackIndex].volume = volume
        if !tracks[trackIndex].isMuted {
            playerNodes[trackIndex].volume = volume
        }
    }
    
    /// Alterna el estado de mute de la pista indicada.
    ///
    /// Al mutear: el nodo recibe 0.0 pero `track.volume` se conserva.
    /// Al desmutear: el nodo recupera el valor de `track.volume`.
    /// - Parameter trackIndex: Índice de la pista (0-3).
    func toggleMute(for trackIndex: Int) {
        guard (0..<trackCount).contains(trackIndex) else { return }
        tracks[trackIndex].isMuted.toggle()
        playerNodes[trackIndex].volume = tracks[trackIndex].isMuted ? 0.0 : tracks[trackIndex].volume
    }
    
    // MARK: - DSP Helpers
    
    /// Calcula un nivel de señal normalizado (0.0 – 1.0) a partir de un buffer PCM.
    ///
    /// Algoritmo:
    /// 1. Calcula el RMS del canal 0 usando `vDSP_rmsqv` (Accelerate framework).
    /// 2. Convierte RMS a decibelios: `dB = 20 * log10(rms)`.
    /// 3. Normaliza el rango [-60 dB … 0 dB] → [0.0 … 1.0].
    ///
    /// - Parameter buffer: Buffer PCM de entrada (grabación o reproducción).
    /// - Returns: Nivel normalizado listo para el VU meter de la UI.
    private func calculateNormalizedLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let frameCount = vDSP_Length(buffer.frameLength)
        guard frameCount > 0 else { return 0.0 }
        
        var rms: Float = 0.0
        vDSP_rmsqv(channelData[0], 1, &rms, frameCount)
        
        guard rms > 0 else { return 0.0 }
        
        let dB = 20.0 * log10(rms)
        let minDB: Float = -60.0
        let maxDB: Float =   0.0
        let normalized = (dB - minDB) / (maxDB - minDB)
        return min(max(normalized, 0.0), 1.0)
    }
    
    /// Instala un tap de medición de VU meter en un `AVAudioPlayerNode`.
    ///
    /// El nivel se escala por el fader post-mute de la pista para reflejar
    /// el volumen real percibido en el mix.
    /// - Parameters:
    ///   - player: Nodo de reproducción en el que instalar el tap.
    ///   - trackIndex: Índice de la pista para actualizar `meterLevel`.
    private func installMeterTap(on player: AVAudioPlayerNode, trackIndex: Int) {
        let postFaderScale = tracks[trackIndex].isMuted ? Float(0.0) : tracks[trackIndex].volume
        player.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateNormalizedLevel(from: buffer) * postFaderScale
            DispatchQueue.main.async {
                self.tracks[trackIndex].meterLevel = level
            }
        }
    }
    
    /// Calcula un `AVAudioTime` sample-accurate en el futuro inmediato.
    ///
    /// Usar un tiempo compartido para todas las pistas garantiza que los
    /// `player.play(at:)` estén sincronizados al mismo frame de audio.
    /// - Parameter offsetSeconds: Segundos de anticipación (e.g. 0.05 = 50 ms).
    /// - Returns: `AVAudioTime` futuro, o `nil` si el outputNode no tiene render time.
    private func makeStartTime(offsetSeconds: Double) -> AVAudioTime? {
        guard let lastRenderTime = engine.outputNode.lastRenderTime,
              lastRenderTime.isSampleTimeValid else {
            return nil
        }
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let offsetSamples = AVAudioFramePosition(offsetSeconds * sampleRate)
        return AVAudioTime(
            sampleTime: lastRenderTime.sampleTime + offsetSamples,
            atRate: sampleRate
        )
    }
    
    // MARK: - Audio Session
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            print("Éxito: Sesión de audio configurada correctamente.")
        } catch {
            print("Error fatal al configurar AVAudioSession: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Input Monitoring
    
    /// Alterna el estado del monitoreo de entrada del micrófono en tiempo real.
    ///
    /// - Con auriculares: alterna `isMonitoringEnabled` y aplica volumen (1.0 / 0.0) a `monitorMixerNode`.
    /// - Sin auriculares (modo altavoz): fuerza silencio, apaga `isMonitoringEnabled` y levanta `showMonitoringWarning`.
    func toggleMonitoring() {
        if areHeadphonesConnected {
            isMonitoringEnabled.toggle()
            monitorMixerNode.outputVolume = isMonitoringEnabled ? 1.0 : 0.0
            print("Input Monitoring: \(isMonitoringEnabled ? "ACTIVADO" : "DESACTIVADO")")
        } else {
            isMonitoringEnabled = false
            monitorMixerNode.outputVolume = 0.0
            DispatchQueue.main.async {
                self.showMonitoringWarning = true
            }
            print("Intento de activar Input Monitoring sin auriculares: bloqueado por seguridad.")
        }
    }
    
    // MARK: - Route Change & Safety Fallback
    
    /// Registra el observador de cambios de ruta de audio (desconexión de auriculares).
    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleRouteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Safety Fallback: si se desconectan los auriculares mientras el monitoreo está activo,
            // silenciar de inmediato para evitar acople acústico por los altavoces.
            if !self.areHeadphonesConnected && self.isMonitoringEnabled {
                self.isMonitoringEnabled = false
                self.monitorMixerNode.outputVolume = 0.0
                print("Auriculares desconectados: Input Monitoring desactivado automáticamente por seguridad.")
            }
        }
    }
}
