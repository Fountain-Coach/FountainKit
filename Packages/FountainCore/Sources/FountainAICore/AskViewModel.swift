import Foundation
// Core chat message lives in ChatContracts; keep a typealias for compatibility here.
public typealias ChatMessage = CoreChatMessage

public protocol LLMService: Sendable {
    func chat(model: String, messages: [ChatMessage]) async throws -> String
}

public protocol BrowserService: Sendable {
    func analyze(url: String, corpusId: String?) async throws -> (title: String?, summary: String?)
}

public enum AskState: Sendable, Equatable { case idle, working, done, failed(String) }

public protocol PersistenceService: Sendable {
    func save(question: String, url: String?, answer: String, sourceURL: String?, sourceTitle: String?, corpusId: String?) async throws
}

public actor AskViewModel {
    private let llm: LLMService
    private let browser: BrowserService
    private let persistence: PersistenceService?

    public private(set) var state: AskState = .idle
    public private(set) var answer: String = ""
    public private(set) var sourceURL: String? = nil
    public private(set) var sourceTitle: String? = nil

    public init(llm: LLMService, browser: BrowserService, persistence: PersistenceService? = nil) {
        self.llm = llm
        self.browser = browser
        self.persistence = persistence
    }

    public func ask(question: String, url: String? = nil, model: String = "gpt-4o-mini", corpusId: String? = nil) async {
        self.state = .working
        var messages: [ChatMessage] = []
        var context: String? = nil
        if let link = url, !link.isEmpty {
            do {
                let (title, summary) = try await browser.analyze(url: link, corpusId: corpusId)
                context = summary
                self.sourceURL = link
                self.sourceTitle = title
                if let c = context, !c.isEmpty {
                    messages.append(.init(role: .system, content: "Use this context if relevant: \(c)"))
                }
            } catch {
                // Ignore analyze failures; proceed to chat
            }
        }
        let prompt = question.isEmpty ? (url.map { "Summarize: \($0)" } ?? "") : question
        messages.append(.init(role: .user, content: prompt))
        do {
            let text = try await llm.chat(model: model, messages: messages)
            self.answer = text
            self.state = .done
            if let p = persistence {
                try? await p.save(question: prompt, url: url, answer: text, sourceURL: self.sourceURL, sourceTitle: self.sourceTitle, corpusId: corpusId)
            }
        } catch {
            self.state = .failed(String(describing: error))
        }
    }
}
