//
//  Track.swift
//  Taper
//
//  Created by Jose maria Martinez marconi on 12/10/2026.
//

import Foundation

/// Modelo de datos para una pista individual del grabador de 4 pistas.
///
/// Es un value type (struct), Identifiable para `ForEach`, y Codable para
/// persistencia en disco. Los estados efímeros de UI/DSP (isRecording, isPlaying,
/// isArmed, meterLevel) se excluyen de la codificación y se restauran a sus
/// valores por defecto al decodificar.
struct Track: Identifiable, Codable {
    
    // MARK: - CodingKeys
    
    /// Solo se persisten las propiedades relevantes al proyecto:
    /// identificación, archivo de audio, volumen y mute.
    /// Los estados de transporte y metering son efímeros y no se guardan.
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileURL
        case volume
        case isMuted
    }
    
    // MARK: - Identificación
    
    /// Identificador único (0-based, corresponde al índice en el array).
    let id: Int
    
    /// Nombre corto para mostrar en la UI (e.g. "T1", "T2").
    let name: String
    
    // MARK: - Estado de Transporte (efímero — no se persiste)
    
    /// `true` mientras esta pista está capturando audio del micrófono.
    /// Solo una pista puede estar grabando a la vez (limitación de `installTap`).
    var isRecording: Bool = false
    
    /// `true` mientras esta pista está reproduciendo su archivo.
    /// Múltiples pistas pueden reproducir simultáneamente.
    var isPlaying: Bool = false
    
    /// `true` cuando la pista está armada (lista para grabar al pulsar Master REC).
    /// Solo una pista puede estar armada a la vez (exclusividad de micrófono).
    var isArmed: Bool = false
    
    // MARK: - Datos de Audio
    
    /// URL del último archivo WAV grabado en esta pista.
    /// `nil` si la pista nunca ha grabado.
    var fileURL: URL? = nil
    
    /// Indica si la pista tiene audio grabado listo para reproducir.
    /// Propiedad computada: se actualiza automáticamente con `fileURL`.
    var hasAudio: Bool { fileURL != nil }
    
    // MARK: - Mezcla
    
    /// Nivel de volumen de la pista (0.0 = silencio, 1.0 = máximo).
    /// Valor por defecto al 80% para dejar headroom en la mezcla.
    var volume: Float = 0.8
    
    /// `true` cuando la pista está silenciada (mute activo).
    /// Al mutear, el `AVAudioPlayerNode` recibe volumen 0.0 pero
    /// el valor de `volume` se conserva para restaurarlo al desmutear.
    var isMuted: Bool = false
    
    // MARK: - Metering (efímero — no se persiste)
    
    /// Nivel de señal normalizado para el VU meter de la UI (0.0 – 1.0).
    /// Se calcula vía RMS → dB en el AudioManager y siempre se actualiza
    /// en el main thread desde los tap callbacks de grabación o reproducción.
    /// Se resetea a 0.0 cuando la pista deja de grabar o reproducir.
    var meterLevel: Float = 0.0
}
