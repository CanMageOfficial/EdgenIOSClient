#if canImport(UIKit)
import CoreML
import UIKit

// MARK: - Protocol for Model Configuration
public protocol ModelConfiguration {
    var inputSize: CGSize { get }
    var inputName: String { get }
    var outputName: String { get }
    func getModelURL() throws -> URL
}

// MARK: - Bundled Model Configuration
public struct BundledModelConfiguration: ModelConfiguration {
    let modelName: String
    let modelExtension: String
    public let inputSize: CGSize
    public let inputName: String
    public let outputName: String
    
    public init(
        modelName: String,
        modelExtension: String = "mlmodelc",
        inputSize: CGSize,
        inputName: String,
        outputName: String
    ) {
        self.modelName = modelName
        self.modelExtension = modelExtension
        self.inputSize = inputSize
        self.inputName = inputName
        self.outputName = outputName
    }
    
    public func getModelURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: modelExtension) else {
            throw ProcessingError.modelNotFound
        }
        return url
    }
}

// MARK: - File Path Model Configuration
public struct FilePathModelConfiguration: ModelConfiguration {
    let modelPath: URL
    public let inputSize: CGSize
    public let inputName: String
    public let outputName: String
    
    public init(
        modelPath: URL,
        inputSize: CGSize,
        inputName: String,
        outputName: String
    ) {
        self.modelPath = modelPath
        self.inputSize = inputSize
        self.inputName = inputName
        self.outputName = outputName
    }
    
    public func getModelURL() throws -> URL {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ProcessingError.modelNotFound
        }
        return modelPath
    }
}

// MARK: - Model Processor
public class ModelProcessor {
    
    // MARK: - Public API
    
    /// Process an image using any model configuration
    public static func processImage(_ inputImage: UIImage, configuration: ModelConfiguration) throws -> UIImage {
        let modelURL = try configuration.getModelURL()
        let model = try MLModel(contentsOf: modelURL)
        
        let pixelBuffer = try preprocessImage(inputImage, targetSize: configuration.inputSize)
        let output = try runInference(model: model, pixelBuffer: pixelBuffer, configuration: configuration)
        let resultImage = try postprocessOutput(output)
        
        return resultImage
    }
    
    // MARK: - Private Processing Steps
    
    private static func preprocessImage(_ image: UIImage, targetSize: CGSize) throws -> CVPixelBuffer {
        guard let resizedImage = image.resized(to: targetSize) else {
            throw ProcessingError.imagePreprocessingFailed
        }
        
        guard let pixelBuffer = resizedImage.toCVPixelBuffer() else {
            throw ProcessingError.imagePreprocessingFailed
        }
        
        return pixelBuffer
    }
    
    private static func runInference(
        model: MLModel,
        pixelBuffer: CVPixelBuffer,
        configuration: ModelConfiguration
    ) throws -> CVPixelBuffer {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            configuration.inputName: MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        
        let prediction = try model.prediction(from: input)
        
        guard let outputFeature = prediction.featureValue(for: configuration.outputName),
              let outputPixelBuffer = outputFeature.imageBufferValue else {
            throw ProcessingError.modelOutputInvalid
        }
        
        return outputPixelBuffer
    }
    
    private static func postprocessOutput(_ pixelBuffer: CVPixelBuffer) throws -> UIImage {
        guard let image = UIImage(pixelBuffer: pixelBuffer) else {
            throw ProcessingError.imagePostprocessingFailed
        }
        return image
    }
    
    public static func extractModelConfiguration(from url: URL) throws -> FilePathModelConfiguration {
        let model = try MLModel(contentsOf: url)
        let description = model.modelDescription
        
        // Get the first input that is an image type
        guard let inputName = description.inputDescriptionsByName.keys.first(where: { key in
            if case .image = description.inputDescriptionsByName[key]?.type {
                return true
            }
            return false
        }) else {
            throw NSError(
                domain: "ModelConfiguration",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No image input found in model"]
            )
        }
        
        // Get input size from the image constraint
        guard let inputFeature = description.inputDescriptionsByName[inputName],
              case .image = inputFeature.type else {
            throw NSError(
                domain: "ModelConfiguration",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid input type for '\(inputName)'"]
            )
        }
        
        // Get the first output (assuming single output for image processing)
        guard let outputName = description.outputDescriptionsByName.keys.first else {
            throw NSError(
                domain: "ModelConfiguration",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "No output found in model"]
            )
        }
        
        guard let imageConstraint = inputFeature.imageConstraint else {
            throw NSError(
                domain: "ModelConfiguration",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Image constraint missing from input feature"]
            )
        }
        
        let inputSize = CGSize(
            width: imageConstraint.pixelsWide,
            height: imageConstraint.pixelsHigh
        )
                
        return FilePathModelConfiguration(
            modelPath: url,
            inputSize: inputSize,
            inputName: inputName,
            outputName: outputName
        )
    }
}

// MARK: - Convenience Extensions
public extension ModelProcessor {
    /// Convenience method for bundled models
    static func processImage(_ inputImage: UIImage, modelName: String, configuration: BundledModelConfiguration) throws -> UIImage {
        return try processImage(inputImage, configuration: configuration)
    }
}

// MARK: - Error Types
public enum ProcessingError: LocalizedError {
    case modelNotFound
    case imagePreprocessingFailed
    case modelOutputInvalid
    case imagePostprocessingFailed
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model file not found or inaccessible"
        case .imagePreprocessingFailed:
            return "Failed to preprocess input image"
        case .modelOutputInvalid:
            return "Model produced invalid output"
        case .imagePostprocessingFailed:
            return "Failed to convert model output to image"
        }
    }
}

// MARK: - Usage Examples
/*
// Example 1: Bundled model
let bundledConfig = BundledModelConfiguration(
    modelName: "model name",
    inputSize: CGSize(width: 512, height: 512),
    inputName: "input",
    outputName: "activation_out"
)
let result1 = try ModelProcessor.processImage(inputImage, configuration: bundledConfig)

// Example 2: File path model
let fileConfig = FilePathModelConfiguration(
    modelPath: URL(fileURLWithPath: "/path/to/model.mlmodelc"),
    inputSize: CGSize(width: 512, height: 512),
    inputName: "input",
    outputName: "output"
)
let result2 = try ModelProcessor.processImage(inputImage, configuration: fileConfig)
*/
#endif
