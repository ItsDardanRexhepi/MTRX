import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Core Image pipeline for document photo correction before Vision OCR
final class CoreImageProcessor {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Full correction pipeline: perspective → contrast → noise → sharpen
    func processDocumentImage(_ image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let corrected = ciImage
            |> perspectiveCorrection
            |> contrastEnhancement
            |> noiseReduction
            |> sharpen

        guard let cgImage = context.createCGImage(corrected, from: corrected.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func perspectiveCorrection(_ image: CIImage) -> CIImage {
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = CGPoint(x: image.extent.minX, y: image.extent.maxY)
        filter.topRight = CGPoint(x: image.extent.maxX, y: image.extent.maxY)
        filter.bottomLeft = CGPoint(x: image.extent.minX, y: image.extent.minY)
        filter.bottomRight = CGPoint(x: image.extent.maxX, y: image.extent.minY)
        return filter.outputImage ?? image
    }

    private func contrastEnhancement(_ image: CIImage) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = image
        filter.contrast = 1.2
        filter.brightness = 0.05
        filter.saturation = 0.0 // grayscale for OCR
        return filter.outputImage ?? image
    }

    private func noiseReduction(_ image: CIImage) -> CIImage {
        let filter = CIFilter.noiseReduction()
        filter.inputImage = image
        filter.noiseLevel = 0.02
        filter.sharpness = 0.4
        return filter.outputImage ?? image
    }

    private func sharpen(_ image: CIImage) -> CIImage {
        let filter = CIFilter.unsharpMask()
        filter.inputImage = image
        filter.radius = 2.5
        filter.intensity = 0.5
        return filter.outputImage ?? image
    }
}

precedencegroup PipelinePrecedence {
    associativity: left
}
infix operator |>: PipelinePrecedence
func |> (lhs: CIImage, rhs: (CIImage) -> CIImage) -> CIImage { rhs(lhs) }
