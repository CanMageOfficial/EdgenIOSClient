import UIKit
import EdgenIOSClient

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // TODO Initialize EdgenAI client with your credentials
        // Replace these with your actual access key and secret key
        EdgenAIClient.initialize(
            accessKey: "your_access_key_here",
            secretKey: "your_secret_key_here"
        )
                
        return true
    }
}
