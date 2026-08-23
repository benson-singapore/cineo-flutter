import UIKit
import AVKit

class VideoPlayerPiPController: NSObject {
    static let shared = VideoPlayerPiPController()

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

        playerViewController.allowsPictureInPicturePlayback = true
        return true
    }

    // Start PiP
    func startPictureInPicture() -> Bool {
        guard let playerViewController = playerViewController,
              playerViewController.isPictureInPicturePossible else {
            return false
        }

        playerViewController.startPictureInPicture()
        return true
    }

    // Stop PiP
    func stopPictureInPicture() -> Bool {
        guard let playerViewController = playerViewController else {
            return false
        }

        playerViewController.stopPictureInPicture()
        return true
    }
}
