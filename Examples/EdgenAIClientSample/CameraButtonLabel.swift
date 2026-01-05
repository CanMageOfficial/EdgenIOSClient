
import SwiftUI

struct CameraButtonLabel: View {
    var body: some View {
        Label("Camera", systemImage: "camera")
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}
