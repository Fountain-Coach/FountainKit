import Foundation
import CoreGraphics
import Flow

@MainActor
struct FlowBridge {
    static func portType(from pb: String) -> PortType {
        switch pb { case "ump": return .midi; case "data": return .control; default: return .control }
    }

    static func toFlowPatch(vm: EditorVM) -> Patch { toFlowPatch(vm: vm, titleFor: { $0.title ?? $0.id }) }

    static func toFlowPatch(vm: EditorVM, titleFor: (PBNode) -> String) -> Patch {
        let nodes: [Flow.Node] = vm.nodes.enumerated().map { idx, n in
            let inputs = canonicalSortPorts(n.ports.filter { $0.dir == .input }).map { Flow.Port(name: $0.id, type: portType(from: $0.type)) }
            let outputs = canonicalSortPorts(n.ports.filter { $0.dir == .output }).map { Flow.Port(name: $0.id, type: portType(from: $0.type)) }
            return Flow.Node(name: titleFor(n),
                             position: CGPoint(x: n.x, y: n.y),
                             inputs: inputs,
                             outputs: outputs)
        }
        // Be tolerant of duplicate node ids (should not happen, but avoid traps): last wins
        let indexById = Dictionary(vm.nodes.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { _, new in new })
        var wires = Set<Wire>()
        for e in vm.edges {
            let partsF = e.from.split(separator: ".", maxSplits: 1).map(String.init)
            let partsT = e.to.split(separator: ".", maxSplits: 1).map(String.init)
            guard partsF.count == 2, partsT.count == 2,
                  let ni = indexById[partsF[0]], let nj = indexById[partsT[0]],
                  let outIdx = nodes[ni].outputs.firstIndex(where: { $0.name == partsF[1] }),
                  let inIdx = nodes[nj].inputs.firstIndex(where: { $0.name == partsT[1] }) else { continue }
            wires.insert(Wire(from: OutputID(ni, outIdx), to: InputID(nj, inIdx)))
        }
        return Patch(nodes: nodes, wires: wires)
    }

    static func fromFlowPatch(_ patch: Patch, into vm: EditorVM) {
        guard patch.nodes.count == vm.nodes.count else { return }
        for i in 0..<patch.nodes.count {
            let p = patch.nodes[i]
            vm.nodes[i].x = Int(p.position.x)
            vm.nodes[i].y = Int(p.position.y)
        }
        // Edges are handled via onWireAdded/Removed callbacks instead of full diff here.
    }
}
