import Foundation
import UIKit

class AlbumUtils {
    static func saveImage(image: UIImage?) {
        guard let image = image else { return }
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        
        showSuccessAlert(message: "Photo is saved to Album")
    }
    
    public static func showSuccessAlert(message: String) {
        DispatchQueue.main.async {
            let alertController = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(okAction)
            let topViewController = UIApplication.topViewController()
            topViewController?.present(alertController, animated: true, completion: nil)
        }
    }
}
