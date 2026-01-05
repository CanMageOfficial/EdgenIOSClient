import SwiftUI
import EdgenIOSClient

struct ModelManagerView: View {
    @State private var modelURL: URL? = nil
    @State private var checkedModel = false
    private let modelId: String
    private let client = EdgenAIClient()
    
    init(modelId: String) {
        self.modelId = modelId
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if let url = modelURL {
                    ProcessImageView(modelURL: url)
                } else {
                    ModelDownloadView(modelId: modelId) { url in
                        DispatchQueue.main.async {
                            self.modelURL = url
                        }
                    }
                }
            }
            .task {
                guard !checkedModel else { return }
                let result = client.checkModelExists(modelId: modelId)
                if result.exists, let url = result.modelURL {
                    self.modelURL = url
                }
                checkedModel = true
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationViewStyle(.stack)
    }
}
