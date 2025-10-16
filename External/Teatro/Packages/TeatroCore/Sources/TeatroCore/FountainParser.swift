import Foundation

/// Minimal Fountain parser shim used to unblock local builds when the
/// full TeatroCore dependency is unavailable.
/// The implementation only covers the node kinds consumed by
/// PersistenceSeeder tooling and should not be considered feature complete.
public struct FountainParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> [FountainNode] {
        var nodes: [FountainNode] = []
        var previousSignificant: FountainNode.NodeType? = nil

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                previousSignificant = nil
                continue
            }

            let nodeType: FountainNode.NodeType
            if let sectionLevel = sectionLevel(for: trimmed) {
                nodeType = .section(level: sectionLevel)
            } else if isSceneHeading(trimmed) {
                nodeType = .sceneHeading
            } else if isCharacterLine(trimmed) {
                nodeType = .character
            } else if isParenthetical(trimmed) {
                nodeType = .parenthetical
            } else if shouldTreatAsDialogue(after: previousSignificant) {
                nodeType = .dialogue
            } else {
                nodeType = .action
            }

            nodes.append(FountainNode(type: nodeType, rawText: trimmed))
            if nodeType == .action {
                previousSignificant = nil
            } else {
                previousSignificant = nodeType
            }
        }

        return nodes
    }

    private func sectionLevel(for line: String) -> Int? {
        guard line.first == "#" else { return nil }
        let level = line.prefix { $0 == "#" }.count
        return max(level, 1)
    }

    private func isSceneHeading(_ line: String) -> Bool {
        line.lowercased().hasPrefix("scene")
    }

    private func isParenthetical(_ line: String) -> Bool {
        line.hasPrefix("(") && line.hasSuffix(")")
    }

    private func isCharacterLine(_ line: String) -> Bool {
        guard line.count <= 32 else { return false }
        let uppercase = line.uppercased()
        guard uppercase == line else { return false }
        return uppercase.rangeOfCharacter(from: .letters) != nil
    }

    private func shouldTreatAsDialogue(after previous: FountainNode.NodeType?) -> Bool {
        switch previous {
        case .character?, .parenthetical?, .dialogue?:
            return true
        default:
            return false
        }
    }
}

/// Simplified representation of Fountain syntax nodes consumed by the
/// persistence seeder tooling. Only the cases referenced in the main
/// workspace are modelled.
public struct FountainNode: Sendable {
    public enum NodeType: Sendable {
        case section(level: Int)
        case sceneHeading
        case character
        case parenthetical
        case dialogue
        case action
        case unknown
    }

    public let type: NodeType
    public let rawText: String

    public init(type: NodeType, rawText: String) {
        self.type = type
        self.rawText = rawText
    }
}
