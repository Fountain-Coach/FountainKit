import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum EngraverExport {
    @MainActor
    static func exportPDF(from view: NSView, suggestedName: String, completion: @escaping (Result<URL, Error>)->Void) {
        // Placeholder routing: NSView PDF fallback. When Engraver is linked, route via its pipeline.
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.pdf]
        }
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do {
                let data = view.dataWithPDF(inside: view.bounds)
                try data.write(to: url)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
