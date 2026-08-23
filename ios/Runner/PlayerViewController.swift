import UIKit
import AVKit
import MediaPlayer
import Flutter

class PlayerViewController: UIViewController {
    static let channelName = "com.cineo/player"

    var pictureInPictureController: AVPictureInPictureController?
    var currentBrightness: CGFloat = UIScreen.main.brightness

    // Initialize method channel for PiP and other controls
    static func setupMethodChannel(with flutterViewController: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: flutterViewController.binaryMessenger
        )

        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "enablePictureInPicture":
                Self.enablePictureInPicture(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    static func enablePictureInPicture(result: @escaping FlutterResult) {
        // PiP support check
        if AVPictureInPictureController.isPictureInPictureSupported() {
            result(true)
        } else {
            result(false)
        }
    }

    // Brightness adjustment
    static func setBrightness(_ value: CGFloat) {
        DispatchQueue.main.async {
            UIScreen.main.brightness = max(0.1, min(1.0, value))
        }
    }

    // Volume control via system audio
    static func setVolume(_ value: Float) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
        }
    }
}
