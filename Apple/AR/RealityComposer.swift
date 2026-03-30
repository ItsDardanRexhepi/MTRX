import RealityKit
import ARKit

/// AR scene composition for marketplace products, property tours, game asset previews
@MainActor
final class RealityComposer {
    private weak var arView: ARView?

    init(arView: ARView) { self.arView = arView }

    /// Create AR product preview for Component 24 Marketplace listings
    func composeProductPreview(name: String, price: String, imageData: Data?) -> AnchorEntity {
        let anchor = AnchorEntity(.plane(.horizontal, classification: .table, minimumBounds: [0.2, 0.2]))
        let box = ModelEntity(mesh: .generateBox(size: 0.1, cornerRadius: 0.005),
                              materials: [SimpleMaterial(color: .systemIndigo, isMetallic: true)])
        box.generateCollisionShapes(recursive: true)
        anchor.addChild(box)

        let label = ModelEntity(mesh: .generateText("\(name)\n\(price)", extrusionDepth: 0.001, font: .systemFont(ofSize: 0.015)),
                                materials: [SimpleMaterial(color: .white, isMetallic: false)])
        label.position = SIMD3(-0.05, 0.08, 0)
        anchor.addChild(label)
        return anchor
    }

    /// Create AR property tour for Component 4 RWA tokenized properties
    func composePropertyTour(address: String, details: [(label: String, value: String)]) -> AnchorEntity {
        let anchor = AnchorEntity(.plane(.vertical, classification: .wall, minimumBounds: [0.5, 0.5]))
        let panel = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.3),
                                materials: [SimpleMaterial(color: .black.withAlphaComponent(0.85), isMetallic: false)])
        anchor.addChild(panel)

        let titleMesh = MeshResource.generateText(address, extrusionDepth: 0.001, font: .boldSystemFont(ofSize: 0.018))
        let title = ModelEntity(mesh: titleMesh, materials: [SimpleMaterial(color: .systemGreen, isMetallic: false)])
        title.position = SIMD3(-0.18, 0.1, 0.001)
        anchor.addChild(title)

        for (i, detail) in details.enumerated() {
            let text = "\(detail.label): \(detail.value)"
            let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.012))
            let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
            entity.position = SIMD3(-0.18, 0.06 - Float(i) * 0.03, 0.001)
            anchor.addChild(entity)
        }
        return anchor
    }

    /// Create AR game asset preview for Component 14 ERC-1155 assets
    func composeGameAssetPreview(tokenId: String, name: String, rarity: String) -> AnchorEntity {
        let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.1, 0.1]))
        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.05),
                                 materials: [SimpleMaterial(color: rarityColor(rarity), isMetallic: true)])
        sphere.generateCollisionShapes(recursive: true)
        anchor.addChild(sphere)

        let label = ModelEntity(mesh: .generateText("\(name)\n#\(tokenId) [\(rarity)]", extrusionDepth: 0.001, font: .systemFont(ofSize: 0.01)),
                                materials: [SimpleMaterial(color: .white, isMetallic: false)])
        label.position = SIMD3(-0.04, 0.07, 0)
        anchor.addChild(label)
        return anchor
    }

    private func rarityColor(_ rarity: String) -> UIColor {
        switch rarity.lowercased() {
        case "legendary": return .systemYellow
        case "epic": return .systemPurple
        case "rare": return .systemBlue
        case "uncommon": return .systemGreen
        default: return .systemGray
        }
    }

    func placeScene(_ anchor: AnchorEntity) { arView?.scene.addAnchor(anchor) }
}
