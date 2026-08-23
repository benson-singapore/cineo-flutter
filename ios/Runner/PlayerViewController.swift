import UIKit
import AVFoundation
import AVKit
import Flutter

enum PlayerViewController {
    static let channelName = "com.benson.cineo/picture_in_picture"

    static func setupMethodChannel(with flutterViewController: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: flutterViewController.binaryMessenger
        )

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "isAvailable":
                result(AVPictureInPictureController.isPictureInPictureSupported())
            case "enter":
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

    static func presentSystemPlayer(
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
            let controller = AVPlayerViewController()
            controller.player = player
            controller.allowsPictureInPicturePlayback = true
            if #available(iOS 14.2, *) {
                controller.canStartPictureInPictureAutomaticallyFromInline = true
            }
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
                result(true)
            }
        }
    }
}
