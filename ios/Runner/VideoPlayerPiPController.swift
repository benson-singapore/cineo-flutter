import UIKit
import AVFoundation
import AVKit

class VideoPlayerPiPController: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = VideoPlayerPiPController()

    var pipController: AVPictureInPictureController?
    var playerLayer: AVPlayerLayer?
    var playerViewController: AVPlayerViewController?

    override private init() {
        super.init()
    }

    // Check if device supports PiP
    static func isPictureInPictureSupported() -> Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    // Enable PiP with AVPlayerViewController
    func enablePictureInPicture(with playerViewController: AVPlayerViewController) -> Bool {
        self.playerViewController = playerViewController

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return false
        }

        guard let player = playerViewController.player else {
            return false
        }

        let playerLayer = AVPlayerLayer(player: player)
        guard let pipController = AVPictureInPictureController(playerLayer: playerLayer) else {
            return false
        }

        pipController.delegate = self
        self.playerLayer = playerLayer
        self.pipController = pipController
        return true
    }

    // Start PiP
    func startPictureInPicture() -> Bool {
        guard let pipController = pipController,
              pipController.isPictureInPicturePossible else {
            return false
        }

        pipController.startPictureInPicture()
        return true
    }

    // Stop PiP
    func stopPictureInPicture() -> Bool {
        guard let pipController = pipController else {
            return false
        }

        pipController.stopPictureInPicture()
        return true
    }
}
