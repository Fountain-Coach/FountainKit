import Foundation

// Simple template model stored locally (UserDefaults JSON)
struct InstrumentTemplate: Identifiable, Codable, Equatable {
    let id: String // stable UUID string
    var kind: Components.Schemas.InstrumentKind
    var title: String
    var defaultWidth: Int
    var defaultHeight: Int
    var hidden: Bool = false
}

@MainActor
final class InstrumentTemplatesStore {
    private let defaultsKey = "pb.templates"
    
    func defaults() -> [InstrumentTemplate] {
        var seeded: [InstrumentTemplate] = []
        func t(id: String = UUID().uuidString, kind: Components.Schemas.InstrumentKind, title: String, w: Int, h: Int, hidden: Bool = false) -> InstrumentTemplate {
            InstrumentTemplate(id: id, kind: kind, title: title, defaultWidth: w, defaultHeight: h, hidden: hidden)
        }
        seeded.append(t(kind: .init(rawValue: "audiotalk.chat")!, title: "AudioTalk Chat", w: 300, h: 180))
        seeded.append(t(kind: .init(rawValue: "mvk.triangle")!, title: "Triangle", w: 260, h: 160))
        seeded.append(t(kind: .init(rawValue: "mvk.quad")!, title: "Textured Quad", w: 260, h: 160))
        seeded.append(t(kind: .init(rawValue: "external.coremidi")!, title: "External CoreMIDI", w: 260, h: 160))
        return seeded
    }

    func load() -> [InstrumentTemplate] {
        let d = UserDefaults.standard
        if let data = d.data(forKey: defaultsKey) {
            if let items = try? JSONDecoder().decode([InstrumentTemplate].self, from: data) {
                // Fallback: if decode yielded empty or all hidden, reseed defaults to avoid empty UX
                if items.isEmpty || items.allSatisfy({ $0.hidden }) {
                    let seeded = defaults()
                    save(seeded)
                    return seeded
                }
                return items
            }
        }
        // Seed defaults on first run
        let seeded = defaults()
        save(seeded)
        return seeded
    }

    func save(_ items: [InstrumentTemplate]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func toggleHidden(id: String, in items: inout [InstrumentTemplate]) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].hidden.toggle()
        save(items)
    }

    func rename(id: String, to newTitle: String, in items: inout [InstrumentTemplate]) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].title = newTitle
        save(items)
    }

    func move(fromOffsets: IndexSet, toOffset: Int, items: inout [InstrumentTemplate]) {
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save(items)
    }

    func reset() -> [InstrumentTemplate] {
        let seeded = defaults()
        save(seeded)
        return seeded
    }
}
