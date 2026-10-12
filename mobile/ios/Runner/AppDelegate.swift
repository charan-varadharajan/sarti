import Flutter
import FoundationModels
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "app.sarti/native_ai",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "availability":
        result(Self.nativeAiAvailability())
      case "generate":
        guard
          let arguments = call.arguments as? [String: Any],
          let prompt = arguments["prompt"] as? String,
          !prompt.isEmpty
        else {
          result(FlutterError(code: "invalid_prompt", message: "A prompt is required.", details: nil))
          return
        }
        Self.generateOnDevice(prompt: prompt, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func nativeAiAvailability() -> String {
    guard #available(iOS 26.0, *) else { return "unsupported" }
    switch SystemLanguageModel.default.availability {
    case .available:
      return "available"
    case .unavailable(.modelNotReady):
      return "model_not_ready"
    case .unavailable(.appleIntelligenceNotEnabled):
      return "disabled"
    case .unavailable(.deviceNotEligible):
      return "unsupported"
    }
  }

  private static func generateOnDevice(prompt: String, result: @escaping FlutterResult) {
    guard #available(iOS 26.0, *) else {
      result(FlutterError(code: "unsupported", message: "On-device AI is unavailable.", details: nil))
      return
    }
    guard SystemLanguageModel.default.isAvailable else {
      result(FlutterError(code: "unavailable", message: "The on-device model is not ready.", details: nil))
      return
    }
    Task {
      do {
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let response = try await session.respond(to: prompt)
        await MainActor.run { result(response.content) }
      } catch {
        await MainActor.run {
          result(
            FlutterError(
              code: "generation_failed",
              message: "On-device generation failed.",
              details: nil
            )
          )
        }
      }
    }
  }
}
