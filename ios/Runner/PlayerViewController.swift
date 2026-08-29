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
        VideoPlayerPiPController.shared.onModeChanged = { isInPictureInPicture, position in
            var arguments: [String: Any] = [
                "isInPictureInPicture": isInPictureInPicture,
            ]
            if let position {
                arguments["positionMilliseconds"] = position
            }
            Self.channel?.invokeMethod(
                "pictureInPictureModeChanged",
                arguments: arguments
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
            case "stop":
                VideoPlayerPiPController.shared.stopPictureInPicture()
                result(nil)
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
            if let milliseconds = arguments?["positionMilliseconds"] as? Int,
               milliseconds > 0 {
                let time = CMTime(value: Int64(milliseconds), timescale: 1000)
                player.seek(to: time)
            }

            guard VideoPlayerPiPController.shared.enablePictureInPicture(
                with: player,
                in: flutterViewController
            ) else {
                result(false)
                return
            }

            if arguments?["isPlaying"] as? Bool ?? true {
                player.play()
            }
            VideoPlayerPiPController.shared.startPictureInPicture { started in
                DispatchQueue.main.async {
                    result(started)
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
                if arguments?["isPlaying"] as? Bool ?? true {
                    player.play()
                }
                result(true)
            }
        }
    }
}
