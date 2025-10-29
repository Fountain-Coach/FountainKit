import Foundation
import CoreGraphics
import Flow

/// FountainFlow — initial surface.
///
/// Goal: provide per-node style and rect providers on top of Flow, evolving to a native editor.
public enum FountainFlowAPI {
    /// Marker type for the package; expanded as we migrate.
}

/// A node kind hint for conditional body/port rendering.
public enum NodeKindHint: Equatable {
    case stage
    case generic
}

/// Per-node style provider surface (v0 draft).
public protocol NodeStyleProvider {
    func drawBody(for index: Int) -> Bool
    func nodeKind(for index: Int) -> NodeKindHint
}

/// Per-node rect provider surface (v0 draft).
public protocol NodeRectProvider {
    /// Returns the rect for the node body in document coordinates.
    func nodeRect(for index: Int) -> CGRect
    /// Returns the input port rect for a given input index in document coordinates.
    func inputRect(for index: Int, input: Int) -> CGRect
    /// Returns the output port rect for a given output index in document coordinates.
    func outputRect(for index: Int, output: Int) -> CGRect
}

