//
//  TapeProject.swift
//  Taper
//
//  Created by Jose maria Martinez marconi on 15/10/2026.
//

import Foundation

/// Modelo de un proyecto "Tape" (cassette virtual).
///
/// Cada TapeProject almacena el estado completo de las 4 pistas
/// (volúmenes, mutes, URLs de archivos WAV) y metadatos del proyecto.
/// Se persiste en disco como JSON dentro de `tapes.json`.
struct TapeProject: Identifiable, Codable {
    
    /// Identificador único del proyecto.
    let id: UUID
    
    /// Nombre visible del proyecto (e.g. "Mi Canción", "Demo Acústico").
    var name: String
    
    /// Fecha de creación del proyecto.
    let createdAt: Date
    
    /// Estado persistido de las 4 pistas (volumen, mute, fileURL).
    /// Los estados efímeros (isRecording, isPlaying, isArmed, meterLevel)
    /// se restauran a sus defaults al decodificar gracias al Codable de Track.
    var tracks: [Track]
    
    /// Crea un nuevo proyecto con 4 pistas vacías y valores por defecto.
    /// - Parameter name: Nombre del proyecto.
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.tracks = (0..<4).map { i in
            Track(id: i, name: "T\(i + 1)")
        }
    }
}
