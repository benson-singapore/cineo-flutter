import UIKit
import AVFoundation
import AVKit

class VideoPlayerPiPController: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = VideoPlayerPiPController()

    private(set) var pipController: AVPictureInPictureController?
    private(set) var playerLayer: AVPlayerLayer?
    private(set) var playerHostView: UIView?

    var onModeChanged: ((Bool, Int64?) -> Void)?

    private var startCompletion: ((Bool) -> Void)?
    private var readinessTimer: Timer?
    private var readinessAttempts = 0
    private let maxReadinessAttempts = 100
    private let readinessInterval: TimeInterval = 0.1

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
        // iOS requires the AVPlayerLayer to be attached to a visible view
        // hierarchy before it can become a PiP source. A 1x1 off-screen layer
        // can make isPictureInPicturePossible remain false indefinitely.
        let hostView = UIView(frame: playerViewController.view.bounds)
        hostView.isUserInteractionEnabled = false
        hostView.alpha = 0.01
        hostView.backgroundColor = .clear
        hostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerViewController.view.addSubview(hostView)
        playerLayer.frame = hostView.bounds
        hostView.layer.addSublayer(playerLayer)
        guard let pipController = AVPictureInPictureController(playerLayer: playerLayer) else {
            hostView.removeFromSuperview()
            return false
        }

        pipController.delegate = self
        if #available(iOS 14.2, *) {
            pipController.canStartPictureInPictureAutomaticallyFromInline = true
        }
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

        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            readinessTimer?.invalidate()
            readinessTimer = nil
            finishStart(false)
            onModeChanged?(false, currentPositionMilliseconds())
            cleanup()
        }
    }

    private func waitUntilPictureInPictureIsPossible(
        _ pipController: AVPictureInPictureController,
        player: AVPlayer
    ) {
        if let item = player.currentItem {
            switch item.status {
            case .failed:
                finishStart(false)
                cleanup()
                return
            case .unknown:
                waitForReadiness(pipController, player: player)
                return
            case .readyToPlay:
                break
            @unknown default:
                waitForReadiness(pipController, player: player)
                return
            }
        }

        guard pipController.isPictureInPicturePossible else {
            waitForReadiness(pipController, player: player)
            return
        }

        readinessTimer?.invalidate()
        readinessTimer = nil
        pipController.startPictureInPicture()
    }

    private func waitForReadiness(
        _ pipController: AVPictureInPictureController,
        player: AVPlayer
    ) {
        readinessAttempts += 1
        if readinessAttempts >= maxReadinessAttempts {
            finishStart(false)
            cleanup()
            return
        }

        readinessTimer?.invalidate()
        readinessTimer = Timer.scheduledTimer(
            withTimeInterval: readinessInterval,
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
        onModeChanged?(true, currentPositionMilliseconds())
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        finishStart(false)
        onModeChanged?(false, currentPositionMilliseconds())
        cleanup()
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        onModeChanged?(false, currentPositionMilliseconds())
        cleanup()
    }

    private func currentPositionMilliseconds() -> Int64? {
        guard let player = playerLayer?.player else { return nil }
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return Int64(seconds * 1000)
    }

    private func cleanup() {
        self.pipController = nil
        self.playerLayer = nil
        playerHostView?.removeFromSuperview()
        self.playerHostView = nil
    }
}
