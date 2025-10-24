import Foundation
import Metal

public final class MPSGraphFacade {
    public init?() { return nil }
    // Keep interface available so callers compile even when facade is unavailable.
    public func matmul(a: [Float], m: Int, k: Int, b: [Float], n: Int) -> [Float] { return [] }
}
