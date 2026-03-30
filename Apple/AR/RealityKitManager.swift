import RealityKit
import ARKit
import Combine

/// RealityKit AR overlay — on-chain data in the physical world
/// Show property ownership history pointing at buildings, supply chain data on products
@MainActor
final class RealityKitManager: ObservableObject {
    @Published var isSessionRunning = false
    var arView: ARView?
    private var cancellables = Set<AnyCancellable>()

    func setupARView() -> ARView {
        let view = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        view.session.run(config)
        arView = view
        isSessionRunning = true
        return view
    }

    /// Place on-chain data card at a world position
    func placeDataCard(at position: SIMD3<Float>, title: String, details: String) {
        guard let arView else { return }
        let anchor = AnchorEntity(world: position)
        let mesh = MeshResource.generatePlane(width: 0.3, height: 0.15)
        let material = SimpleMaterial(color: .black.withAlphaComponent(0.8), isMetallic: false)
        let card = ModelEntity(mesh: mesh, materials: [material])
        let textMesh = MeshResource.generateText(title, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.02))
        let textEntity = ModelEntity(mesh: textMesh, materials: [SimpleMaterial(color: .white, isMetallic: false)])
        textEntity.position = SIMD3(-0.12, 0.03, 0.001)
        card.addChild(textEntity)
        anchor.addChild(card)
        arView.scene.addAnchor(anchor)
    }

    /// Place property ownership timeline in AR
    func placePropertyTimeline(at position: SIMD3<Float>, owners: [(name: String, date: String)]) {
        guard let arView else { return }
        let anchor = AnchorEntity(world: position)
        for (index, owner) in owners.enumerated() {
            let y = Float(index) * 0.06
            let text = "\(owner.date): \(owner.name)"
            let mesh = MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.015))
            let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: .cyan, isMetallic: false)])
            entity.position = SIMD3(0, y, 0)
            anchor.addChild(entity)
        }
        arView.scene.addAnchor(anchor)
    }

    func pauseSession() { arView?.session.pause(); isSessionRunning = false }
}
