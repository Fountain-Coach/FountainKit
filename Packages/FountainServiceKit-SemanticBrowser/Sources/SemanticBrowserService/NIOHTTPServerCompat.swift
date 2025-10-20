import Foundation
import NIO
import NIOHTTP1
import NIOFoundationCompat

public typealias HTTPKernel = @Sendable (HTTPRequestHead, ByteBuffer?) async -> (HTTPResponseStatus, ByteBuffer)

public final class NIOHTTPServer {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?
    private let kernel: HTTPKernel

    public init(kernel: @escaping HTTPKernel) {
        self.kernel = kernel
    }

    public func start(port: Int) async throws -> Int {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(kernel: self.kernel))
                }
            }
        let ch = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
        self.channel = ch
        return ch.localAddress?.port ?? port
    }

    public func stop() async throws {
        if let ch = channel { try await ch.close().get() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            group.shutdownGracefully { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart
        private var head: HTTPRequestHead?
        private var body: ByteBuffer?
        private let kernel: HTTPKernel
        private struct ContextBox: @unchecked Sendable { let context: ChannelHandlerContext }
        init(kernel: @escaping HTTPKernel) { self.kernel = kernel }
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let h):
                head = h
                body = context.channel.allocator.buffer(capacity: 0)
            case .body(var b):
                body?.writeBuffer(&b)
            case .end:
                guard let head = head else { return }
                let body = body
                let kernel = self.kernel
                let promise = context.eventLoop.makePromise(of: (HTTPResponseStatus, ByteBuffer).self)
                promise.completeWithTask { await kernel(head, body) }
                let box = ContextBox(context: context)
                promise.futureResult.whenComplete { result in
                    let context = box.context
                    if let (status, respBody) = try? result.get() {
                        var headers = HTTPHeaders()
                        headers.add(name: "Content-Length", value: "\(respBody.readableBytes)")
                        headers.add(name: "Content-Type", value: "application/json")
                        context.write(self.wrapOutboundOut(.head(HTTPResponseHead(version: head.version, status: status, headers: headers))), promise: nil)
                        context.write(self.wrapOutboundOut(.body(.byteBuffer(respBody))), promise: nil)
                        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                    } else {
                        context.close(promise: nil)
                    }
                }
            }
        }
    }
}

extension NIOHTTPServer: @unchecked Sendable {}

public func makeSemanticKernel(service: SemanticMemoryService, engine: BrowserEngine? = nil, requireAPIKey: Bool = false) -> HTTPKernel {
    let eng = engine ?? URLFetchBrowserEngine()
    let parser = HTMLParser()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    @Sendable func buffer<T: Encodable>(_ value: T) -> ByteBuffer {
        let data = try? encoder.encode(value)
        var buf = ByteBufferAllocator().buffer(capacity: data?.count ?? 0)
        if let data { buf.writeBytes(data) }
        return buf
    }
    @Sendable func error(_ status: HTTPResponseStatus, _ message: String) -> (HTTPResponseStatus, ByteBuffer) {
        struct Err: Codable { let error: String }
        return (status, buffer(Err(error: message)))
    }
    @Sendable func query(_ uri: String) -> [String: String] {
        guard let idx = uri.firstIndex(of: "?") else { return [:] }
        let q = uri[uri.index(after: idx)...]
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[0])
                let val = String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(parts[1])
                out[key] = val
            }
        }
        return out
    }
    return { head, body in
        let path = head.uri.split(separator: "?")[0]
        if requireAPIKey {
            let apiKey = head.headers.first(name: "x-api-key")
            if apiKey == nil || apiKey!.isEmpty {
                return error(.unauthorized, "missing api key")
            }
        }
        switch (head.method, path) {
        case (.GET, "/v1/visual"):
            let qs = query(head.uri)
            guard let pageId = qs["pageId"], !pageId.isEmpty else { return error(.badRequest, "pageId required") }
            if let (asset, anchors) = await service.loadVisual(pageId: pageId) {
                struct Img: Codable { let imageId: String; let contentType: String?; let width: Int?; let height: Int?; let scale: Float? }
                struct Anchor: Codable { let imageId: String?; let x: Float?; let y: Float?; let w: Float?; let h: Float?; let excerpt: String?; let confidence: Float?; let ts: Double?; let stale: Bool? }
                struct Resp: Codable { let image: Img?; let anchors: [Anchor] }
                let img = asset.map { Img(imageId: $0.imageId, contentType: $0.contentType, width: $0.width, height: $0.height, scale: $0.scale) }
                let threshDays = Int(qs["staleThresholdDays"] ?? "")
                var cutoff: Date? = nil
                if let d = threshDays, let fetched = asset?.fetchedAt { cutoff = Calendar.current.date(byAdding: .day, value: -max(1, d), to: fetched) }
                let list = anchors.map { a -> Anchor in
                    let stale = (cutoff != nil && a.ts != nil) ? (a.ts! < cutoff!) : nil
                    return Anchor(imageId: a.imageId, x: a.x, y: a.y, w: a.w, h: a.h, excerpt: a.excerpt, confidence: a.confidence, ts: a.ts?.timeIntervalSince1970, stale: stale)
                }
                return (.ok, buffer(Resp(image: img, anchors: list)))
            }
            return error(.notFound, "no visual for pageId")
        case (.GET, let p) where p.hasPrefix("/assets/"):
            // Serve dev asset images by imageId
            let parts = p.split(separator: "/").map(String.init)
            if parts.count == 3, let imageName = parts.last, imageName.hasSuffix(".png") {
                let imageId = String(imageName.dropLast(4))
                if let ref = await service.loadArtifactRef(ownerId: imageId, kind: "image/png") {
                    if let data = try? Data(contentsOf: URL(fileURLWithPath: ref)) {
                        var buf = ByteBufferAllocator().buffer(capacity: data.count)
                        buf.writeBytes(data)
                        var headers = HTTPHeaders()
                        headers.add(name: "Content-Length", value: "\(buf.readableBytes)")
                        headers.add(name: "Content-Type", value: "image/png")
                        return (.ok, buf)
                    }
                }
                return error(.notFound, "asset not found")
            }
            return error(.badRequest, "invalid asset path")
        case (.POST, "/v1/index"):
            guard let body, let data = body.getData(at: 0, length: body.readableBytes) else {
                return error(.badRequest, "body required")
            }
            guard let req = try? JSONDecoder().decode(SemanticMemoryService.IndexRequest.self, from: data) else {
                return error(.badRequest, "invalid json")
            }
            let res = await service.ingest(req)
            return (.ok, buffer(res))
        case (.GET, "/v1/pages"):
            let qs = query(head.uri)
            let limit = Int(qs["limit"] ?? "20") ?? 20
            let offset = Int(qs["offset"] ?? "0") ?? 0
            let (total, items) = await service.queryPages(q: qs["q"], host: qs["host"], lang: qs["lang"], limit: limit, offset: offset)
            struct Resp<T: Codable>: Codable { let total: Int; let items: [T] }
            return (.ok, buffer(Resp(total: total, items: items)))
        case (.GET, "/v1/segments"):
            let qs = query(head.uri)
            let limit = Int(qs["limit"] ?? "20") ?? 20
            let offset = Int(qs["offset"] ?? "0") ?? 0
            let (total, items) = await service.querySegments(q: qs["q"], kind: qs["kind"], entity: qs["entity"], limit: limit, offset: offset)
            struct Resp<T: Codable>: Codable { let total: Int; let items: [T] }
            return (.ok, buffer(Resp(total: total, items: items)))
        case (.GET, "/v1/entities"):
            let qs = query(head.uri)
            let limit = Int(qs["limit"] ?? "20") ?? 20
            let offset = Int(qs["offset"] ?? "0") ?? 0
            let (total, items) = await service.queryEntities(q: qs["q"], type: qs["type"], limit: limit, offset: offset)
            struct Resp<T: Codable>: Codable { let total: Int; let items: [T] }
            return (.ok, buffer(Resp(total: total, items: items)))
        case (.POST, "/v1/snapshot"):
            guard let body, let data = body.getData(at: 0, length: body.readableBytes) else {
                return error(.badRequest, "body required")
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let url = obj["url"] as? String else {
                return error(.badRequest, "invalid json")
            }
            guard obj["wait"] != nil else { return error(.badRequest, "wait required") }
            guard let res = try? await eng.snapshot(for: url, wait: nil, capture: nil) else {
                return error(.internalServerError, "snapshot failed")
            }
            struct Page: Codable { let url: String; let status: Int?; let contentType: String? }
            struct Rend: Codable { let html: String; let text: String }
            struct Snap: Codable { let snapshotId: String; let page: Page; let rendered: Rend }
            struct Resp: Codable { let snapshot: Snap }
            let snap = Snap(snapshotId: UUID().uuidString, page: Page(url: res.finalURL, status: res.pageStatus, contentType: res.pageContentType), rendered: Rend(html: res.html, text: res.text))
            return (.ok, buffer(Resp(snapshot: snap)))
        case (.POST, "/v1/browse"):
            guard let body, let data = body.getData(at: 0, length: body.readableBytes) else {
                return error(.badRequest, "body required")
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let url = obj["url"] as? String else {
                return error(.badRequest, "invalid json")
            }
            guard let res = try? await eng.snapshot(for: url, wait: nil, capture: nil) else {
                return error(.internalServerError, "snapshot failed")
            }
            let (_, spans) = parser.parseTextAndBlocks(from: res.html)
            struct Block: Codable { let id: String; let kind: String; let text: String; let span: [Int] }
            struct Analysis: Codable { let blocks: [Block] }
            struct Resp: Codable { let analysis: Analysis }
            let blocks = spans.map { Block(id: $0.id, kind: $0.kind, text: $0.text, span: [$0.start, $0.end]) }
            return (.ok, buffer(Resp(analysis: Analysis(blocks: blocks))))
        case (.GET, "/v1/health"):
            struct Pool: Codable { let capacity: Int; let inUse: Int }
            struct Health: Codable { let status: String; let version: String; let browserPool: Pool }
            let h = Health(status: "ok", version: "0.1", browserPool: Pool(capacity: 0, inUse: 0))
            return (.ok, buffer(h))
        default:
            return error(.notFound, "not found")
        }
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
