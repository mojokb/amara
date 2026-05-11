import Foundation
import AppKit

/// Shared clipboard state for the file browser.
/// Tracks a pending Cut or Copy operation and performs the actual file move/copy on Paste.
final class FileBrowserClipboard: ObservableObject {
    enum Operation { case cut, copy }

    @Published private(set) var operation: Operation? = nil
    @Published private(set) var urls: [URL] = []

    var hasContent: Bool { !urls.isEmpty }

    func cut(_ url: URL) {
        operation = .cut
        urls = [url]
        writeToSystemClipboard([url])
    }

    func copy(_ url: URL) {
        operation = .copy
        urls = [url]
        writeToSystemClipboard([url])
    }

    /// Pastes into `destinationDir`. Returns the URL of the pasted item.
    @discardableResult
    func paste(into destinationDir: URL) throws -> URL? {
        guard let op = operation, let source = urls.first else { return nil }
        let dest = destinationDir.appendingPathComponent(source.lastPathComponent)
        let finalDest = uniqueDestination(dest)
        switch op {
        case .cut:
            try FileManager.default.moveItem(at: source, to: finalDest)
            clear()
        case .copy:
            try FileManager.default.copyItem(at: source, to: finalDest)
        }
        return finalDest
    }

    func clear() {
        operation = nil
        urls = []
    }

    // MARK: - Private

    private func writeToSystemClipboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
    }

    /// Appends " copy", " copy 2", etc. when destination already exists.
    private func uniqueDestination(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let ext  = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir  = url.deletingLastPathComponent()
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) copy\(n == 2 ? "" : " \(n)")"
                                   : "\(base) copy\(n == 2 ? "" : " \(n)").\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
