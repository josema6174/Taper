import Foundation
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    
    // Nuestro motor principal
    let engine = AVAudioEngine()
    
    // Estado observable para la UI — refleja si el engine está encendido
    @Published var isRunning: Bool = false
    
    init() {
        setupAudioSession()
        setupAudioGraph()
    }
    
    // MARK: - Audio Graph
    
    /// Conecta el grafo mínimo: inputNode → mainMixerNode → outputNode.
    /// Sin esto, engine.start() crashea porque no hay ningún nodo conectado.
    private func setupAudioGraph() {
        // Acceder a inputNode fuerza al engine a configurar el nodo de entrada (micrófono).
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Conectamos input → mixer. El mixer ya está conectado a outputNode por defecto.
        engine.connect(inputNode, to: engine.mainMixerNode, format: inputFormat)
        
        print("Audio graph configurado: input (\(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch) → mixer → output")
    }
    
    // MARK: - Engine Control
    
    /// Arranca o detiene el AVAudioEngine y actualiza el estado publicado.
    func toggleEngine() {
        if engine.isRunning {
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
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // 1. Configuramos para poder grabar (mic) y reproducir a la vez
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            
            // 2. Pedimos el buffer más pequeño posible (aprox 5ms) para reducir la latencia al mínimo
            try session.setPreferredIOBufferDuration(0.005)
            
            // 3. Encendemos la sesión de hardware
            try session.setActive(true)
            
            print("Éxito: Sesión de audio configurada correctamente.")
            
        } catch {
            print("Error fatal al configurar AVAudioSession: \(error.localizedDescription)")
        }
    }
}//
//  AudioManager.swift
//  Taper
//
//  Created by Jose maria Martinez marconi on 21/08/2026.
//

