import Foundation
import MetalViewKit
import SDLKit
import FountainStoreClient
#if canImport(CSDL3)
import CSDL3
#endif

@main
@MainActor
struct InfinityApp {
    static func main() {
        Task.detached {
            await printPromptIfAvailable()
        }
        do {
            let width = 1440
            let height = 900
            let window = SDLWindow(config: .init(title: "Infinity", width: width, height: height))
            try window.open()
            try window.show()
            let renderer = try SDLRenderer(width: width, height: height, window: window)

            var scene = InfinityScene()
            scene.grid = 24
            var camera = Canvas2D(zoom: Canvas2D.defaultZoom, translation: Canvas2D.defaultTranslation)

            var running = true
            let fps: Double = 60
            let frameTime: useconds_t = useconds_t(1_000_000.0 / fps)

            #if canImport(CSDL3)
            var lastMousePosition = CGPoint.zero
            var hasMousePosition = false
            var draggingNodeId: String?
            var isPanning = false
            var isZooming = false
            var zoomAnchorViewPoint = CGPoint.zero
            var zoomStartY: CGFloat = 0
            #endif

            while running {
                #if canImport(CSDL3)
                var event = SDLKit_Event(type: 0, x: 0, y: 0, keycode: 0, button: 0)
                while SDLKit_PollEvent(&event) != 0 {
                    let type = Int32(bitPattern: event.type)
                    switch type {
                    case Int32(SDLKIT_EVENT_QUIT),
                         Int32(SDLKIT_EVENT_WINDOW_CLOSED):
                        running = false
                    case Int32(SDLKIT_EVENT_MOUSE_DOWN):
                        let pos = CGPoint(x: CGFloat(event.x), y: CGFloat(event.y))
                        lastMousePosition = pos
                        hasMousePosition = true
                        let docPoint = camera.viewToDoc(pos)
                        if event.button == 1 {
                            if let hit = hitTestNode(at: docPoint, in: scene) {
                                scene.selection = [hit.id]
                                draggingNodeId = hit.id
                            } else {
                                scene.selection = []
                                isPanning = true
                            }
                        } else if event.button == 3 {
                            isZooming = true
                            zoomAnchorViewPoint = pos
                            zoomStartY = pos.y
                        }
                    case Int32(SDLKIT_EVENT_MOUSE_UP):
                        if event.button == 1 {
                            draggingNodeId = nil
                            isPanning = false
                        } else if event.button == 3 {
                            isZooming = false
                        }
                        hasMousePosition = false
                    case Int32(SDLKIT_EVENT_MOUSE_MOVE):
                        let pos = CGPoint(x: CGFloat(event.x), y: CGFloat(event.y))
                        if hasMousePosition {
                            let dx = pos.x - lastMousePosition.x
                            let dy = pos.y - lastMousePosition.y
                            let deltaView = CGSize(width: dx, height: dy)
                            if let id = draggingNodeId {
                                let scale = max(0.0001, camera.zoom)
                                let deltaDoc = CGPoint(x: deltaView.width / scale, y: deltaView.height / scale)
                                scene = scene.movingNode(id: id, by: deltaDoc)
                            } else if isPanning {
                                camera.panBy(viewDelta: deltaView)
                            } else if isZooming {
                                let dyTotal = pos.y - zoomStartY
                                let magnification = -dyTotal * 0.002
                                camera.zoomAround(viewAnchor: zoomAnchorViewPoint, magnification: magnification)
                            }
                        }
                        lastMousePosition = pos
                        hasMousePosition = true
                    default:
                        break
                    }
                }
                #endif

                try renderer.clear(color: 0xFF101010)
                drawGrid(renderer: renderer, camera: camera, grid: scene.grid, width: width, height: height)

                if scene.nodes.isEmpty {
                    scene = scene.addingNode(at: CGPoint(x: 200, y: 200), baseTitle: "Node")
                }
                drawNodes(renderer: renderer, scene: scene, camera: camera)

                renderer.present()
                usleep(frameTime)
            }

            renderer.shutdown()
            window.close()
        } catch {
            fputs("Infinity failed: \(error)\n", stderr)
        }
    }

    private static func printPromptIfAvailable() async {
        let env = ProcessInfo.processInfo.environment
        let root: URL
        if let dir = env["FOUNTAINSTORE_DIR"], !dir.isEmpty {
            if dir.hasPrefix("/") {
                root = URL(fileURLWithPath: dir, isDirectory: true)
            } else {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                root = cwd.appendingPathComponent(dir, isDirectory: true)
            }
        } else {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            root = cwd.appendingPathComponent(".fountain/store", isDirectory: true)
        }

        let client: FountainStoreClient
        if let disk = try? DiskFountainStoreClient(rootDirectory: root) {
            client = FountainStoreClient(client: disk)
        } else {
            client = FountainStoreClient(client: EmbeddedFountainStoreClient())
        }

        let corpusId = "infinity"
        let segmentId = "prompt:infinity:teatro"
        do {
            if let data = try await client.getDoc(corpusId: corpusId, collection: "segments", id: segmentId) {
                if let segment = try? JSONDecoder().decode(Segment.self, from: data) {
                    print("\n=== Teatro Prompt (\(corpusId)) ===\n\(segment.text)\n=== end prompt ===\n")
                } else if let raw = String(data: data, encoding: .utf8) {
                    print("\n=== Teatro Prompt (\(corpusId)) (raw) ===\n\(raw)\n=== end prompt ===\n")
                }
            } else {
                fputs("[infinity] prompt segment '\(segmentId)' not found in corpus '\(corpusId)'. Seed via Scripts/apps/infinity-seed.\n", stderr)
            }
        } catch {
            fputs("[infinity] error reading prompt from FountainStore: \(error)\n", stderr)
        }
    }

    private static func drawGrid(renderer: SDLRenderer, camera: Canvas2D, grid: Int, width: Int, height: Int) {
        let stepDoc = CGFloat(max(grid, 1))
        let docX0 = camera.viewToDoc(CGPoint(x: 0, y: 0)).x
        let docX1 = camera.viewToDoc(CGPoint(x: CGFloat(width), y: 0)).x
        let docY0 = camera.viewToDoc(CGPoint(x: 0, y: 0)).y
        let docY1 = camera.viewToDoc(CGPoint(x: 0, y: CGFloat(height))).y

        func alignedStart(_ v: CGFloat) -> CGFloat {
            let k = floor(v / stepDoc)
            return k * stepDoc
        }

        let gridColorMinor: UInt32 = 0xFF2A2A2A

        var xDoc = alignedStart(docX0)
        while xDoc <= docX1 {
            let vx = camera.docToView(CGPoint(x: xDoc, y: 0)).x
            let ix = Int(vx.rounded())
            try? renderer.drawLine(x1: ix, y1: 0, x2: ix, y2: height, color: gridColorMinor)
            xDoc += stepDoc
        }

        var yDoc = alignedStart(docY0)
        while yDoc <= docY1 {
            let vy = camera.docToView(CGPoint(x: 0, y: yDoc)).y
            let iy = Int(vy.rounded())
            try? renderer.drawLine(x1: 0, y1: iy, x2: width, y2: iy, color: gridColorMinor)
            yDoc += stepDoc
        }
    }

    private static func drawNodes(renderer: SDLRenderer, scene: InfinityScene, camera: Canvas2D) {
        let nodeColor: UInt32 = 0xFF3A82F7
        for node in scene.nodes {
            let rectDoc = node.frame
            let originView = camera.docToView(CGPoint(x: rectDoc.minX, y: rectDoc.minY))
            let sizeView = CGSize(width: rectDoc.width * camera.zoom, height: rectDoc.height * camera.zoom)
            let x = Int(originView.x.rounded())
            let y = Int(originView.y.rounded())
            let w = Int(sizeView.width.rounded())
            let h = Int(sizeView.height.rounded())
            try? renderer.drawRectangle(x: x, y: y, width: w, height: h, color: nodeColor)
        }
    }

    private static func hitTestNode(at docPoint: CGPoint, in scene: InfinityScene) -> InfinityNode? {
        for node in scene.nodes.reversed() {
            if node.frame.contains(docPoint) {
                return node
            }
        }
        return nil
    }
}
