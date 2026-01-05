
import SwiftUI
import CoreData
import EdgenIOSClient

// MARK: - SwiftUI App
@main
struct EdgenSwiftUIsampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            // TODO update model id
            ModelManagerView(modelId: "model_id_here")
        }
    }
}
