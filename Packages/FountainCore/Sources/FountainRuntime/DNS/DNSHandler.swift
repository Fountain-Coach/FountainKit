import NIOCore

final class DNSHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let engine: DNSEngine

    init(engine: DNSEngine) {
        self.engine = engine
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buf = self.unwrapInboundIn(data)
        if let response = engine.handleQuery(buffer: &buf) {
            context.write(self.wrapOutboundOut(response), promise: nil)
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
