//
//  ContentView.swift
//  Taper
//
//  Created by Jose maria Martinez marconi on 21/08/2026.
//

import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    
    /// Fuente de verdad del motor de audio, inyectada como StateObject.
    @StateObject private var audioManager = AudioManager()
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ── Engine Control Section (Top) ──────────────────────
            engineControlSection
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // ── 4-Channel Strip Mixer ─────────────────────────────
            channelStripSection
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // ── Master Transport Bar (Bottom) ─────────────────────
            masterTransportBar
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .alert("Headphones Required", isPresented: $audioManager.showMonitoringWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Input monitoring is disabled while using speakers to prevent severe acoustic feedback. Please connect headphones to monitor your microphone.")
        }
    }
}

// MARK: - Engine Control Section

private extension ContentView {
    
    /// Sección superior: indicador de estado, botón de Input Monitoring + botón Start/Stop del engine.
    var engineControlSection: some View {
        VStack(spacing: 16) {
            
            HStack {
                // Indicador de estado del engine
                HStack(spacing: 8) {
                    Circle()
                        .fill(audioManager.isRunning ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                    
                    Text(audioManager.isRunning ? "ENGINE RUNNING" : "ENGINE STOPPED")
                        .font(.caption)
                        .fontWeight(.medium)
                        .tracking(1.5)
                        .foregroundColor(audioManager.isRunning ? .white : .gray)
                }
                
                Spacer()
                
                // Botón de Input Monitoring (requiere auriculares)
                Button {
                    audioManager.toggleMonitoring()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "headphones")
                            .font(.system(size: 12, weight: .bold))
                        
                        Text(audioManager.isMonitoringEnabled ? "MONITOR ON" : "MONITOR")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(
                        audioManager.isMonitoringEnabled
                            ? Color(red: 0.3, green: 0.85, blue: 0.45)
                            : Color.gray.opacity(0.7)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                audioManager.isMonitoringEnabled
                                    ? Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.12)
                                    : Color.white.opacity(0.04)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                audioManager.isMonitoringEnabled
                                    ? Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.8)
                                    : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                }
            }
            .padding(.horizontal, 24)
            
            Button {
                audioManager.toggleEngine()
            } label: {
                Text(audioManager.isRunning ? "STOP" : "START")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundColor(audioManager.isRunning ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(audioManager.isRunning
                                  ? Color.white.opacity(0.08)
                                  : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Channel Strip Section

private extension ContentView {
    
    /// HStack con los 4 channel strips verticales, estilo mixer de consola.
    var channelStripSection: some View {
        HStack(spacing: 0) {
            ForEach(Array(audioManager.tracks.enumerated()), id: \.element.id) { index, track in
                ChannelStrip(
                    track: track,
                    trackIndex: index,
                    isEngineRunning: audioManager.isRunning,
                    audioManager: audioManager
                )
                
                if index < audioManager.tracks.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Master Transport Bar

private extension ContentView {
    
    /// Barra inferior de transporte estilo hardware Portastudio.
    /// PLAY, REC y STOP controlan todas las pistas de forma sincronizada.
    var masterTransportBar: some View {
        let anyArmed = audioManager.tracks.contains(where: { $0.isArmed })
        
        return HStack(spacing: 0) {
            
            // ── PLAY ──────────────────────────────────────────────
            TransportButton(
                label: "▶  PLAY",
                isActive: audioManager.isMasterPlaying,
                activeColor: Color(red: 0.3, green: 0.85, blue: 0.45),
                isEnabled: audioManager.isRunning && !audioManager.isMasterRecording
            ) {
                audioManager.startMasterPlay()
            }
            
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
            
            // ── REC ───────────────────────────────────────────────
            TransportButton(
                label: "●  REC",
                isActive: audioManager.isMasterRecording,
                activeColor: Color(red: 1.0, green: 0.18, blue: 0.18),
                isEnabled: audioManager.isRunning && anyArmed
            ) {
                audioManager.startMasterRecord()
            }
            
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
            
            // ── STOP ──────────────────────────────────────────────
            TransportButton(
                label: "■  STOP",
                isActive: false,
                activeColor: .white,
                isEnabled: audioManager.isRunning && (audioManager.isMasterPlaying || audioManager.isMasterRecording)
            ) {
                audioManager.stopMasterTransport()
            }
        }
        .frame(height: 72)
        .background(Color.white.opacity(0.03))
    }
}

// MARK: - TransportButton

/// Botón de transporte estilo hardware: flat, minimalista, con estados activo/inactivo.
struct TransportButton: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(isActive ? activeColor : (isEnabled ? .white : .gray.opacity(0.35)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isActive
                    ? activeColor.opacity(0.12)
                    : Color.clear
            )
            .overlay(
                // Línea superior de acento cuando está activo
                VStack {
                    Rectangle()
                        .fill(isActive ? activeColor : Color.clear)
                        .frame(height: 2)
                    Spacer()
                }
            )
            .animation(.easeInOut(duration: 0.12), value: isActive)
        }
        .disabled(!isEnabled)
    }
}

// MARK: - ChannelStrip

/// Columna vertical para cada canal.
/// Contiene: badge de audio, label, VU meter, fader de volumen, botón ARM, botones M/S.
struct ChannelStrip: View {
    
    let track: Track
    let trackIndex: Int
    let isEngineRunning: Bool
    
    @ObservedObject var audioManager: AudioManager
    
    /// Estado local del botón Solo (no conectado al AudioManager todavía).
    @State private var isSoloed: Bool = false
    
    // Accent colors
    private let accentRed    = Color(red: 0.85, green: 0.25, blue: 0.25)
    private let brightRed    = Color(red: 1.0,  green: 0.2,  blue: 0.2)
    private let accentGreen  = Color(red: 0.3,  green: 0.85, blue: 0.4)
    private let accentCyan   = Color(red: 0.55, green: 0.85, blue: 0.95)
    private let accentYellow = Color(red: 0.95, green: 0.85, blue: 0.35)
    private let accentOrange = Color(red: 1.0,  green: 0.55, blue: 0.1)
    
    var body: some View {
        VStack(spacing: 10) {
            
            // ── Audio Badge + Channel Label ───────────────────────
            channelHeader
            
            // ── VU Meter (vertical) ───────────────────────────────
            vuMeter
            
            // ── Volume Readout ────────────────────────────────────
            volumeReadout
            
            // ── Volume Fader (vertical, custom) ───────────────────
            verticalFader
            
            // ── ARM Button ────────────────────────────────────────
            armButton
                .padding(.horizontal, 12)
            
            // ── M (Mute) & S (Solo) Buttons ───────────────────────
            HStack(spacing: 4) {
                muteButton
                soloButton
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(trackIndex.isMultiple(of: 2) ? 0.02 : 0))
    }
}

// MARK: - ChannelStrip Subviews

private extension ChannelStrip {
    
    // MARK: Channel Header
    
    /// Label de pista con badge de audio disponible.
    var channelHeader: some View {
        VStack(spacing: 3) {
            // Badge de audio grabado
            HStack(spacing: 3) {
                if track.hasAudio {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(accentGreen.opacity(0.7))
                        .frame(width: 16, height: 3)
                } else {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 16, height: 3)
                }
            }
            
            // Nombre de pista
            Text(track.name)
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(
                    track.isRecording ? brightRed :
                    track.isArmed     ? accentOrange :
                    .white
                )
        }
    }
    
    // MARK: ARM Button
    
    /// Botón de arm — reemplaza el botón REC individual.
    /// Estados visuales:
    ///   - Gris: desarmado.
    ///   - Naranja: armado (listo para grabar al pulsar Master REC).
    ///   - Rojo: grabando activamente.
    var armButton: some View {
        Button {
            audioManager.toggleArm(for: trackIndex)
        } label: {
            HStack(spacing: 5) {
                // Indicador circular de estado
                Circle()
                    .fill(armIndicatorColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: armIndicatorColor.opacity(0.6),
                            radius: track.isRecording || track.isArmed ? 4 : 0)
                
                Text(armButtonLabel)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(armTextColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(armBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(armBorderColor, lineWidth: track.isArmed || track.isRecording ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.15), value: track.isArmed)
            .animation(.easeInOut(duration: 0.15), value: track.isRecording)
        }
        .disabled(audioManager.isMasterRecording)
    }
    
    private var armButtonLabel: String {
        if track.isRecording { return "REC" }
        if track.isArmed     { return "ARMED" }
        return "ARM"
    }
    
    private var armIndicatorColor: Color {
        if track.isRecording { return brightRed }
        if track.isArmed     { return accentOrange }
        return Color.gray.opacity(0.4)
    }
    
    private var armTextColor: Color {
        if track.isRecording { return .white }
        if track.isArmed     { return accentOrange }
        return .gray
    }
    
    private var armBackgroundColor: Color {
        if track.isRecording { return brightRed.opacity(0.2) }
        if track.isArmed     { return accentOrange.opacity(0.12) }
        return Color.white.opacity(0.05)
    }
    
    private var armBorderColor: Color {
        if track.isRecording { return brightRed }
        if track.isArmed     { return accentOrange }
        return Color.gray.opacity(0.2)
    }
    
    // MARK: Mute Button
    
    var muteButton: some View {
        Button {
            audioManager.toggleMute(for: trackIndex)
        } label: {
            Text("M")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(track.isMuted ? .black : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(track.isMuted ? accentCyan : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(track.isMuted ? accentCyan : Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .animation(.easeInOut(duration: 0.12), value: track.isMuted)
    }
    
    // MARK: Solo Button
    
    var soloButton: some View {
        Button {
            isSoloed.toggle()
        } label: {
            Text("S")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(isSoloed ? .black : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isSoloed ? accentYellow : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSoloed ? accentYellow : Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: Volume Readout
    
    /// Indicador numérico de volumen o estado de Mute.
    var volumeReadout: some View {
        Text(track.isMuted ? "MUTE" : "\(Int(track.volume * 100))%")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(0.5)
            .foregroundColor(track.isMuted ? accentCyan : Color.gray.opacity(0.7))
            .animation(.easeInOut(duration: 0.12), value: track.isMuted)
    }
    
    // MARK: Vertical Fader
    
    /// Fader vertical custom construido con DragGesture.
    /// Emula el recorrido y tacto de un fader analógico de consola Portastudio.
    var verticalFader: some View {
        GeometryReader { geo in
            let trackHeight = max(geo.size.height, 1)
            let currentVolume = CGFloat(track.volume)
            // Posición Y del thumb: 0 (arriba) = 1.0 (máximo), trackHeight (abajo) = 0.0 (silencio)
            let thumbY = min(max((1.0 - currentVolume) * trackHeight, 0), trackHeight)
            
            ZStack(alignment: .top) {
                // ── Riel del fader ─────────────────────────────────
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                
                // ── Relleno activo (desde abajo hasta el thumb) ────
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(track.isMuted ? Color.gray.opacity(0.25) : Color.white.opacity(0.3))
                        .frame(width: 3, height: max(0, trackHeight * currentVolume))
                }
                
                // ── Thumb (cap físico de consola) ──────────────────
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            track.isMuted
                                ? LinearGradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [Color.white, Color(white: 0.88)], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
                    
                    // Ranura central clásica del fader cap
                    Rectangle()
                        .fill(track.isMuted ? Color.black.opacity(0.3) : Color.black.opacity(0.65))
                        .frame(width: 14, height: 1.5)
                }
                .frame(width: 28, height: 10)
                .offset(y: thumbY - 5) // Centra los 10pt de altura
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle()) // Toda la columna es tappable/draggable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = 1.0 - (value.location.y / trackHeight)
                        let clamped = min(max(Float(normalized), 0.0), 1.0)
                        audioManager.setVolume(for: trackIndex, volume: clamped)
                    }
            )
        }
        .frame(width: 40)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 4)
    }
    
    // MARK: VU Meter
    
    /// Barra vertical de VU meter en tiempo real.
    ///
    /// Lee `track.meterLevel` (0.0 – 1.0) calculado por DSP en el AudioManager.
    /// - Señal normal (< 0.85): degradado blanco/gris estilo consola.
    /// - Peak (≥ 0.85): rojo brillante como indicador de clipping.
    var vuMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Fondo del rail
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.07))
                
                let level = CGFloat(track.meterLevel)
                let isPeaking = track.meterLevel >= 0.85
                
                // Barra de nivel reactiva
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: isPeaking
                                ? [Color(red: 1.0, green: 0.15, blue: 0.15),
                                   Color(red: 1.0, green: 0.4,  blue: 0.0)]
                                : [Color.white.opacity(0.85),
                                   Color.white.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: geo.size.height * level)
                    .animation(.linear(duration: 0.05), value: track.meterLevel)
                
                // Tick de peak
                if isPeaking {
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.15, blue: 0.15))
                        .frame(height: 2)
                        .offset(y: -(geo.size.height * level - 2))
                        .animation(.linear(duration: 0.05), value: track.meterLevel)
                }
            }
        }
        .frame(width: 8, height: 60)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
