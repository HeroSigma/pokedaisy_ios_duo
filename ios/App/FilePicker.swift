import UIKit
import UniformTypeIdentifiers

/// The Files picker, presented straight from UIKit over whatever is on screen, handing back copies (asCopy) of the picked
/// files so no security-scoped access is needed. SwiftUI's fileImporter left a black screen on a sideloaded build on the
/// iPhone Duo (a player's report, 2026-11-18).
@MainActor
enum FilePicker {
    private static var delegate: Delegate?

    static func pick(types: [UTType], onPick: @escaping @MainActor ([URL]) -> Void) {
        guard let presenter = topViewController() else { return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.modalPresentationStyle = .formSheet
        let d = Delegate { urls in
            onPick(urls)
            delegate = nil
        }
        delegate = d
        picker.delegate = d
        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    @MainActor
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let done: @MainActor ([URL]) -> Void
        init(_ done: @escaping @MainActor ([URL]) -> Void) { self.done = done }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { done(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { done([]) }
    }
}
