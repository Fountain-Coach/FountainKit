import MIDI2
import MIDI2Core
import MIDI2Transports
import SSEOverMIDI

let session = RTPMidiSession(localName: "loopback")
let flex = FlexPacker()
let sysx = SysEx8Packer()
let rel = Reliability()

let sender = DefaultSseSender(rtp: session, flex: flex, sysx: sysx, rel: rel)
let receiver = DefaultSseReceiver(rtp: session, flex: flex, sysx: sysx, rel: rel)

receiver.onEvent = { env in
    print("Received #\(env.seq): \(env.data ?? "")")
}
receiver.onCtrl = { env in
    if let resend = rel.handleCtrl(env) {
        for frames in resend.values {
            for f in frames { try? session.send(umps: [f.words]) }
        }
    }
}

try receiver.start()

let tokens = ["Hello", "MIDI"]
for (i, t) in tokens.enumerated() {
    let env = SseEnvelope(ev: "message", seq: UInt64(i), data: t)
    try sender.send(event: env)
}

sender.close()
receiver.stop()

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
