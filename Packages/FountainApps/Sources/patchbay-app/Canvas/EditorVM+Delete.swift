import Foundation

extension EditorVM {
    // Delete nodes and incident edges; clear selection
    func deleteNodes(ids: Set<String>) {
        if ids.isEmpty { return }
        nodes.removeAll { ids.contains($0.id) }
        edges.removeAll { edge in
            let fromNode = edge.from.split(separator: ".").first.map(String.init) ?? ""
            let toNode = edge.to.split(separator: ".").first.map(String.init) ?? ""
            return ids.contains(fromNode) || ids.contains(toNode)
        }
        if let sel = selection, ids.contains(sel) { selection = nil }
        selected.removeAll()
    }
}

