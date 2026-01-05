
import SwiftUI

struct GallerySelectionView: View {
    var title: String
    
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.1))
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .overlay(
                VStack {
                    Text(title)
                        .foregroundColor(.gray)
                }
            )
    }
}
