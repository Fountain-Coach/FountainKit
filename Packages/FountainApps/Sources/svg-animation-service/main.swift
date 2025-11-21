import Foundation
import FountainRuntime
import SVGAnimationKit
import LauncherSignature

/// SVG Animation Renderer Instrument service.
/// Thin HTTP wrapper around SVGAnimationKit implementing `svg-animation.yml`.
@main
enum SVGAnimationServiceMain {
    static func main() async {
        let env = ProcessInfo.processInfo.environment
        if env["FOUNTAIN_SKIP_LAUNCHER_SIG"] != "1" {
            verifyLauncherSignature()
        }

        let kernel = HTTPKernel { req in
            await handle(request: req)
        }
        let server = NIOHTTPServer(kernel: kernel)

        do {
            let port = Int(env["SVG_ANIMATION_PORT"] ?? env["PORT"] ?? "8091") ?? 8091
            _ = try await server.start(port: port)
            print("svg-animation-service listening on :\(port)")
        } catch {
            let msg = "[svg-animation] failed to start: \(error)\n"
            FileHandle.standardError.write(Data(msg.utf8))
            exit(2)
        }

        dispatchMain()
    }

    /// Top-level router for the service.
    private static func handle(request: HTTPRequest) async -> HTTPResponse {
        // Serve the curated OpenAPI spec.
        if request.method == "GET" && request.path == "/openapi.yaml" {
            let url = URL(fileURLWithPath: "Packages/FountainSpecCuration/openapi/v1/svg-animation.yml")
            if let data = try? Data(contentsOf: url) {
                return HTTPResponse(status: 200, headers: ["Content-Type": "application/yaml"], body: data)
            }
            return HTTPResponse(status: 404)
        }

        // Simple liveness metric.
        if request.method == "GET" && request.path == "/metrics" {
            let body = Data("svg_animation_up 1\n".utf8)
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: body)
        }

        // Core instrument endpoints.
        if request.method == "POST" && request.path == "/svg/scene" {
            return handleRenderScene(request: request)
        }
        if request.method == "POST" && request.path == "/svg/scene/frames" {
            return handleRenderFrames(request: request)
        }

        return HTTPResponse(status: 404)
    }

    /// Renders a single SVG scene.
    private static func handleRenderScene(request: HTTPRequest) -> HTTPResponse {
        guard let obj = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            return error(status: 400, reason: "invalid JSON body")
        }
        guard let scene = decodeScene(from: obj) else {
            return error(status: 400, reason: "invalid scene description")
        }
        let svg = SVGRenderer.render(scene: scene)
        return HTTPResponse(
            status: 200,
            headers: ["Content-Type": "image/svg+xml; charset=utf-8"],
            body: Data(svg.utf8)
        )
    }

    /// Renders a sequence of SVG scenes from a scalar timeline.
    private static func handleRenderFrames(request: HTTPRequest) -> HTTPResponse {
        guard let obj = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            return error(status: 400, reason: "invalid JSON body")
        }
        guard let sceneObj = obj["scene"] as? [String: Any],
              let scene = decodeScene(from: sceneObj),
              let timelineObj = obj["timeline"] as? [String: Any],
              let fps = obj["fps"] as? Double, fps >= 1
        else {
            return error(status: 400, reason: "invalid scene/timeline/fps")
        }

        guard let timeline = decodeTimeline(from: timelineObj) else {
            return error(status: 400, reason: "invalid timeline description")
        }

        let frames = AnimationFrames.renderScenes(baseScene: scene, timeline: timeline, fps: fps) { base, _ in
            base
        }
        let svgs = frames.map { SVGRenderer.render(scene: $0) }
        let payload: [String: Any] = ["frames": svgs]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return HTTPResponse(
            status: 200,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    /// Helper to emit error responses as JSON.
    private static func error(status: Int, reason: String) -> HTTPResponse {
        let obj: [String: Any] = ["error": status, "message": reason]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    /// Decodes an SVGScene from the OpenAPI-aligned JSON representation.
    private static func decodeScene(from obj: [String: Any]) -> SVGScene? {
        guard let width = obj["width"] as? Double,
              let height = obj["height"] as? Double,
              let nodeArray = obj["nodes"] as? [[String: Any]]
        else { return nil }

        let background = obj["background"] as? String
        var nodes: [SVGNode] = []
        for entry in nodeArray {
            guard let kind = entry["kind"] as? String else { continue }
            switch kind {
            case "rect":
                if let rectObj = entry["rect"] as? [String: Any],
                   let x = rectObj["x"] as? Double,
                   let y = rectObj["y"] as? Double,
                   let w = rectObj["width"] as? Double,
                   let h = rectObj["height"] as? Double {
                    let fill = rectObj["fill"] as? String
                    let stroke = rectObj["stroke"] as? String
                    let strokeWidth = rectObj["strokeWidth"] as? Double
                    nodes.append(.rect(SVGRect(x: x, y: y, width: w, height: h, fill: fill, stroke: stroke, strokeWidth: strokeWidth)))
                }
            case "circle":
                if let circleObj = entry["circle"] as? [String: Any],
                   let cx = circleObj["cx"] as? Double,
                   let cy = circleObj["cy"] as? Double,
                   let r = circleObj["r"] as? Double {
                    let fill = circleObj["fill"] as? String
                    let stroke = circleObj["stroke"] as? String
                    let strokeWidth = circleObj["strokeWidth"] as? Double
                    nodes.append(.circle(SVGCircle(cx: cx, cy: cy, r: r, fill: fill, stroke: stroke, strokeWidth: strokeWidth)))
                }
            case "text":
                if let textObj = entry["text"] as? [String: Any],
                   let x = textObj["x"] as? Double,
                   let y = textObj["y"] as? Double,
                   let content = textObj["content"] as? String {
                    let fill = textObj["fill"] as? String
                    let fontSize = textObj["fontSize"] as? Double
                    nodes.append(.text(SVGText(x: x, y: y, content: content, fill: fill, fontSize: fontSize)))
                }
            case "path":
                if let pathObj = entry["path"] as? [String: Any],
                   let cmds = pathObj["commands"] as? [[String: Any]] {
                    var commands: [SVGPathCommand] = []
                    for c in cmds {
                        guard let cKind = c["kind"] as? String else { continue }
                        switch cKind {
                        case "moveTo":
                            if let x = c["x"] as? Double, let y = c["y"] as? Double {
                                commands.append(.moveTo(x: x, y: y))
                            }
                        case "lineTo":
                            if let x = c["x"] as? Double, let y = c["y"] as? Double {
                                commands.append(.lineTo(x: x, y: y))
                            }
                        case "quadTo":
                            if let cx = c["cx"] as? Double,
                               let cy = c["cy"] as? Double,
                               let x = c["x"] as? Double,
                               let y = c["y"] as? Double {
                                commands.append(.quadTo(cx: cx, cy: cy, x: x, y: y))
                            }
                        case "cubicTo":
                            if let cx1 = c["cx1"] as? Double,
                               let cy1 = c["cy1"] as? Double,
                               let cx2 = c["cx2"] as? Double,
                               let cy2 = c["cy2"] as? Double,
                               let x = c["x"] as? Double,
                               let y = c["y"] as? Double {
                                commands.append(.cubicTo(cx1: cx1, cy1: cy1, cx2: cx2, cy2: cy2, x: x, y: y))
                            }
                        case "close":
                            commands.append(.close)
                        default:
                            break
                        }
                    }
                    let fill = pathObj["fill"] as? String
                    let stroke = pathObj["stroke"] as? String
                    let strokeWidth = pathObj["strokeWidth"] as? Double
                    nodes.append(.path(SVGPath(commands: commands, fill: fill, stroke: stroke, strokeWidth: strokeWidth)))
                }
            default:
                continue
            }
        }
        return SVGScene(width: width, height: height, background: background, nodes: nodes)
    }

    /// Decodes a scalar animation timeline from JSON.
    private static func decodeTimeline(from obj: [String: Any]) -> AnimationTimeline1D? {
        guard let duration = obj["duration"] as? Double,
              let tracksObj = obj["tracks"] as? [String: Any]
        else { return nil }

        var tracks: [String: AnimationCurve1D] = [:]
        for (name, value) in tracksObj {
            guard let curveObj = value as? [String: Any],
                  let keyframesArray = curveObj["keyframes"] as? [[String: Any]] else {
                continue
            }
            var frames: [Keyframe1D] = []
            for k in keyframesArray {
                if let t = k["time"] as? Double,
                   let v = k["value"] as? Double {
                    frames.append(Keyframe1D(time: t, value: v))
                }
            }
            if !frames.isEmpty {
                tracks[name] = AnimationCurve1D(keyframes: frames)
            }
        }
        return AnimationTimeline1D(duration: duration, tracks: tracks)
    }
}

