//
//  TapesLibraryView.swift
//  Taper
//
//  Created by Jose maria Martinez marconi on 15/10/2026.
//

import SwiftUI

/// Vista de biblioteca de cintas (proyectos) estilo "cajón de cassettes".
///
/// Presenta una lista de todos los proyectos guardados con nombre y fecha,
/// permite cargar un proyecto existente o crear uno nuevo con un nombre personalizado.
struct TapesLibraryView: View {
    
    @ObservedObject var audioManager: AudioManager
    @Environment(\.dismiss) private var dismiss
    
    /// Controla la visibilidad del alert para crear un nuevo tape.
    @State private var showNewTapeAlert: Bool = false
    
    /// Nombre ingresado por el usuario para el nuevo tape.
    @State private var newTapeName: String = ""
    
    /// Controla la visibilidad del alert para renombrar un tape existente.
    @State private var showRenameAlert: Bool = false
    
    /// Tape que se va a renombrar actualmente.
    @State private var tapeToRename: TapeProject?
    
    /// Texto para el nuevo nombre al renombrar un tape.
    @State private var renameTapeText: String = ""
    
    /// Formateador de fecha para mostrar en la lista.
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fondo oscuro estilo consola
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // ── Header con botón de nuevo tape ──────────────
                    createNewTapeButton
                    
                    Divider()
                        .background(Color.white.opacity(0.08))
                    
                    // ── Lista de tapes guardados ─────────────────────
                    if audioManager.savedTapes.isEmpty {
                        emptyLibraryView
                    } else {
                        tapesList
                    }
                }
            }
            .navigationTitle("My Tapes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .semibold))
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("New Tape", isPresented: $showNewTapeAlert) {
                TextField("Tape name", text: $newTapeName)
                Button("Create") {
                    let name = newTapeName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    audioManager.createNewTape(name: name)
                    newTapeName = ""
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    newTapeName = ""
                }
            } message: {
                Text("Enter a name for your new tape.")
            }
            .alert("Rename Tape", isPresented: $showRenameAlert) {
                TextField("Tape name", text: $renameTapeText)
                Button("Save") {
                    let name = renameTapeText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, let tape = tapeToRename else { return }
                    audioManager.renameTape(project: tape, newName: name)
                    tapeToRename = nil
                    renameTapeText = ""
                }
                Button("Cancel", role: .cancel) {
                    tapeToRename = nil
                    renameTapeText = ""
                }
            } message: {
                Text("Enter a new name for this tape.")
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Subviews

private extension TapesLibraryView {
    
    /// Botón para crear un nuevo tape en la parte superior.
    var createNewTapeButton: some View {
        Button {
            showNewTapeAlert = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("CREATE NEW TAPE")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white)
                    
                    Text("Start a fresh 4-track recording")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.03))
        }
    }
    
    /// Vista cuando la biblioteca está vacía.
    var emptyLibraryView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "opticaldisc")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.3))
            
            Text("No tapes yet")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Create your first tape to start recording.")
                .font(.system(size: 13))
                .foregroundColor(.gray.opacity(0.35))
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    /// Lista de proyectos guardados con acciones de carga, renombrado y eliminación.
    var tapesList: some View {
        List {
            ForEach(audioManager.savedTapes) { tape in
                tapeRow(tape: tape)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        audioManager.loadTape(project: tape)
                        dismiss()
                    }
                    .listRowBackground(
                        tape.id == audioManager.currentTape?.id
                            ? Color.white.opacity(0.06)
                            : Color.clear
                    )
                    .swipeActions(edge: .leading) {
                        Button {
                            tapeToRename = tape
                            renameTapeText = tape.name
                            showRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(Color(red: 1.0, green: 0.6, blue: 0.2))
                    }
                    .contextMenu {
                        Button {
                            tapeToRename = tape
                            renameTapeText = tape.name
                            showRenameAlert = true
                        } label: {
                            Label("Rename Tape", systemImage: "pencil")
                        }
                        
                        if tape.id != audioManager.currentTape?.id {
                            Button(role: .destructive) {
                                audioManager.deleteTape(project: tape)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
            }
            .onDelete(perform: deleteTapes)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    /// Fila individual de un tape en la lista.
    func tapeRow(tape: TapeProject) -> some View {
        HStack(spacing: 14) {
            // Icono de cassette
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        tape.id == audioManager.currentTape?.id
                            ? Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.15)
                            : Color.white.opacity(0.06)
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: "cassette.fill")
                    .font(.system(size: 16))
                    .foregroundColor(
                        tape.id == audioManager.currentTape?.id
                            ? Color(red: 0.3, green: 0.85, blue: 0.45)
                            : .gray
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Nombre del tape (tocable para renombrar manualmente)
                HStack(spacing: 6) {
                    Button {
                        tapeToRename = tape
                        renameTapeText = tape.name
                        showRenameAlert = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(tape.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                    .buttonStyle(.borderless)
                    
                    // Badge de "activo" si es el proyecto cargado
                    if tape.id == audioManager.currentTape?.id {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.45))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(red: 0.3, green: 0.85, blue: 0.45).opacity(0.15))
                            )
                    }
                }
                
                // Fecha de creación + conteo de pistas con audio
                HStack(spacing: 8) {
                    Text(dateFormatter.string(from: tape.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    let tracksWithAudio = tape.tracks.filter { $0.fileURL != nil }.count
                    if tracksWithAudio > 0 {
                        Text("•  \(tracksWithAudio)/4 tracks")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray.opacity(0.3))
        }
        .padding(.vertical, 4)
    }
    
    /// Elimina tapes de la biblioteca por índice (swipe-to-delete).
    func deleteTapes(at offsets: IndexSet) {
        for index in offsets {
            let tape = audioManager.savedTapes[index]
            // No permitir eliminar el tape activo
            if tape.id != audioManager.currentTape?.id {
                audioManager.deleteTape(project: tape)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TapesLibraryView(audioManager: AudioManager())
}
