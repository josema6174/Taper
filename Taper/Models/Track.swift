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
        case eqLow
        case eqMid
        case eqHigh
        case reverbMix
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
    
    /// `true` si la pista está en Solo (efímero — no se persiste).
    var isSoloed: Bool = false
    
    // MARK: - EQ (3 bandas, en dB, rango -12.0 ... 12.0)
    
    /// Ganancia de la banda grave (low shelf @ 100 Hz).
    var eqLow: Float = 0.0
    
    /// Ganancia de la banda media (parametric @ 1 kHz).
    var eqMid: Float = 0.0
    
    /// Ganancia de la banda aguda (high shelf @ 8 kHz).
    var eqHigh: Float = 0.0
    
    /// `true` si alguna banda del EQ no está en 0 dB.
    var isEQActive: Bool { eqLow != 0 || eqMid != 0 || eqHigh != 0 }
    
    /// Wet/dry del reverb individual de la pista (0.0 – 100.0).
    var reverbMix: Float = 0.0
    
    /// `true` si hay algún EQ o reverb distinto de cero.
    var isFXActive: Bool { isEQActive || reverbMix != 0 }
    
    // MARK: - Metering (efímero — no se persiste)
    
    /// Nivel de señal normalizado para el VU meter de la UI (0.0 – 1.0).
    /// Se calcula vía RMS → dB en el AudioManager y siempre se actualiza
    /// en el main thread desde los tap callbacks de grabación o reproducción.
    /// Se resetea a 0.0 cuando la pista deja de grabar o reproducir.
    var meterLevel: Float = 0.0
}


// MARK: - Backward-compatible Decoding

extension Track {
    /// Decodificación tolerante: los proyectos guardados antes del EQ
    /// (sin claves `eqLow/eqMid/eqHigh`) cargan con 0.0 dB.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(Int.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        self.init(id: id, name: name)
        self.fileURL = try c.decodeIfPresent(URL.self, forKey: .fileURL)
        self.volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 0.8
        self.isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        self.eqLow = try c.decodeIfPresent(Float.self, forKey: .eqLow) ?? 0.0
        self.eqMid = try c.decodeIfPresent(Float.self, forKey: .eqMid) ?? 0.0
        self.eqHigh = try c.decodeIfPresent(Float.self, forKey: .eqHigh) ?? 0.0
        self.reverbMix = try c.decodeIfPresent(Float.self, forKey: .reverbMix) ?? 0.0
    }
}
