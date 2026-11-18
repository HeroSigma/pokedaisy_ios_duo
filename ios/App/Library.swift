import Foundation
import UniformTypeIdentifiers

// The games: Documents/ROMs (visible in the Files app as On My iPhone > PokeDaisy > ROMs), each with its battery save
// beside it (<name>.sav, mGBA's layout, so a save moves to and from mGBA, RetroArch and PokeDaisy's other builds).
// Settings, states, cheats and save backups live in Documents/PokeDaisy.
struct Game: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var platform: String {
        switch url.pathExtension.lowercased() {
        case "gba": return "GBA"
        case "gbc": return "GBC"
        default: return "GB"
        }
    }
    var saveURL: URL { url.deletingPathExtension().appendingPathExtension("sav") }
    var hasSave: Bool { FileManager.default.fileExists(atPath: saveURL.path) }
}

@MainActor
final class Library: ObservableObject {
    static let extensions: Set<String> = ["gba", "gb", "gbc"]

    @Published private(set) var games: [Game] = []
    @Published var importMessage: String?

    let romsURL: URL
    let dataURL: URL
    let cacheURL: URL

    init() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        romsURL = docs.appendingPathComponent("ROMs", isDirectory: true)
        dataURL = docs.appendingPathComponent("PokeDaisy", isDirectory: true)
        cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PokeDaisy", isDirectory: true)
        for url in [romsURL, dataURL, cacheURL] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        pd_ios_init(dataURL.path, cacheURL.path)
        refresh()
    }

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: romsURL, includingPropertiesForKeys: nil)) ?? []
        games = urls
            .filter { Library.extensions.contains($0.pathExtension.lowercased()) }
            .map { Game(url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Copies picked files into ROMs (never moves or changes the originals). A file already there keeps its copy.
    func importFiles(_ urls: [URL]) {
        var added = 0, skipped: [String] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Library.extensions.contains(ext) || ext == "sav" else {
                skipped.append(url.lastPathComponent)
                continue
            }
            // The picker hands over copies (FilePicker's asCopy); one from Files' own folders may still be scoped.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let target = romsURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                // Never overwrite: a save there is the player's progress.
                skipped.append(url.lastPathComponent + " (already there)")
                continue
            }
            do {
                try FileManager.default.copyItem(at: url, to: target)
                added += 1
            } catch {
                skipped.append(url.lastPathComponent)
            }
        }
        refresh()
        var text = added == 1 ? "Added 1 file." : "Added \(added) files."
        if !skipped.isEmpty { text += "\nLeft out: " + skipped.joined(separator: ", ") }
        importMessage = text
    }

    static var importTypes: [UTType] {
        // Declared in Info.plist (UTImportedTypeDeclarations): an undeclared extension is only a dynamic type, which the
        // picker doesn't always take. Anything else (a ROM in a zip's folder, odd names) can still be picked as data.
        let ours = ["gba", "gb", "gbc", "sav"].map { UTType(importedAs: "com.pokedaisy.ios.\($0)", conformingTo: .data) }
        return ours + [.data]
    }
}
