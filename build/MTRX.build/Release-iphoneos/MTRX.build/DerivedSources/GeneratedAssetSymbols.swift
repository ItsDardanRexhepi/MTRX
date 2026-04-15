import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

    /// The "AccentPrimary" asset catalog color resource.
    static let accentPrimary = DeveloperToolsSupport.ColorResource(name: "AccentPrimary", bundle: resourceBundle)

    /// The "AccentSecondary" asset catalog color resource.
    static let accentSecondary = DeveloperToolsSupport.ColorResource(name: "AccentSecondary", bundle: resourceBundle)

    /// The "AccentTertiary" asset catalog color resource.
    static let accentTertiary = DeveloperToolsSupport.ColorResource(name: "AccentTertiary", bundle: resourceBundle)

    /// The "PriceDown" asset catalog color resource.
    static let priceDown = DeveloperToolsSupport.ColorResource(name: "PriceDown", bundle: resourceBundle)

    /// The "PriceUp" asset catalog color resource.
    static let priceUp = DeveloperToolsSupport.ColorResource(name: "PriceUp", bundle: resourceBundle)

    /// The "SurfaceCard" asset catalog color resource.
    static let surfaceCard = DeveloperToolsSupport.ColorResource(name: "SurfaceCard", bundle: resourceBundle)

    /// The "SurfaceElevated" asset catalog color resource.
    static let surfaceElevated = DeveloperToolsSupport.ColorResource(name: "SurfaceElevated", bundle: resourceBundle)

    /// The "TrinityPrimary" asset catalog color resource.
    static let trinityPrimary = DeveloperToolsSupport.ColorResource(name: "TrinityPrimary", bundle: resourceBundle)

    /// The "TrinityProcessing" asset catalog color resource.
    static let trinityProcessing = DeveloperToolsSupport.ColorResource(name: "TrinityProcessing", bundle: resourceBundle)

    /// The "TrinitySecondary" asset catalog color resource.
    static let trinitySecondary = DeveloperToolsSupport.ColorResource(name: "TrinitySecondary", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

}

