import MIDI2Core

public protocol SseOverMidiSender {
    func send(event: SseEnvelope) throws
    func flush()
    func setWindow(_ n: Int)
    func close()
}

public protocol SseOverMidiReceiver {
    var onEvent: ((SseEnvelope) -> Void)? { get set }
    var onCtrl: ((SseEnvelope) -> Void)? { get set }
    func start() throws
    func stop()
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
