import Foundation
import FountainStoreClient

@main
struct QuietFrameTeatroSeedMain {
    static func main() async {
        let appId = "quietframe"
        let prompt = """
        QuietFrame App — Teatro Prompt (Landing: Fountain Editor)

        What
        - Landing view is the Fountain Editor embedded in the QuietFrame app. It loads the current screenplay (plain text) and shows a parsed structure summary.
        - The editor uses an ETag‑gated write path; all saves require If‑Match. Proposals are the unit of change and can be created and applied with acceptance.
        - Instruments and placements are available for orchestration alongside the editor.

        Why
        - Determinism: ETag semantics ensure no conflicting writes.
        - Auditability: Proposals are structured and stored with persona + rationale.
        - Extensibility: Editor composes with instruments/placements for later orchestration in QuietFrame.

        How (HTTP contracts)
        - Script: GET /editor/{corpusId}/script → 200 text/plain + ETag; PUT (If‑Match required) → 204/400/412
        - Structure: GET /editor/{corpusId}/structure → acts/scenes/beats + etag
        - Preview: POST /editor/preview/parse (text/plain) → structure
        - Proposals: POST /editor/{cid}/proposals → 201; POST /editor/{cid}/proposals/{id} decision → 200
        - Proposals list/get: GET /editor/{cid}/proposals?limit&offset&order; GET /editor/{cid}/proposals/{id}
        - Instruments: GET/POST /editor/{cid}/instruments; GET/PATCH /editor/{cid}/instruments/{instrumentId}
        - Placements: GET/POST /editor/{cid}/placements; PATCH/DELETE /editor/{cid}/placements/{placementId}
        - Sessions: GET/POST /editor/sessions; PATCH /editor/sessions/{sessionId}

        Invariants
        - Saves are ETag‑gated; missing If‑Match yields typed 400 {message}.
        - Proposals support: composeBlock, insertScene, renameScene, rewriteRange, moveScene, splitScene, applyPatch.
        - Proposals list is ordered by createdAt (desc by default) with limit/offset.
        """

        let facts: [String: Any] = [
            "ui": [
                "landing": "editor",
                "panels": ["script", "structure", "proposals", "instruments", "placements"]
            ],
            "api": [
                "script": ["GET /editor/{cid}/script", "PUT /editor/{cid}/script"],
                "structure": ["GET /editor/{cid}/structure", "POST /editor/preview/parse"],
                "proposals": ["POST /editor/{cid}/proposals", "POST /editor/{cid}/proposals/{id}", "GET /editor/{cid}/proposals", "GET /editor/{cid}/proposals/{id}"],
                "instruments": ["GET/POST /editor/{cid}/instruments", "GET/PATCH /editor/{cid}/instruments/{instrumentId}"],
                "placements": ["GET/POST /editor/{cid}/placements", "PATCH/DELETE /editor/{cid}/placements/{placementId}"],
                "sessions": ["GET/POST /editor/sessions", "PATCH /editor/sessions/{sessionId}"]
            ],
            "proposals": [
                "ops": ["composeBlock", "insertScene", "renameScene", "rewriteRange", "moveScene", "splitScene", "applyPatch"],
                "fields": ["authorPersona", "rationale"]
            ],
            "rules": [
                "etag_required_on_put": true,
                "typed_errors": ["script.missing_if_match": true],
                "list_order_default": "desc"
            ]
        ]

        await PromptSeeder.seedAndPrint(appId: appId, prompt: prompt, facts: facts)
    }
}

