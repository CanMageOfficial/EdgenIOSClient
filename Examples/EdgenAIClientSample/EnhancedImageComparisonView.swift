import SwiftUI

struct EnhancedImageComparisonView: View {
    let originalImage: UIImage
    let processedImage: UIImage?
    
    @State private var viewMode: ViewMode = .processed
    
    enum ViewMode: String, CaseIterable {
        case original = "Original"
        case processed = "Processed"
    }
    
    private var selectedImage: UIImage {
        switch viewMode {
        case .original:
            return originalImage
        case .processed:
            return processedImage ?? originalImage
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {            
            ZStack {
                Color.gray.opacity(0.1)
                
                Image(uiImage: selectedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipped()
            }
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            
            if processedImage == nil {
                Button(action: {
                    viewMode = .original
                }) {
                    Text(ViewMode.original.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                HStack {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button(action: {
                            viewMode = mode
                        }) {
                            Text(mode.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    viewMode == mode ? Color.blue : Color.gray.opacity(0.2)
                                )
                                .foregroundColor(
                                    viewMode == mode ? .white : .primary
                                )
                                .cornerRadius(8)
                        }
                        .disabled(
                            (mode == .processed && processedImage == nil)
                        )
                    }
                }
            }
        }
    }
}
