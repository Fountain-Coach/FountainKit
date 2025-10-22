import Foundation
import FountainStoreClient
import FunctionCallerService
import PlannerService

@main
struct M2Smoke {
    static func main() async {
        let store = FountainStoreClient(client: EmbeddedFountainStoreClient())
        let corpus = "audiotalk"
        // Seed function catalog with a subset of AudioTalk operations (relative paths)
        func seed(_ id: String, _ method: String, _ path: String) async {
            let fn = FunctionModel(corpusId: corpus, functionId: id, name: id, description: "", httpMethod: method, httpPath: path)
            _ = try? await store.addFunction(fn)
        }
        await seed("createScreenplaySession", "POST", "/audiotalk/screenplay/sessions")
        await seed("createNotationSession", "POST", "/audiotalk/notation/sessions")
        await seed("parseScreenplay", "POST", "/audiotalk/screenplay/{id}/parse")
        await seed("mapScreenplayCues", "POST", "/audiotalk/screenplay/{id}/map-cues")
        await seed("getCueSheet", "GET", "/audiotalk/screenplay/{id}/cue-sheet")
        await seed("applyScreenplayCuesToNotation", "POST", "/audiotalk/screenplay/{id}/apply-to-notation")
        await seed("listJournal", "GET", "/audiotalk/journal")
        await seed("listUMPEvents", "GET", "/audiotalk/ump/{session}/events")

        // Verify function catalog via FunctionCaller API
        let caller = FunctionCallerOpenAPI(persistence: store, baseURLPrefix: "http://127.0.0.1:8080/audiotalk/v1")
        do {
            let out = try await caller.list_functions(.init(query: .init(page: 1, page_size: 50)))
            guard case .ok(let ok) = out, case .json(let body) = ok.body else {
                print("list_functions: unexpected response")
                exit(2)
            }
            print("functions: \(body.functions?.count ?? 0)")
        } catch {
            print("list_functions error: \(error)")
            exit(2)
        }

        // Generate a plan from a natural objective
        let planner = PlannerOpenAPI(persistence: store)
        let objective = "parse screenplay id=TEST map cues apply to notation notation=NS1 cue sheet"
        do {
            let req = Components.Schemas.UserObjectiveRequest(objective: objective)
            let out = try await planner.planner_reason(.init(body: .json(req)))
            guard case .ok(let ok) = out, case .json(let plan) = ok.body else {
                print("planner_reason: unexpected response")
                exit(2)
            }
            print("plan steps: \(plan.steps.count)")
            for s in plan.steps { print("- \(s.name)") }
        } catch {
            print("planner_reason error: \(error)")
            exit(2)
        }

        print("M2 smoke OK")
    }
}
