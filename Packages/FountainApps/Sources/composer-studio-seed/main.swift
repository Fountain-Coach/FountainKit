import Foundation
import FountainStoreClient

@main
struct ComposerStudioSeedMain {
    static func main() async {
        let appId = "composer-studio"
        let prompt = """
        Composer Studio — Screenplay‑First Flow

        What
        - Single‑window macOS app for composing from screenplay text (.fountain) with inline tags.
        - Left: screenplay editor. Right: plan/preview card area with chat anchored at the bottom.
        - Actions: Parse → Map Cues → Apply; each action surfaces a compact result (warnings, cue counts, render status).
        - Journal records stored/parsed/cued/applied steps with timestamps so sessions are explainable and replayable.

        Why
        - Determinism: screenplay text + ETag define the session; the same input and operations yield the same cues and score changes.
        - Explainability: every change is accompanied by a short, human‑readable plan with anchors back into text and score.
        - Safety: Apply/Undo are idempotent for a given ETag; “Try” paths never mutate the stored score.

        How (surface)
        - Screenplay editor: monospaced, fountain‑style text area with inline tags (e.g. [[AudioTalk: mood gentle]]) and a small state strip (Project • Scene • Selection).
        - Actions row: Parse (builds structure + warnings), Map Cues (proposes cue spans), Apply (writes cues into score state and logs to journal).
        - Plan/preview card: shows the latest analysis, cue summary, and apply outcome with buttons for Apply / Try / Undo where applicable.
        - Chat: bottom‑anchored conversation where the user describes musical intent (“soften strings in Scene 2”); replies carry a short plan + anchors back to screenplay and score.

        Invariants
        - Parse never mutates the screenplay; it only produces structure and diagnostics.
        - Apply is ETag‑gated and idempotent for the same screenplay content + cue plan.
        - Preview card appears only when a fresh analysis or cue plan exists; Apply always logs a journal entry.
        - Journal entries are ordered newest‑first and include at least {action, scene/selection, summary, timestamp}.
        """

        let facts: [String: Any] = [
            "instruments": [
                [
                    "id": "score",
                    "product": "ScoreInstrument",
                    "properties": [
                        "score.page",
                        "score.zoom",
                        "score.selection.startBar",
                        "score.selection.endBar",
                        "score.annotations.visible",
                        "score.cueFocus.id"
                    ]
                ],
                [
                    "id": "script",
                    "product": "ScriptInstrument",
                    "properties": [
                        "script.act",
                        "script.scene",
                        "script.cursor.line",
                        "script.selection.startLine",
                        "script.selection.endLine",
                        "script.sidebar.visible"
                    ]
                ],
                [
                    "id": "cues",
                    "product": "CuePlannerInstrument",
                    "properties": [
                        "cues.focusId",
                        "cues.filter.mode"
                    ]
                ],
                [
                    "id": "chat",
                    "product": "ChatInstrument",
                    "properties": [
                        "chat.mode",
                        "chat.lastUserIntent",
                        "chat.unreadCount"
                    ]
                ]
            ],
            "flow": [
                "screenplay.save",
                "parse",
                "map.cues",
                "apply"
            ],
            "invariants": [
                "session.hasETag": true,
                "actions.gatedByPreconditions": true,
                "apply.idempotentPerETag": true
            ]
        ]

        await PromptSeeder.seedAndPrint(appId: appId, prompt: prompt, facts: facts)
    }
}

