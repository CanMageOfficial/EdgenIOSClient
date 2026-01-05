
import SwiftUI

struct PhotoButtonLabel: View {
    var body: some View {
        Label("Photos", systemImage: "photo.on.rectangle")
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}
