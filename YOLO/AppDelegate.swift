import UIKit
import Clarity

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  /// Called when the app finishes launching, used here to set global app settings.
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Disable screen dimming and auto-lock to keep the app active during long operations.
    UIApplication.shared.isIdleTimerDisabled = true

    // Enable battery monitoring to allow the app to adapt its behavior based on battery level.
    UIDevice.current.isBatteryMonitoringEnabled = true

    // Store the app version and build version in UserDefaults for easy access elsewhere in the app.
    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    {
      UserDefaults.standard.set("\(appVersion) (\(buildVersion))", forKey: "app_version")
    }

    // Store the device's UUID in UserDefaults for identification purposes.
    if let uuid = UIDevice.current.identifierForVendor?.uuidString {
      UserDefaults.standard.set(uuid, forKey: "uuid")
    }

    // Ensure UserDefaults changes are immediately saved.
    UserDefaults.standard.synchronize()
      
      
    // Note: Set ".verbose" value for "logLevel" parameter while testing to debug initialization issues.
    let clarityConfig = ClarityConfig(projectId: "qb0lbdho2i")
    ClaritySDK.initialize(config: clarityConfig)
    return true
  }
}

/// Extension to CALayer to add functionality for generating screenshots of any layer.
extension CALayer {
  var screenShot: UIImage? {
    // Begin a new image context, using the device's screen scale to ensure high-resolution output.
    UIGraphicsBeginImageContextWithOptions(frame.size, false, UIScreen.main.scale)
    defer {
      UIGraphicsEndImageContext()
    }  // Ensure the image context is cleaned up correctly.

    if let context = UIGraphicsGetCurrentContext() {
      // Render the layer into the current context.
      render(in: context)
      // Attempt to generate an image from the current context.
      return UIGraphicsGetImageFromCurrentImageContext()
    }
    return nil  // Return nil if the operation fails.
  }
}
