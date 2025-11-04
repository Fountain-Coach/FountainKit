import SwiftUI
import AVKit

struct PBVideoPlayer: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(frame: .zero)
        v.controlsStyle = .inline
        v.allowsPictureInPicturePlayback = false
        v.updatesNowPlayingInfoCenter = false
        v.player = AVPlayer(url: url)
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player?.currentItem?.asset as? AVURLAsset == nil || (nsView.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            nsView.player = AVPlayer(url: url)
        }
    }
}

