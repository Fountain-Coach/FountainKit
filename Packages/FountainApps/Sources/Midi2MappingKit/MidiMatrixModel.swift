import Foundation
import SwiftUI

public struct MidiRouteFilters: Hashable, Codable { public var cv2: Bool = true; public var m1: Bool = true; public var pe: Bool = true; public var utility: Bool = true; public init() {} }
public struct MidiRouteParams: Hashable, Codable { public var channelMaskAll: Bool = true; public var channels: Set<Int> = []; public var group: Int = 0; public var filters: MidiRouteFilters = .init(); public init() {} }

public final class MidiMatrixModel: ObservableObject {
    public struct RouteKey: Hashable { public var row: Int; public var col: Int; public init(row: Int, col: Int) { self.row=row; self.col=col } }
    @Published public var sources: [String]
    @Published public var destinations: [String]
    @Published public var routes: Set<RouteKey>
    @Published public var selected: RouteKey? = nil
    @Published public var params: [RouteKey: MidiRouteParams] = [:]
    // Optional validator for cells; when nil, all cells are valid.
    public var isCellValid: ((RouteKey) -> Bool)? = nil
    public init(sources: [String], destinations: [String], routes: Set<RouteKey> = []) {
        self.sources = sources; self.destinations = destinations; self.routes = routes
    }
    public func isOn(_ k: RouteKey) -> Bool { routes.contains(k) }
    public func toggle(_ k: RouteKey) { if routes.contains(k) { routes.remove(k) } else { routes.insert(k) } }
    public func set(_ k: RouteKey, on: Bool) { if on { routes.insert(k) } else { routes.remove(k) } }
    public func params(for k: RouteKey) -> MidiRouteParams { params[k] ?? MidiRouteParams() }
    public func setParams(_ p: MidiRouteParams, for k: RouteKey) { params[k] = p }
}
