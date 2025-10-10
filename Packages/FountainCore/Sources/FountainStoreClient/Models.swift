import Foundation

public struct Corpus: Codable, Sendable {
    public let id: String
    public var metadata: [String: String]
    public init(id: String, metadata: [String: String] = [:]) {
        self.id = id
        self.metadata = metadata
    }
}

public struct CorpusCreateRequest: Codable, Sendable {
    public let corpusId: String
    public init(corpusId: String) { self.corpusId = corpusId }
}
public struct CorpusResponse: Codable, Sendable {
    public let corpusId: String; public let message: String
    public init(corpusId: String, message: String) { self.corpusId = corpusId; self.message = message }
}

public struct Baseline: Codable, Sendable {
    public let corpusId: String
    public let baselineId: String
    public let content: String
    public let ts: Double

    public init(corpusId: String, baselineId: String, content: String, ts: Double = Date().timeIntervalSince1970) {
        self.corpusId = corpusId
        self.baselineId = baselineId
        self.content = content
        self.ts = ts
    }
}

public struct Reflection: Codable, Sendable {
    public let corpusId: String
    public let reflectionId: String
    public let question: String
    public let content: String
    public let ts: Double

    public init(corpusId: String, reflectionId: String, question: String, content: String, ts: Double = Date().timeIntervalSince1970) {
        self.corpusId = corpusId
        self.reflectionId = reflectionId
        self.question = question
        self.content = content
        self.ts = ts
    }
}

public struct Drift: Codable, Sendable {
    public let corpusId: String
    public let driftId: String
    public let content: String
    public let ts: Double

    public init(corpusId: String, driftId: String, content: String, ts: Double = Date().timeIntervalSince1970) {
        self.corpusId = corpusId
        self.driftId = driftId
        self.content = content
        self.ts = ts
    }
}

public struct Patterns: Codable, Sendable {
    public let corpusId: String
    public let patternsId: String
    public let content: String
    public let ts: Double

    public init(corpusId: String, patternsId: String, content: String, ts: Double = Date().timeIntervalSince1970) {
        self.corpusId = corpusId
        self.patternsId = patternsId
        self.content = content
        self.ts = ts
    }
}

public struct Role: Codable, Sendable {
    public let corpusId: String
    public let name: String
    public let prompt: String

    public init(corpusId: String, name: String, prompt: String) {
        self.corpusId = corpusId
        self.name = name
        self.prompt = prompt
    }
}

public struct Page: Codable, Sendable {
    public let corpusId: String
    public let pageId: String
    public let url: String
    public let host: String
    public let title: String

    public init(corpusId: String, pageId: String, url: String, host: String, title: String) {
        self.corpusId = corpusId
        self.pageId = pageId
        self.url = url
        self.host = host
        self.title = title
    }
}

public struct Segment: Codable, Sendable {
    public let corpusId: String
    public let segmentId: String
    public let pageId: String
    public let kind: String
    public let text: String

    public init(corpusId: String, segmentId: String, pageId: String, kind: String, text: String) {
        self.corpusId = corpusId
        self.segmentId = segmentId
        self.pageId = pageId
        self.kind = kind
        self.text = text
    }
}

public struct Entity: Codable, Sendable {
    public let corpusId: String
    public let entityId: String
    public let name: String
    public let type: String

    public init(corpusId: String, entityId: String, name: String, type: String) {
        self.corpusId = corpusId
        self.entityId = entityId
        self.name = name
        self.type = type
    }
}

public struct Table: Codable, Sendable {
    public let corpusId: String
    public let tableId: String
    public let pageId: String
    public let csv: String

    public init(corpusId: String, tableId: String, pageId: String, csv: String) {
        self.corpusId = corpusId
        self.tableId = tableId
        self.pageId = pageId
        self.csv = csv
    }
}

public struct AnalysisRecord: Codable, Sendable {
    public let corpusId: String
    public let analysisId: String
    public let pageId: String
    public let summary: String

    public init(corpusId: String, analysisId: String, pageId: String, summary: String) {
        self.corpusId = corpusId
        self.analysisId = analysisId
        self.pageId = pageId
        self.summary = summary
    }
}

public struct Query: Sendable {
    public enum Mode: Sendable {
        case byId(String)
        case byIndexEq(String, String)
        case prefixScan(String, String)
    }
    public var mode: Mode?
    public var filters: [String: String]
    public var sort: [(field: String, ascending: Bool)]
    public var text: String?
    public var limit: Int?
    public var offset: Int?
    public init(mode: Mode? = nil, filters: [String: String] = [:], sort: [(field: String, ascending: Bool)] = [], text: String? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.mode = mode
        self.filters = filters
        self.sort = sort
        self.text = text
        self.limit = limit
        self.offset = offset
    }
}

public struct QueryResponse: Sendable {
    public let total: Int
    public let documents: [Data]
    public init(total: Int, documents: [Data]) {
        self.total = total
        self.documents = documents
    }
}

public struct Capabilities: Codable, Sendable {
    public var corpus: Bool
    public var documents: [String]
    public var query: [String]
    public var transactions: [String]
    public var admin: [String]
    public var experimental: [String]
    public init(corpus: Bool = true, documents: [String] = [], query: [String] = [], transactions: [String] = [], admin: [String] = [], experimental: [String] = []) {
        self.corpus = corpus
        self.documents = documents
        self.query = query
        self.transactions = transactions
        self.admin = admin
        self.experimental = experimental
    }
}

public struct FunctionModel: Codable, Sendable {
    public let corpusId: String
    public let functionId: String
    public let name: String
    public let description: String
    public let httpMethod: String
    public let httpPath: String

    public init(corpusId: String, functionId: String, name: String, description: String, httpMethod: String, httpPath: String) {
        self.corpusId = corpusId
        self.functionId = functionId
        self.name = name
        self.description = description
        self.httpMethod = httpMethod
        self.httpPath = httpPath
    }
}

public struct SuccessResponse: Codable, Sendable { public let message: String }

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
