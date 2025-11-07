import Foundation

#if canImport(QuietFrameCells)
import QuietFrameCells
public typealias AppCellsCore = QuietFrameCells.CellsCore
#else
public struct AppCellsCore: Sendable {
    public enum Rule: String, Sendable { case life, seeds, highlife, custom }
    public private(set) var width: Int
    public private(set) var height: Int
    public var wrap: Bool
    public var rule: Rule
    public var seedKind: String = "random"
    public private(set) var seedHash: String = ""
    private var grid: [UInt8]
    private var next: [UInt8]
    public init(width: Int = 64, height: Int = 40, wrap: Bool = true, ruleName: String = "life", seed: UInt64? = nil) {
        self.width = max(4, width); self.height = max(4, height); self.wrap = wrap
        self.rule = Rule(rawValue: ruleName.lowercased()) ?? .life
        self.grid = Array(repeating: 0, count: width*height); self.next = grid
        if let s = seed { reseed(seed: s) } else { reseed(seed: UInt64.random(in: 1..<UInt64.max)) }
    }
    public mutating func resize(width w: Int? = nil, height h: Int? = nil) { if let w { width = max(4, w) }; if let h { height = max(4, h) }; grid = Array(repeating: 0, count: width*height); next = grid }
    public mutating func setRule(_ name: String) { rule = Rule(rawValue: name.lowercased()) ?? .custom }
    public mutating func reseed(seed: UInt64) { seedKind = "hash"; seedHash = String(format: "%016llx", seed); grid = generateGrid(seed: seed); next = grid }
    public mutating func reseedRandom() { reseed(seed: UInt64.random(in: 1..<UInt64.max)) }
    private func idx(_ x: Int, _ y: Int) -> Int { y*width + x }
    private func alive(_ x: Int, _ y: Int) -> UInt8 {
        var xx = x, yy = y
        if wrap { if xx < 0 { xx += width }; if xx >= width { xx -= width }; if yy < 0 { yy += height }; if yy >= height { yy -= height } }
        if xx < 0 || xx >= width || yy < 0 || yy >= height { return 0 }
        return grid[idx(xx,yy)] > 0 ? 1 : 0
    }
    private func neighbors(_ x: Int, _ y: Int) -> Int { var n=0; for dy in -1...1 { for dx in -1...1 { if dx != 0 || dy != 0 { n += Int(alive(x+dx,y+dy)) } } }; return n }
    private func ruleLive(a: Bool, n: Int) -> Bool { switch rule { case .life: return (a && (n==2||n==3)) || (!a && n==3); case .seeds: return (!a && n==2); case .highlife: return (a && (n==2||n==3)) || (!a && (n==3||n==6)); case .custom: return (a && (n==2||n==3)) || (!a && n==3) } }
    public mutating func tick() -> [(Int,Int,Int)] { var births:[(Int,Int,Int)]=[]; for y in 0..<height { for x in 0..<width { let a = grid[idx(x,y)]>0; let n = neighbors(x,y); let live = ruleLive(a:a,n:n); if live { let age = min(250, Int(grid[idx(x,y)])+1); next[idx(x,y)] = UInt8(age); if !a { births.append((x,y,n)) } } else { next[idx(x,y)] = 0 } } } ; grid = next; return births }
    public var density: Double { Double(grid.reduce(0) { $0 + ($1>0 ? 1 : 0) }) / Double(max(1, width*height)) }
    public var stateHash: String { var h:UInt64=1469598103934665603; for v in grid { h ^= UInt64(v); h &*= 1099511628211 }; return String(format: "%016llx", h) }
    public func snapshotNumeric() -> [String: Double] { ["cells.grid.width": Double(width), "cells.grid.height": Double(height), "cells.grid.wrap": wrap ? 1.0 : 0.0, "cells.state.density": density] }
    public func snapshotStrings() -> [String: String] { ["cells.rule.name": rule.rawValue, "cells.seed.kind": seedKind, "cells.seed.hash": seedHash, "cells.state.hash": stateHash] }
    public func forEachAlive(_ body: (Int,Int,UInt8)->Void) { for y in 0..<height { for x in 0..<width { let age = grid[idx(x,y)]; if age>0 { body(x,y,age) } } } }
    private func generateGrid(seed: UInt64) -> [UInt8] { var rng=seed; func next32()->UInt32 { rng = rng &* 6364136223846793005 &+ 1; return UInt32(truncatingIfNeeded: (rng>>32)) }; var out=[UInt8](repeating:0,count:width*height); for i in 0..<out.count { out[i] = ((next32() & 1) == 1) ? 1 : 0 }; return out }
}
#endif

