import Foundation
import AVFoundation
import Combine

class AudioManager: ObservableObject {
    
    // Nuestro motor principal
    let engine = AVAudioEngine()
    
    init() {
        setupAudioSession()
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

