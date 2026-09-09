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
            
            // ── Engine Test Section (Top) ──────────────────────────
            engineControlSection
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // ── 4-Channel Strip Mixer ──────────────────────────────
            channelStripSection
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Engine Control Section

private extension ContentView {
    
    /// Sección superior: indicador de estado + botón Start/Stop del engine.
    var engineControlSection: some View {
        VStack(spacing: 16) {
            
            // ── Status Indicator ───────────────────────────────────
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
            
            // ── Start / Stop Button ────────────────────────────────
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
        .padding(.vertical, 24)
    }
}

// MARK: - Channel Strip Section

private extension ContentView {
    
    /// HStack con los 4 channel strips verticales, estilo mixer de consola.
    var channelStripSection: some View {
        HStack(spacing: 0) {
            ForEach(1...4, id: \.self) { channelNumber in
                ChannelStrip(
                    channelNumber: channelNumber,
                    isEngineRunning: audioManager.isRunning
                )
                
                // Separador vertical entre canales (excepto el último)
                if channelNumber < 4 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - ChannelStrip

/// Columna vertical para cada canal. Contiene: label, VU meter,
/// fader vertical, botón REC, y botones M/S. Disposición de arriba a abajo.
struct ChannelStrip: View {
    
    let channelNumber: Int
    let isEngineRunning: Bool
    
    /// Estado local del botón REC (solo visual por ahora).
    @State private var isArmed: Bool = false
    
    /// Estado local del botón Mute.
    @State private var isMuted: Bool = false
    
    /// Estado local del botón Solo.
    @State private var isSoloed: Bool = false
    
    /// Valor placeholder del fader de volumen (0 = silencio, 1 = máximo).
    @State private var volume: Double = 0.75
    
    // Accent colors
    private let accentRed = Color(red: 0.85, green: 0.25, blue: 0.25)
    private let accentCyan = Color(red: 0.55, green: 0.85, blue: 0.95)
    private let accentYellow = Color(red: 0.95, green: 0.85, blue: 0.35)
    
    var body: some View {
        VStack(spacing: 10) {
            
            // ── Channel Label ──────────────────────────────────────
            Text("C\(channelNumber)")
                .font(.system(.headline, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(isArmed ? accentRed : .white)
            
            // ── VU Meter (vertical) ────────────────────────────────
            vuMeter
            
            // ── Volume Fader (vertical, custom) ──────────────────
            verticalFader
            
            // ── REC Button ─────────────────────────────────────────
            Button {
                isArmed.toggle()
            } label: {
                Text("REC")
                    .font(.caption2)
                    .fontWeight(.heavy)
                    .tracking(1)
                    .foregroundColor(isArmed ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isArmed ? accentRed : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isArmed ? accentRed : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 12)
            
            // ── M (Mute) & S (Solo) Buttons ────────────────────────
            // Mitad del alto que REC, en fila horizontal.
            HStack(spacing: 4) {
                Button {
                    isMuted.toggle()
                } label: {
                    Text("M")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(isMuted ? .black : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isMuted ? accentCyan : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isMuted ? accentCyan : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                
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
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(channelNumber.isMultiple(of: 2) ? 0.02 : 0))
    }
    
    // MARK: VU Meter
    
    /// Barra vertical que representa el VU meter del canal.
    /// Placeholder estático — se llena al 40% cuando el engine está corriendo.
    private var vuMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Fondo del meter
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                
                // Nivel de relleno (estático placeholder)
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.green.opacity(0.6),
                                Color.green.opacity(0.25)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: geo.size.height * (isEngineRunning ? 0.4 : 0))
                    .animation(.easeInOut(duration: 0.4), value: isEngineRunning)
            }
        }
        .frame(width: 8, height: 60)
    }
    
    // MARK: Vertical Fader
    
    /// Fader vertical custom construido con DragGesture.
    /// Más limpio y controlable que rotar un Slider nativo.
    private var verticalFader: some View {
        GeometryReader { geo in
            let trackHeight = geo.size.height
            // Posición Y del thumb: 0 (arriba) = volumen máximo, trackHeight (abajo) = silencio
            let thumbY = (1.0 - volume) * trackHeight
            
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
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 3, height: trackHeight * volume)
                }
                
                // ── Thumb (indicador arrastrable) ──────────────────
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 28, height: 10)
                    .shadow(color: .white.opacity(0.15), radius: 4, y: 0)
                    .offset(y: thumbY - 5) // -5 para centrar el thumb (alto 10 / 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle()) // Toda el área es tappable/draggable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Convertimos la posición Y del dedo a valor de volumen (invertido)
                        let normalized = 1.0 - (value.location.y / trackHeight)
                        volume = min(max(normalized, 0), 1)
                    }
            )
        }
        .frame(width: 40)
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 8)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
