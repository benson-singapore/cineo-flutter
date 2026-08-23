import UIKit
import AVFoundation
import AVKit
import Flutter

enum PlayerViewController {
    static let channelName = "com.benson.cineo/picture_in_picture"
    private static var channel: FlutterMethodChannel?

    static func setupMethodChannel(with flutterViewController: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: flutterViewController.binaryMessenger
        )
        Self.channel = channel
        VideoPlayerPiPController.shared.onModeChanged = { isInPictureInPicture in
            Self.channel?.invokeMethod(
                "pictureInPictureModeChanged",
                arguments: isInPictureInPicture
            )
        }

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "isAvailable":
                result(AVPictureInPictureController.isPictureInPictureSupported())
            case "enter":
                Self.enterPictureInPicture(
                    arguments: call.arguments as? [String: Any],
                    from: flutterViewController,
                    result: result
                )
            case "openSystemPlayer":
                Self.presentSystemPlayer(
                    arguments: call.arguments as? [String: Any],
                    from: flutterViewController,
                    result: result
                )
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    static func enterPictureInPicture(
        arguments: [String: Any]?,
        from flutterViewController: FlutterViewController,
        result: @escaping FlutterResult
    ) {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let urlString = arguments?["url"] as? String,
              let url = URL(string: urlString) else {
            result(false)
            return
        }

        DispatchQueue.main.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                result(false)
                return
            }

            let player = AVPlayer(url: url)
            let controller = UIViewController()
            controller.view.backgroundColor = .black
            controller.modalPresentationStyle = .fullScreen

            if let title = arguments?["title"] as? String {
                controller.title = title
            }
            if let milliseconds = arguments?["positionMilliseconds"] as? Int,
               milliseconds > 0 {
                let time = CMTime(value: Int64(milliseconds), timescale: 1000)
                player.seek(to: time)
            }

            flutterViewController.present(controller, animated: true) {
                player.play()
                guard VideoPlayerPiPController.shared.enablePictureInPicture(
                    with: player,
                    in: controller
                ) else {
                    controller.dismiss(animated: true)
                    result(false)
                    return
                }

                VideoPlayerPiPController.shared.startPictureInPicture { started in
                    DispatchQueue.main.async {
                        controller.dismiss(animated: true)
                        result(started)
                    }
                }
            }
        }
    }

    static func presentSystemPlayer(
        arguments: [String: Any]?,
        from flutterViewController: FlutterViewController,
        result: @escaping FlutterResult
    ) {
        guard let urlString = arguments?["url"] as? String,
              let url = URL(string: urlString) else {
            result(false)
            return
        }

        DispatchQueue.main.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                result(false)
                return
            }

            let player = AVPlayer(url: url)
            let controller = AVPlayerViewController()
            controller.player = player
            controller.allowsPictureInPicturePlayback = true
            if #available(iOS 14.2, *) {
                controller.canStartPictureInPictureAutomaticallyFromInline = true
            }
            controller.modalPresentationStyle = .fullScreen
            controller.title = arguments?["title"] as? String

            if let milliseconds = arguments?["positionMilliseconds"] as? Int,
               milliseconds > 0 {
                let time = CMTime(value: Int64(milliseconds), timescale: 1000)
                player.seek(to: time)
            }

            flutterViewController.present(controller, animated: true) {
                player.play()
                result(true)
            }
        }
    }
}
