@preconcurrency import NIOCore
@preconcurrency import NIOPosix

/// NIO-based DNS server booting UDP and optional TCP listeners.
public final class DNSServer: @unchecked Sendable {
    private let group: EventLoopGroup
    private let engine: DNSEngine
    private var udpChannel: Channel?
    private var tcpChannel: Channel?

    /// Creates a server bound to the provided ``ZoneManager``.
    /// - Parameters:
    ///   - zoneManager: Actor supplying DNS records.
    ///   - signer: Optional DNSSEC signer for the engine.
    ///   - group: Event loop group powering the server. Defaults to a single-threaded group.
    public init(zoneManager: ZoneManager, signer: DNSSECSigner? = nil, group: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)) async {
        self.group = group
        self.engine = await DNSEngine(zoneManager: zoneManager, signer: signer)
    }

    /// Starts the UDP server and optionally a TCP server.
    /// - Parameters:
    ///   - udpPort: UDP port to bind to.
    ///   - tcpPort: Optional TCP port; when provided a TCP listener is started.
    /// - Returns: The bound UDP port.
    @discardableResult
    public func start(udpPort: Int, tcpPort: Int? = nil) async throws -> Int {
        let udpBootstrap = DatagramBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHandler(DatagramCodec()).flatMap {
                    channel.pipeline.addHandler(DNSHandler(engine: self.engine))
                }
            }
        self.udpChannel = try await udpBootstrap.bind(host: "127.0.0.1", port: udpPort).get()
        if let tcpPort {
            let tcpBootstrap = ServerBootstrap(group: group)
                .childChannelInitializer { channel in
                    channel.pipeline.addHandler(TCPFrameHandler()).flatMap {
                        channel.pipeline.addHandler(TCPFrameEncoder())
                    }.flatMap {
                        channel.pipeline.addHandler(DNSHandler(engine: self.engine))
                    }
                }
            self.tcpChannel = try await tcpBootstrap.bind(host: "127.0.0.1", port: tcpPort).get()
        }
        return self.udpChannel!.localAddress!.port!
    }

    /// Shuts down the server and releases resources.
    public func stop() async throws {
        try await udpChannel?.close().get()
        try await tcpChannel?.close().get()
        try await group.shutdownGracefully()
    }
}

/// UDP datagram codec translating `AddressedEnvelope` packets for ``DNSHandler``.
private final class DatagramCodec: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = AddressedEnvelope<ByteBuffer>
    private var remoteAddress: SocketAddress?

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = self.unwrapInboundIn(data)
        remoteAddress = envelope.remoteAddress
        context.fireChannelRead(self.wrapInboundOut(envelope.data))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        if let addr = remoteAddress {
            remoteAddress = nil
            let envelope = AddressedEnvelope(remoteAddress: addr, data: buffer)
            context.write(self.wrapOutboundOut(envelope), promise: promise)
        }
    }
}

/// Handler for TCP DNS length-prefixed frames.
private final class TCPFrameHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    private var buffer = ByteBuffer()

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var newData = self.unwrapInboundIn(data)
        buffer.writeBuffer(&newData)
        while true {
            guard let length: UInt16 = buffer.getInteger(at: buffer.readerIndex) else { break }
            let total = Int(length) + 2
            guard buffer.readableBytes >= total else { break }
            buffer.moveReaderIndex(forwardBy: 2)
            if let slice = buffer.readSlice(length: Int(length)) {
                context.fireChannelRead(self.wrapInboundOut(slice))
            }
        }
    }
}

/// Encoder for TCP DNS length-prefixed frames.
private final class TCPFrameEncoder: ChannelOutboundHandler, @unchecked Sendable {
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var buf = context.channel.allocator.buffer(capacity: 2)
        var bytes = self.unwrapOutboundIn(data)
        buf.writeInteger(UInt16(bytes.readableBytes), as: UInt16.self)
        buf.writeBuffer(&bytes)
        context.write(self.wrapOutboundOut(buf), promise: promise)
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
