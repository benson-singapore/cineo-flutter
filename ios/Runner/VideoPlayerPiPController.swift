import UIKit
import AVFoundation
import AVKit

class VideoPlayerPiPController: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = VideoPlayerPiPController()

    private(set) var pipController: AVPictureInPictureController?
    private(set) var playerLayer: AVPlayerLayer?
    private(set) var playerHostView: UIView?

    var onModeChanged: ((Bool) -> Void)?

    private var startCompletion: ((Bool) -> Void)?
    private var readinessTimer: Timer?
    private var readinessAttempts = 0

    override private init() {
        super.init()
    }

    static func isPictureInPictureSupported() -> Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    func enablePictureInPicture(
        with player: AVPlayer,
        in playerViewController: UIViewController
    ) -> Bool {
        readinessTimer?.invalidate()
        readinessTimer = nil
        startCompletion = nil
        self.playerHostView?.removeFromSuperview()
        self.playerHostView = nil

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return false
        }

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        // The layer must be attached to a visible view hierarchy for iOS to
        // accept the PiP request. Keep it out of the Flutter UI while the
        // native player is handed off to the PiP window.
        let hostView = UIView(frame: CGRect(x: -1, y: -1, width: 1, height: 1))
        hostView.isUserInteractionEnabled = false
        hostView.alpha = 0.01
        playerViewController.view.addSubview(hostView)
        playerLayer.frame = hostView.bounds
        hostView.layer.addSublayer(playerLayer)
        guard let pipController = AVPictureInPictureController(playerLayer: playerLayer) else {
            hostView.removeFromSuperview()
            return false
        }

        pipController.delegate = self
        self.playerLayer = playerLayer
        self.pipController = pipController
        self.playerHostView = hostView
        return true
    }

    func startPictureInPicture(completion: @escaping (Bool) -> Void) {
        guard let pipController = pipController,
              let player = playerLayer?.player else {
            completion(false)
            return
        }

        startCompletion = completion
        readinessAttempts = 0
        waitUntilPictureInPictureIsPossible(pipController, player: player)
    }

    func stopPictureInPicture() {
        guard let pipController = pipController else {
            return
        }

        pipController.stopPictureInPicture()
    }

    private func waitUntilPictureInPictureIsPossible(
        _ pipController: AVPictureInPictureController,
        player: AVPlayer
    ) {
        guard pipController.isPictureInPicturePossible else {
            readinessAttempts += 1
            if readinessAttempts >= 50 {
                finishStart(false)
                cleanup()
                return
            }

            readinessTimer?.invalidate()
            readinessTimer = Timer.scheduledTimer(
                withTimeInterval: 0.1,
                repeats: false
            ) { [weak self, weak pipController, weak player] _ in
                guard let self,
                      let pipController,
                      let player else {
                    self?.finishStart(false)
                    return
                }
                self.waitUntilPictureInPictureIsPossible(
                    pipController,
                    player: player
                )
            }
            return
        }

        readinessTimer?.invalidate()
        readinessTimer = nil
        pipController.startPictureInPicture()
    }

    private func finishStart(_ succeeded: Bool) {
        readinessTimer?.invalidate()
        readinessTimer = nil
        let completion = startCompletion
        startCompletion = nil
        completion?(succeeded)
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        finishStart(true)
        onModeChanged?(true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        finishStart(false)
        onModeChanged?(false)
        cleanup()
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        onModeChanged?(false)
        cleanup()
    }

    private func cleanup() {
        self.pipController = nil
        self.playerLayer = nil
        playerHostView?.removeFromSuperview()
        self.playerHostView = nil
    }
}
