import Foundation
import FountainStoreClient

@main
struct InfinitySeedMain {
    static func main() async {
        let appId = "infinity"

        let teatroPrompt = """
        Scene: Infinity — Canvas-Only PatchBay Canvas

        Text:
        - Host: a single SDLKit window titled “Infinity” on macOS. The window behaves like a normal app window (title bar, Cmd+Q, fullscreen), but all interactive content is a single infinite canvas; there are no left/right panes, lists, or monitors.
        - Canvas: an infinite 2D workspace backed by the shared Canvas2D transform. The canvas fills the entire content area of the window; there is no surrounding chrome. The document-space origin (0,0) is visible when zoom=1 and translation=(0,0), and the grid math matches PatchBay’s center canvas.
        - Grid: minor grid spacing is `grid.minor` document units (default 24). Major lines appear every `grid.majorEvery` minor steps (default 5). At zoom=1, a minor step is 24 px; a major step is 24×5=120 px. The grid scrolls under the viewport; there is no fixed background.
        - Nodes: Infinity shows at least one rectangular node on the canvas. Nodes live in document space, can be selected, and can be dragged; they do not introduce additional panes or toolbars. Ports and edges are part of the graph model but may be visually minimal or omitted in the first version.

        Camera and Input:
        - Transform core: Infinity uses Canvas2D as the single source of truth for doc↔view transforms. All pan/zoom behaviour is expressed in terms of `Canvas2D.docToView`, `Canvas2D.viewToDoc`, `Canvas2D.panBy`, and `Canvas2D.zoomAround`.
        - Pan (mouse): dragging with the primary mouse button on empty canvas pans the view. The drag delta in view space is mapped to a document-space translation via Canvas2D, so the cursor “follows” the content under your finger.
        - Pan (nodes): dragging with the primary mouse button on a node moves that node in document space instead of panning the whole canvas.
        - Zoom (mouse): dragging with a secondary button (or an equivalent gesture) vertically near a point performs anchor-stable zoom via `Canvas2D.zoomAround(viewAnchor:magnification:)`. Moving up zooms in; moving down zooms out.
        - Bounds: zoom is clamped to [0.25, 3.0] via Canvas2D; translation is unconstrained in document space.

        Input/Focus Model (v1):
        - Single focus owner: the Infinity canvas is the only interactive surface in the window. When the Infinity window is active, all pointer and keyboard events are considered to target the canvas; there are no hidden text fields or secondary focus targets.
        - Keyboard (v1): keyboard shortcuts are reserved for pan/zoom/tools in future revisions; the initial version may be mouse-only. When text tools are introduced, typed characters will always go to the currently active tool on the canvas, not to any OS-level text boxes.
        - No soft focus traps: there are no overlapping controls that can capture focus accidentally; selection is explicit (nodes) and everything else is canvas.

        Properties (PE / OpenAPI surface):
        - canvas.zoom (float, 0.25–3.0, default 1.0)
        - canvas.translation.x (float, horizontal doc-space offset)
        - canvas.translation.y (float, vertical doc-space offset)
        - grid.minor (int, minor grid spacing in doc units)
        - grid.majorEvery (int, how many minor steps between major grid lines)

        Invariants (PatchBay canvas parity):
        - Follow-finger pan: view-space drag on empty canvas maps deterministically into doc-space translation via Canvas2D.panBy; repeated drags compose cleanly.
        - Anchor-stable zoom: zooming around a view-space anchor keeps the underlying document point stationary in view space within a small tolerance (≤ 1 px for typical zoom deltas).
        - Grid spacing: pixel spacing between minor grid lines is `grid.minor × canvas.zoom`; major spacing is `grid.minor × grid.majorEvery × canvas.zoom`.
        - Node motion: dragging a node moves it in document space; the same doc-space position renders at different zoom levels according to Canvas2D, with no drift between pan/zoom cycles.
        """

        let facts: [String: Any] = [
            "appId": appId,
            "agentId": "fountain.coach/agent/infinity/service",
            "instruments": [[
                "manufacturer": "Fountain",
                "product": "InfinityCanvas",
                "instanceId": "infinity-1",
                "displayName": "Infinity Canvas"
            ]],
            "properties": [
                [
                    "name": "canvas.zoom",
                    "type": "float",
                    "min": 0.25,
                    "max": 3.0,
                    "default": 1.0
                ],
                [
                    "name": "canvas.translation.x",
                    "type": "float",
                    "min": -10000.0,
                    "max": 10000.0,
                    "default": 0.0
                ],
                [
                    "name": "canvas.translation.y",
                    "type": "float",
                    "min": -10000.0,
                    "max": 10000.0,
                    "default": 0.0
                ],
                [
                    "name": "grid.minor",
                    "type": "int",
                    "min": 2,
                    "max": 128,
                    "default": 24
                ],
                [
                    "name": "grid.majorEvery",
                    "type": "int",
                    "min": 1,
                    "max": 16,
                    "default": 5
                ]
            ],
            "robot": [
                "subset": [
                    "InfinityCanvasTests",
                    "InfinityGraphTests"
                ],
                "invariants": [
                    "followFingerPan",
                    "anchorStableZoom",
                    "gridSpacingMatchesZoom",
                    "nodeMotionStableUnderPanAndZoom"
                ]
            ]
        ]

        await PromptSeeder.seedAndPrint(appId: appId, prompt: teatroPrompt, facts: facts)
    }
}
