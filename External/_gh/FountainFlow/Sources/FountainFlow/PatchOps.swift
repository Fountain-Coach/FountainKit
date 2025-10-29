import Foundation
import Flow

public enum FountainFlowPatchOps {
    /// Split a Flow.Patch into two patches based on a node classification.
    /// Wires crossing the partition are dropped (for now) — callers can re-synthesize them in a composed view.
    public static func split(patch: Patch, isStage: (NodeIndex) -> Bool) -> (stage: Patch, rest: Patch) {
        // Build index remaps for each side
        var stageMap: [NodeIndex: NodeIndex] = [:]
        var restMap: [NodeIndex: NodeIndex] = [:]
        var stageNodes: [Node] = []
        var restNodes: [Node] = []
        for (idx, n) in patch.nodes.enumerated() {
            if isStage(idx) { stageMap[idx] = stageNodes.count; stageNodes.append(n) }
            else { restMap[idx] = restNodes.count; restNodes.append(n) }
        }
        func remap(_ wire: Wire, using map: [NodeIndex: NodeIndex]) -> Wire? {
            guard let ni = map[wire.output.nodeIndex], let nj = map[wire.input.nodeIndex] else { return nil }
            return Wire(from: OutputID(ni, wire.output.portIndex), to: InputID(nj, wire.input.portIndex))
        }
        let stageWires = Set(patch.wires.compactMap { remap($0, using: stageMap) })
        let restWires = Set(patch.wires.compactMap { remap($0, using: restMap) })
        return (Patch(nodes: stageNodes, wires: stageWires), Patch(nodes: restNodes, wires: restWires))
    }

    /// Split plus index maps.
    /// - Returns: (stagePatch, restPatch, stageIndexMap, restIndexMap)
    ///   where maps translate subset indices -> original indices.
    public static func splitWithMaps(patch: Patch, isStage: (NodeIndex) -> Bool) -> (Patch, Patch, [NodeIndex: NodeIndex], [NodeIndex: NodeIndex]) {
        var stageMapOldToNew: [NodeIndex: NodeIndex] = [:]
        var restMapOldToNew: [NodeIndex: NodeIndex] = [:]
        var stageNodes: [Node] = []
        var restNodes: [Node] = []
        for (idx, n) in patch.nodes.enumerated() {
            if isStage(idx) { stageMapOldToNew[idx] = stageNodes.count; stageNodes.append(n) }
            else { restMapOldToNew[idx] = restNodes.count; restNodes.append(n) }
        }
        func remap(_ wire: Wire, using map: [NodeIndex: NodeIndex]) -> Wire? {
            guard let ni = map[wire.output.nodeIndex], let nj = map[wire.input.nodeIndex] else { return nil }
            return Wire(from: OutputID(ni, wire.output.portIndex), to: InputID(nj, wire.input.portIndex))
        }
        let stageWires = Set(patch.wires.compactMap { remap($0, using: stageMapOldToNew) })
        let restWires = Set(patch.wires.compactMap { remap($0, using: restMapOldToNew) })
        // Inverse maps: subset -> original
        let stageIndexMap = Dictionary(uniqueKeysWithValues: stageMapOldToNew.map { ($0.value, $0.key) })
        let restIndexMap = Dictionary(uniqueKeysWithValues: restMapOldToNew.map { ($0.value, $0.key) })
        return (Patch(nodes: stageNodes, wires: stageWires), Patch(nodes: restNodes, wires: restWires), stageIndexMap, restIndexMap)
    }
}
