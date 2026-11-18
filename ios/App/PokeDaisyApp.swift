import SwiftUI

@main
struct PokeDaisyApp: App {
    @StateObject private var library = Library()
    @StateObject private var emulator = Emulator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(emulator)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: emulator.resume()
            case .inactive: emulator.pause()
            case .background:
                emulator.pause()
                emulator.flushSave()
            @unknown default: break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var emulator: Emulator
    @EnvironmentObject var library: Library

    var body: some View {
        ZStack {
            if emulator.running {
                GameScreen()
                    .transition(.opacity)
            } else {
                LibraryView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: emulator.running)
        .alert("The game didn't start", isPresented: $emulator.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(emulator.errorText)
        }
    }
}
