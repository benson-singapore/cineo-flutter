import UIKit
import AVKit

class VideoPlayerPiPController: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = VideoPlayerPiPController()

    var pipController: AVPictureInPictureController?
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

        guard let pipController = AVPictureInPictureController(playerViewController: playerViewController) else {
            return false
        }

        pipController.delegate = self
        self.pipController = pipController
        return true
    }

    // Start PiP
    func startPictureInPicture() -> Bool {
        guard let pipController = pipController, pipController.isPossible else {
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

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP started")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP stopped")
    }
}
