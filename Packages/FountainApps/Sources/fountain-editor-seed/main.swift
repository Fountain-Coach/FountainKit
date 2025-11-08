import Foundation
import FountainStoreClient

@main
struct FountainEditorSeed {
    static func main() async {
        // Seed the multi-corpus Fountain Editor Instrument prompt (teatro + facts)
        // Default corpus for the editor prompt itself: "fountain-editor"
        let env = ProcessInfo.processInfo.environment
        let corpusId = env["CORPUS_ID"] ?? "fountain-editor"
        let root = URL(fileURLWithPath: env["FOUNTAINSTORE_DIR"] ?? ".fountain/store")
        let client: FountainStoreClient
        do { client = FountainStoreClient(client: try DiskFountainStoreClient(rootDirectory: root)) } catch {
            print("seed: store init failed: \(error)"); return
        }
        do { _ = try await client.createCorpus(corpusId, metadata: ["app":"fountain-editor","kind":"teatro"]) } catch { }

        let pageId = "prompt:fountain-editor"
        _ = try? await client.addPage(.init(corpusId: corpusId, pageId: pageId, url: "store://prompt/fountain-editor", host: "store", title: "Fountain Editor Instrument — Teatro"))

        let teatro = """
        Fountain Editor Instrument — multi‑corpus, Slugline‑class

        What
        - Slugline UI: Outline (acts/scenes/beats), Typewriter Editor, Status, Page counter, Instruments drawer.
        - Multi‑corpus: create/open/switch/duplicate corpora in the editor; no delete in editor.
        - Modes: Editor and Chat share the same structural bed (anchors from the Fountain AST), not hard‑coded menus.

        Why
        - Keep screenplay text, structure, and instrument placement in one deterministic, Store‑backed surface. Changes are anchored, diffable, reproducible, and CI‑gated.

        How
        - Parser: TeatroCore.FountainParser (full Fountain syntax).
        - Anchors: act{n}.scene{m}[.beat{k}] with byte and line/col spans and script ETag.
        - Persistence (Store): script, structure facts, instruments library, placements, proposals, chat sessions, recents.
        - Instruments: library + placements attached to anchors; audition via midi2 BLE/RTP; no CoreMIDI.
        - Modes: Editor (smart blocks, typewriter) and Chat (draft/rewrite/structure/placements via proposals).
        - Safety: save requires matching ETag; facts and placements record ETags; proposals tracked with fingerprints.

        Shortcuts
        - Cmd+N New, Cmd+O Open, Cmd+K Switch, Cmd+S Save, Cmd+F Find, Cmd+Shift+N New scene, Cmd+\\ toggle Editor/Chat.

        Testing & CI
        - Parser + anchors unit; persistence + proposals integration; instruments audition; PB‑VRT numeric + snapshots. Any failure blocks merges.
        """
        _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):teatro", pageId: pageId, kind: "teatro.prompt", text: teatro))

        // Facts JSON (validator-safe). Use a Swift dictionary and encode to JSON to avoid escaping issues.
        var facts: [String: Any] = [:]
        facts["prompt.version"] = 2
        facts["ui"] = [
            "layout": "outline+editor+status+drawer",
            "modes": ["editor","chat"],
            "modeToggle.shortcut": "cmd\\u005C",
            "outline.minWidth": 220,
            "gutter": ["editorMarkers": true, "widthPx": 14],
            "editor": ["typewriter": true, "typeface": "Courier Prime", "fontSizePt": 12],
            "status.items": ["cursor","words","pages","etag","corpus"],
            "drawer": ["placements": true, "library": true]
        ]
        facts["parser"] = [
            "engine": "TeatroCore.FountainParser",
            "acts": ["from": "section.level1"],
            "scenes": ["from": ["section.level2","sceneHeading"]],
            "beats": ["from": "synopsis"],
            "anchors": ["format": "act{n}.scene{m}[.beat{k}]"]
        ]
        facts["pagination"] = [
            "paper": "USLetter",
            "font": "Courier12",
            "marginsInches": ["left": 1.5, "right": 1.0, "top": 1.0, "bottom": 1.0],
            "dualDialogue": true,
            "continuedMarks": true
        ]
        facts["persistence"] = [
            "script.page": "docs:{corpusId}:fountain:script",
            "structure.page": "prompt:{corpusId}:fountain-structure",
            "instruments.page": "docs:{corpusId}:instruments",
            "placements.page": "docs:{corpusId}:instrument-placements",
            "meta.page": "docs:{corpusId}:meta",
            "proposals.page": "docs:{corpusId}:proposals",
            "chat.sessions.prefix": "docs:{corpusId}:chat:sessions",
            "recents.page": "docs:fountain-editor:recents"
        ]
        facts["corpus"] = [
            "create": ["title": true, "corpusId.slug.fromTitle": true, "seedFromImport": true],
            "open": ["recents": true, "search": true],
            "switch": ["quickSwitcher": true],
            "duplicate": ["allowed": true],
            "delete": ["allowed": false, "note": "lifecycle managed externally (FountainAI)"]
        ]
        facts["instruments"] = [
            "profiles": ["midi2sampler"],
            "library.schema": ["instrumentId","name","tags","profile","programBase","defaultMapping","notes"],
            "placement.schema": ["placementId","anchor","instrumentId","overrides","order","bus","notes"],
            "anchor.format": "act{n}.scene{m}[.beat{k}]",
            "audition": ["enabled": true, "transport": ["ble","rtp"], "route": "midi2sampler"]
        ]
        facts["chat"] = [
            "instrument.id": "fountain-chat",
            "modes": ["draft","rewrite","controller"],
            "state": ["persona": "default", "threadId": NSNull(), "currentAnchor": NSNull(), "lastScriptETag": NSNull()],
            "ops": [
                "notify": ["chat.message","proposal.created","proposal.updated","proposal.accepted","proposal.rejected"],
                "set": ["chat.ask","chat.reply","chat.attachAnchor","chat.setPersona"],
                "tools": [
                    "editor.composeBlock","editor.rewriteRange","editor.insertScene","editor.renameScene",
                    "editor.moveScene","editor.splitScene","editor.applyPatch","placements.add","placements.update","cueSheet.generate"
                ]
            ]
        ]
        facts["shortcuts"] = [
            "newCorpus": "cmd+n",
            "openCorpus": "cmd+o",
            "switchCorpus": "cmd+k",
            "save": "cmd+s",
            "find": "cmd+f",
            "newScene": "cmd+shift+n",
            "toggleMode": "cmd+\\u005C"
        ]
        facts["invariants"] = [
            "outlineMinWidthPx": 220,
            "editorBaselineGridPx": 20,
            "gutterWidthPx": 14,
            "typewriterCenterTolerancePx": 1
        ]
        facts["testing"] = [
            "fixtures.corpus": "fountain-editor-fixtures",
            "fixtures.scripts": [
                "docs:fountain-editor-fixtures:fountain:script:baseline",
                "docs:fountain-editor-fixtures:fountain:script:dual-dialogue",
                "docs:fountain-editor-fixtures:fountain:script:notes-boneyard",
                "docs:fountain-editor-fixtures:fountain:script:sections-scenes"
            ],
            "pbvrt.numeric": [
                "outlineMinWidthPx": 220,
                "gutterWidthPx": 14,
                "editorBaselineGridPx": 20,
                "typewriterCenterTolerancePx": 1
            ],
            "pbvrt.snapshots": [
                "sizes": ["1440x900","1280x800"],
                "targets": ["editor.surface","chat.surface"]
            ],
            "parser.unit": ["assert": ["nodeCounts","anchorIds","lineColRanges","byteRanges","sectionsScenesBeats"]],
            "reconcile.unit": [
                "edits": ["insertNearAnchor","deleteNearAnchor","renameSection","sceneSplit"],
                "assert": ["placementsReattach","anchorsStableOrRenamed"]
            ],
            "persistence.integration": [
                "checks": ["saveRequiresMatchingETag","structureCarriesScriptETag","placementsRecordETags","staleWriteRejected"]
            ],
            "proposals.integration": [
                "ops": ["create","accept","reject"],
                "assert": ["patchApplied","scriptETagAdvanced","structureUpdated","historyRecorded"]
            ],
            "instruments.integration": [
                "library": ["create","duplicate","list","search"],
                "placements": ["add","update","remove","listForAnchor"],
                "audition": ["midi2Only","fanoutHonorsChannelGroupFilters"]
            ],
            "ci": [
                "runner": "Scripts/ci/fountain-editor-tests.sh",
                "gates": ["parser","persistence","proposals","instruments","pbvrt.numeric","pbvrt.snapshots"]
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            _ = try? await client.addSegment(.init(corpusId: corpusId, segmentId: "\(pageId):facts", pageId: pageId, kind: "facts", text: text))
        }

        print("Seeded Fountain Editor Instrument → corpus=\(corpusId) page=\(pageId)")
    }
}

