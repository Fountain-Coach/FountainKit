// TeatroStageScene — renderer-agnostic Teatro engine model for MetalViewKit

#if canImport(CoreGraphics)
import Foundation
import CoreGraphics

public struct TeatroVec3: Sendable, Equatable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
    public init(x: CGFloat, y: CGFloat, z: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct TeatroCameraState: Sendable, Equatable {
    public var azimuth: CGFloat
    public var zoom: CGFloat
    public init(azimuth: CGFloat, zoom: CGFloat) {
        self.azimuth = azimuth
        self.zoom = zoom
    }
}

public enum TeatroLightType: String, Sendable {
    case spot
    case wash
    case backlight
}

public struct TeatroLight: Sendable, Equatable {
    public var id: String
    public var type: TeatroLightType
    public var origin: TeatroVec3
    public var target: TeatroVec3
    public var radius: CGFloat
    public var intensity: CGFloat
    public var label: String?
    public init(id: String,
                type: TeatroLightType,
                origin: TeatroVec3,
                target: TeatroVec3,
                radius: CGFloat,
                intensity: CGFloat,
                label: String? = nil) {
        self.id = id
        self.type = type
        self.origin = origin
        self.target = target
        self.radius = radius
        self.intensity = intensity
        self.label = label
    }
}

public struct TeatroRep: Sendable, Equatable {
    public var id: String
    public var position: TeatroVec3
    public var roleLabel: String?
    public init(id: String, position: TeatroVec3, roleLabel: String? = nil) {
        self.id = id
        self.position = position
        self.roleLabel = roleLabel
    }
}

public struct TeatroStageSnapshot: Sendable, Equatable {
    public var time: TimeInterval
    public var camera: TeatroCameraState
    public var reps: [TeatroRep]
    public var lights: [TeatroLight]
    public init(time: TimeInterval,
                camera: TeatroCameraState,
                reps: [TeatroRep],
                lights: [TeatroLight]) {
        self.time = time
        self.camera = camera
        self.reps = reps
        self.lights = lights
    }
}

public struct TeatroStageScene: Sendable {
    public var camera: TeatroCameraState
    public var roomSize: TeatroVec3
    public var reps: [TeatroRep]
    public var lights: [TeatroLight]
    public var snapshots: [TeatroStageSnapshot]
    public init(camera: TeatroCameraState,
                roomSize: TeatroVec3,
                reps: [TeatroRep] = [],
                lights: [TeatroLight] = [],
                snapshots: [TeatroStageSnapshot] = []) {
        self.camera = camera
        self.roomSize = roomSize
        self.reps = reps
        self.lights = lights
        self.snapshots = snapshots
    }
}

#endif

