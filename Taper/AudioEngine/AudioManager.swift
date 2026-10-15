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
    
    /// `true` mientras se está renderizando y exportando la mezcla offline a un archivo .m4a.
    @Published var isExporting: Bool = false
    
    // MARK: - Project Management
    
    /// Proyecto de cinta actualmente cargado. `nil` si no se ha creado/cargado ninguno.
    @Published var currentTape: TapeProject?
    
    /// Biblioteca de todos los proyectos guardados en disco.
    @Published var savedTapes: [TapeProject] = []
    
    /// URL del archivo JSON que almacena la biblioteca de proyectos.
    private var tapesFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("tapes.json")
    }
    
    // MARK: - RTL Compensation
    
    /// Calcula la latencia total de ida y vuelta (RTL) del hardware de audio.
    /// Suma latencia de entrada, salida y duración del buffer I/O. Si el cálculo da 0, se usa un fallback de 15 ms.
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
        loadTapesFromDisk()
        
        // Si hay proyectos guardados, cargar el último modificado automáticamente.
        // Si no hay ninguno, crear un proyecto "Untitled Tape" por defecto.
        if let lastTape = savedTapes.first {
            loadTape(project: lastTape)
        } else {
            createNewTape(name: "Untitled Tape")
        }
        
        // Auto-inicio transparente del motor de audio al inicializar
        ensureEngineIsRunning()
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
        var inputFormat = inputNode.outputFormat(forBus: 0)
        if inputFormat.sampleRate == 0 || inputFormat.channelCount == 0 {
            inputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        }
        
        // 1. Monitoreo de entrada: conectar micrófono a través de monitorMixerNode
        // Silenciado por defecto (0.0) para prevenir acople accidental por altavoces.
        if monitorMixerNode.engine == nil {
            engine.attach(monitorMixerNode)
        }
        engine.connect(inputNode, to: monitorMixerNode, format: inputFormat)
        engine.connect(monitorMixerNode, to: engine.mainMixerNode, format: inputFormat)
        monitorMixerNode.outputVolume = isMonitoringEnabled ? 1.0 : 0.0
        print("Nodo monitorMixerNode adjuntado y conectado al mainMixerNode (volumen: \(monitorMixerNode.outputVolume)).")
        
        // 2. Adjuntar y conectar los 4 playerNodes al mainMixerNode
        for (index, player) in playerNodes.enumerated() {
            if player.engine == nil {
                engine.attach(player)
            }
            engine.connect(player, to: engine.mainMixerNode, format: inputFormat)
            player.volume = tracks[index].isMuted ? 0.0 : tracks[index].volume
            print("PlayerNode[\(index)] adjuntado y conectado al mixer.")
        }
        
        print("Grafo configurado: \(trackCount) pistas + monitorMixer conectados al mixer.")
    }
    
    // MARK: - Engine Auto-Start & Safety Check (Lazy Start)
    
    /// Garantiza que el motor de audio esté corriendo (lazy start).
    /// Se invoca al iniciar la app y como verificación de seguridad antes de
    /// reproducir, grabar o activar el monitoreo, protegiendo la sesión si iOS
    /// pausó el hardware (e.g. app enviada a segundo plano o interrupción).
    func ensureEngineIsRunning() {
        if !engine.isRunning {
            do {
                try engine.start()
                print("Engine iniciado automáticamente (auto/lazy start).")
            } catch {
                print("Error al iniciar AVAudioEngine: \(error.localizedDescription)")
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
        // Verificación de seguridad (lazy start automático)
        ensureEngineIsRunning()
        guard engine.isRunning else {
            print("Error: No se pudo arrancar el engine para reproducción.")
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
            
            // Verificar que el archivo siga existiendo en disco
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Advertencia: Archivo de pista \(i + 1) no encontrado en disco, saltando.")
                tracks[i].fileURL = nil
                continue
            }
            
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
        // Verificación de seguridad (lazy start automático)
        ensureEngineIsRunning()
        guard engine.isRunning else {
            print("Error: No se pudo arrancar el engine para grabación.")
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
        
        // Preparar archivo WAV de destino con UUID para evitar colisiones entre proyectos
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent("Track\(armedIndex + 1)_\(UUID().uuidString).wav")
        
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
            
            // Verificar que el archivo siga existiendo en disco
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Advertencia: Archivo de pista \(i + 1) no encontrado en disco, saltando.")
                tracks[i].fileURL = nil
                continue
            }
            
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
    /// Guarda automáticamente el proyecto actual al detener.
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
        
        // 3. Auto-save del proyecto actual
        saveCurrentTape()
        
        print("Master Transport detenido.")
    }
    
    // MARK: - Export Mixdown (Offline Rendering)
    
    /// Exporta la mezcla multitrack a un archivo comprimido `.m4a` (AAC) usando renderizado offline (bouncing).
    ///
    /// Pasos:
    /// 1. Verifica que haya al menos una pista con audio en disco y determina la duración máxima de la mezcla.
    /// 2. Detiene el engine.
    /// 3. Activa el modo manual rendering offline en `engine` con formato estéreo y frames máximos de 4096.
    /// 4. Crea un archivo `AVAudioFile` de salida AAC en el directorio temporal (`NSTemporaryDirectory`).
    /// 5. Agenda las pistas con audio en sus respectivos `AVAudioPlayerNode`s, aplicando sus volúmenes y estados de mute.
    /// 6. Inicia el engine y arranca los playerNodes.
    /// 7. Itera en un bucle llamando a `engine.renderOffline(4096, to: buffer)` y escribe al archivo hasta alcanzar la duración máxima.
    /// 8. Detiene el engine, desactiva el modo offline y restablece el grafo de audio para reproducción en tiempo real.
    /// 9. Notifica la URL del archivo resultante en el hilo principal mediante el `completion` handler.
    ///
    /// Todo el renderizado corre en un hilo en segundo plano (`DispatchQueue.global`) para no bloquear la UI.
    /// - Parameter completion: Handler llamado en el main thread con la `URL` del archivo `.m4a`, o `nil` en caso de error.
    func exportMixdown(completion: @escaping (URL?) -> Void) {
        // Evitar exportaciones concurrentes
        guard !isExporting else {
            print("Exportación ya en curso.")
            return
        }
        
        // 1. Validar que exista al menos una pista con audio disponible en disco
        let activeTracks = tracks.filter { track in
            guard track.hasAudio, let url = track.fileURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        
        guard !activeTracks.isEmpty else {
            print("Error al exportar: No hay pistas con audio grabado.")
            completion(nil)
            return
        }
        
        // Detener cualquier reproducción o grabación activa antes del bounce
        if isMasterPlaying || isMasterRecording {
            stopMasterTransport()
        }
        
        // Indicar a la UI que la exportación comenzó
        isExporting = true
        
        // Ejecutar en hilo secundario para mantener la fluidez de la UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var exportURL: URL? = nil
            
            do {
                // 1. Abrir archivos y encontrar la duración máxima de todas las pistas
                var filesToSchedule: [(trackIndex: Int, file: AVAudioFile)] = []
                var maxDurationSeconds: Double = 0.0
                
                for (index, track) in self.tracks.enumerated() {
                    guard track.hasAudio, let fileURL = track.fileURL,
                          FileManager.default.fileExists(atPath: fileURL.path) else {
                        continue
                    }
                    
                    let file = try AVAudioFile(forReading: fileURL)
                    let duration = Double(file.length) / file.processingFormat.sampleRate
                    if duration > maxDurationSeconds {
                        maxDurationSeconds = duration
                    }
                    filesToSchedule.append((trackIndex: index, file: file))
                }
                
                guard !filesToSchedule.isEmpty, maxDurationSeconds > 0 else {
                    throw NSError(
                        domain: "AudioManager",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No se encontraron pistas válidas con duración mayor a cero."]
                    )
                }
                
                // 2. Detener el engine
                if self.engine.isRunning {
                    self.engine.stop()
                }
                
                // 3. Activar modo offline de renderizado manual
                var renderFormat = self.engine.mainMixerNode.outputFormat(forBus: 0)
                if renderFormat.sampleRate == 0 || renderFormat.channelCount == 0 {
                    renderFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
                }
                
                let maxFrameCapacity: AVAudioFrameCount = 4096
                try self.engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: maxFrameCapacity)
                
                let totalFramesToRender = AVAudioFramePosition(ceil(maxDurationSeconds * renderFormat.sampleRate))
                
                // 4. Crear archivo de salida .m4a (AAC) en el directorio temporal
                let rawTapeName = self.currentTape?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let tapeName = (rawTapeName?.isEmpty == false ? rawTapeName! : "Tape")
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Mixdown_\(tapeName).m4a")
                try? FileManager.default.removeItem(at: outputURL)
                
                let aacSettings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: renderFormat.sampleRate,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192000
                ]
                
                // Bloque para asegurar que outputFile se deasigne y cierre todos sus metadatos/headers AAC
                try {
                    let outputFile = try AVAudioFile(
                        forWriting: outputURL,
                        settings: aacSettings,
                        commonFormat: .pcmFormatFloat32,
                        interleaved: false
                    )
                    
                    // 5. Agendar cada pista con audio en su playerNode respetando volumen y mute
                    for item in filesToSchedule {
                        let player = self.playerNodes[item.trackIndex]
                        player.stop()
                        player.removeTap(onBus: 0)
                        
                        let track = self.tracks[item.trackIndex]
                        player.volume = track.isMuted ? 0.0 : track.volume
                        player.scheduleFile(item.file, at: nil, completionHandler: nil)
                    }
                    
                    // Asegurar que playerNodes sin audio estén silenciados y sin taps
                    for (index, player) in self.playerNodes.enumerated() {
                        if !filesToSchedule.contains(where: { $0.trackIndex == index }) {
                            player.stop()
                            player.removeTap(onBus: 0)
                        }
                    }
                    
                    // Asegurar que el monitoreo del micrófono esté silenciado en el mixdown offline
                    self.monitorMixerNode.outputVolume = 0.0
                    
                    // 6. Iniciar el engine y comenzar reproducción de los playerNodes
                    try self.engine.start()
                    for item in filesToSchedule {
                        self.playerNodes[item.trackIndex].play()
                    }
                    
                    // 7. Loop de renderizado offline
                    let buffer = AVAudioPCMBuffer(pcmFormat: self.engine.manualRenderingFormat, frameCapacity: maxFrameCapacity)!
                    
                    while self.engine.manualRenderingSampleTime < totalFramesToRender {
                        let remainingFrames = totalFramesToRender - self.engine.manualRenderingSampleTime
                        let framesToRender = min(maxFrameCapacity, AVAudioFrameCount(remainingFrames))
                        
                        let status = try self.engine.renderOffline(framesToRender, to: buffer)
                        
                        switch status {
                        case .success:
                            try outputFile.write(from: buffer)
                        case .insufficientDataFromInputNode:
                            break
                        case .cannotDoInCurrentContext:
                            print("Advertencia: Offline render context ocupado.")
                            break
                        case .error:
                            throw NSError(
                                domain: "AudioManager",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Error en renderOffline de AVAudioEngine."]
                            )
                        @unknown default:
                            break
                        }
                    }
                }()
                
                exportURL = outputURL
                print("Mixdown renderizado con éxito: \(outputURL.path)")
                
            } catch {
                print("Error en exportMixdown: \(error.localizedDescription)")
            }
            
            // 8. Detener engine, deshabilitar modo offline y limpiar playerNodes
            self.engine.stop()
            self.engine.disableManualRenderingMode()
            for player in self.playerNodes {
                player.stop()
                player.removeTap(onBus: 0)
            }
            
            // 9. Restablecer grafo para tiempo real, reiniciar engine y notificar completion
            DispatchQueue.main.async {
                self.setupAudioGraph()
                self.ensureEngineIsRunning()
                self.isExporting = false
                completion(exportURL)
            }
        }
    }
    
    // MARK: - Project Management
    
    /// Guarda el estado actual de las 4 pistas en el proyecto activo y persiste a disco.
    ///
    /// Sincroniza los datos de `tracks` (fileURL, volume, isMuted) hacia `currentTape.tracks`,
    /// actualiza la entrada en `savedTapes` y escribe `tapes.json`.
    func saveCurrentTape() {
        guard var tape = currentTape else { return }
        
        // Sincronizar el estado actual de las pistas al proyecto
        tape.tracks = tracks
        currentTape = tape
        
        // Actualizar en la biblioteca
        if let index = savedTapes.firstIndex(where: { $0.id == tape.id }) {
            savedTapes[index] = tape
        } else {
            savedTapes.insert(tape, at: 0)
        }
        
        saveTapesToDisk()
        print("Proyecto '\(tape.name)' guardado.")
    }
    
    /// Crea un nuevo proyecto vacío con el nombre indicado.
    ///
    /// Detiene el engine y el transporte, resetea las 4 pistas a valores por defecto,
    /// lo establece como proyecto activo y lo persiste a disco.
    /// - Parameter name: Nombre del nuevo proyecto.
    func createNewTape(name: String) {
        // Detener transporte si estuviera activo
        stopMasterTransport()
        
        let newTape = TapeProject(name: name)
        currentTape = newTape
        
        // Resetear las pistas del AudioManager a los defaults del nuevo proyecto
        tracks = newTape.tracks
        
        // Aplicar volúmenes a los playerNodes
        for i in 0..<trackCount {
            playerNodes[i].volume = tracks[i].isMuted ? 0.0 : tracks[i].volume
        }
        
        // Persistir inmediatamente
        savedTapes.insert(newTape, at: 0)
        saveTapesToDisk()
        
        ensureEngineIsRunning()
        
        print("Nuevo proyecto creado: '\(name)'.")
    }
    
    /// Carga un proyecto existente desde la biblioteca.
    ///
    /// Detiene el transporte, restaura las pistas del proyecto
    /// y verifica que los archivos WAV referenciados sigan existiendo en disco.
    /// - Parameter project: El `TapeProject` a cargar.
    func loadTape(project: TapeProject) {
        // Detener transporte si estuviera activo
        stopMasterTransport()
        
        currentTape = project
        
        // Restaurar las pistas del proyecto con validación de archivos
        var loadedTracks = project.tracks
        for i in 0..<min(loadedTracks.count, trackCount) {
            // Resetear estados efímeros
            loadedTracks[i].isRecording = false
            loadedTracks[i].isPlaying = false
            loadedTracks[i].isArmed = false
            loadedTracks[i].meterLevel = 0.0
            
            // Verificar que el archivo WAV siga existiendo en disco
            if let fileURL = loadedTracks[i].fileURL {
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    print("Advertencia: Archivo de pista \(i + 1) no encontrado: \(fileURL.lastPathComponent). Limpiando referencia.")
                    loadedTracks[i].fileURL = nil
                }
            }
        }
        
        tracks = loadedTracks
        
        // Aplicar volúmenes a los playerNodes
        for i in 0..<trackCount {
            playerNodes[i].volume = tracks[i].isMuted ? 0.0 : tracks[i].volume
        }
        
        ensureEngineIsRunning()
        
        print("Proyecto '\(project.name)' cargado con éxito.")
    }
    
    /// Elimina un proyecto de la biblioteca y opcionalmente sus archivos de audio.
    /// - Parameter project: El `TapeProject` a eliminar.
    func deleteTape(project: TapeProject) {
        // No permitir borrar el proyecto actualmente cargado
        guard project.id != currentTape?.id else {
            print("No se puede eliminar el proyecto activo.")
            return
        }
        
        // Eliminar archivos WAV asociados del disco
        for track in project.tracks {
            if let fileURL = track.fileURL {
                try? FileManager.default.removeItem(at: fileURL)
                print("Archivo eliminado: \(fileURL.lastPathComponent)")
            }
        }
        
        // Eliminar de la biblioteca
        savedTapes.removeAll { $0.id == project.id }
        saveTapesToDisk()
        print("Proyecto '\(project.name)' eliminado.")
    }
    
    /// Renombra el proyecto indicado y persiste los cambios a disco.
    /// Si el proyecto renombrado es el actualmente activo (`currentTape`), también actualiza `currentTape.name`.
    /// - Parameters:
    ///   - project: El `TapeProject` a renombrar.
    ///   - newName: Nuevo nombre para el proyecto.
    func renameTape(project: TapeProject, newName: String) {
        renameTape(id: project.id, newName: newName)
    }
    
    /// Renombra el proyecto con el UUID indicado y persiste los cambios a disco.
    /// - Parameters:
    ///   - id: Identificador único del proyecto.
    ///   - newName: Nuevo nombre para el proyecto.
    func renameTape(id: UUID, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Si es el proyecto activo, actualizar currentTape
        if currentTape?.id == id {
            currentTape?.name = trimmedName
        }
        
        // Actualizar en savedTapes
        if let index = savedTapes.firstIndex(where: { $0.id == id }) {
            savedTapes[index].name = trimmedName
        }
        
        saveTapesToDisk()
        print("Proyecto con ID \(id) renombrado a '\(trimmedName)'.")
    }
    
    /// Renombra el proyecto activo actual (`currentTape`).
    /// - Parameter newName: Nuevo nombre para el proyecto activo.
    func renameCurrentTape(newName: String) {
        guard let current = currentTape else { return }
        renameTape(id: current.id, newName: newName)
    }
    
    // MARK: - Persistence Helpers
    
    /// Lee `tapes.json` desde el directorio Documents y carga la biblioteca.
    private func loadTapesFromDisk() {
        guard FileManager.default.fileExists(atPath: tapesFileURL.path) else {
            print("No se encontró tapes.json. Biblioteca vacía.")
            return
        }
        
        do {
            let data = try Data(contentsOf: tapesFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            savedTapes = try decoder.decode([TapeProject].self, from: data)
            // Ordenar por fecha de creación descendente (más reciente primero)
            savedTapes.sort { $0.createdAt > $1.createdAt }
            print("Biblioteca cargada: \(savedTapes.count) proyecto(s).")
        } catch {
            print("Error al cargar tapes.json: \(error.localizedDescription)")
            savedTapes = []
        }
    }
    
    /// Escribe la biblioteca completa en `tapes.json`.
    private func saveTapesToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(savedTapes)
            try data.write(to: tapesFileURL, options: .atomic)
            print("tapes.json guardado (\(savedTapes.count) proyecto(s)).")
        } catch {
            print("Error al guardar tapes.json: \(error.localizedDescription)")
        }
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
            ensureEngineIsRunning()
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
