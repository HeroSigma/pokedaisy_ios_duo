import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var emulator: Emulator
    @State private var dropping = false

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty {
                    empty
                } else {
                    List(library.games) { game in
                        Button {
                            emulator.start(game)
                        } label: {
                            row(game)
                        }
                        .listRowBackground(Color(white: 0.12))
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable { library.refresh() }
                }
            }
            .background(Color(white: 0.07))
            .navigationTitle("PokeDaisy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addGames()
                    } label: {
                        Label("Add games", systemImage: "plus")
                    }
                }
            }
            .alert("Games", isPresented: Binding(get: { library.importMessage != nil }, set: { if !$0 { library.importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.importMessage ?? "")
            }
            .onDrop(of: [.fileURL, .data], isTargeted: $dropping) { providers in
                library.importDropped(providers)
            }
            .overlay {
                if dropping {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.12)))
                        .overlay(Text("Drop to add").font(.title3.bold()).foregroundStyle(.white))
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { library.refresh() }
        }
    }

    private func addGames() {
        FilePicker.pick(types: Library.importTypes) { urls in
            if !urls.isEmpty { library.importFiles(urls) }
        }
    }

    private func row(_ game: Game) -> some View {
        HStack(spacing: 12) {
            Text(game.platform)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 40, height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(game.platform == "GBA" ? Color.indigo : Color.teal))
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).foregroundStyle(.white).lineLimit(2)
                Text(game.hasSave ? "Save file found" : "No save yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.fill").foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No games yet")
                .font(.title3.bold())
            Text("Tap + or drag them in from the Files app to add your own .gba, .gb or .gbc files (and their .sav files), or put them in the Files app under On My iPhone > PokeDaisy > ROMs. No games are included.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Add games") { addGames() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
