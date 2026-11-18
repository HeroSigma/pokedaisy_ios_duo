import SwiftUI
import UIKit

/// Every orientation, on both displays. The inner display of iPhone Duo resizes the app to whatever window it gives, so the
/// app must not ask to be full screen (UIRequiresFullScreen kept it sideways there) or limit its orientations.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .all
    }
}

@main
struct PokeDaisyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = Library()
    @StateObject private var emulator = Emulator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(emulator)
                .preferredColorScheme(.dark)
                // A file opened with PokeDaisy (Files' share sheet, or a tap on a .gba): added like a picked one.
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    library.importFiles([url])
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: emulator.resume()
            // Inactive is Control Center, a notification pulled down, Siri: the game keeps running (and sounding) there,
            // so music started from Control Center doesn't stop it. Only leaving the app (background) pauses it.
            case .inactive: break
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
