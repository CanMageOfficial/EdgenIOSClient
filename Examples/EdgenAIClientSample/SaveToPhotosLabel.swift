
import SwiftUI

struct SaveToPhotosLabel: View {
    var body: some View {
        Label("Save to Photos", systemImage: "square.and.arrow.down")
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}
