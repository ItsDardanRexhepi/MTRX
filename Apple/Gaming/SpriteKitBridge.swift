import SpriteKit
import SwiftUI

/// SpriteKit bridge for 2D blockchain games in Component 14
/// Renders ERC-1155 game assets as sprites
class GameScene: SKScene {
    private var playerNode: SKSpriteNode?
    private var assetNodes: [String: SKSpriteNode] = [:]

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)
        setupPlayer()
    }

    private func setupPlayer() {
        let player = SKSpriteNode(color: .systemBlue, size: CGSize(width: 40, height: 40))
        player.position = CGPoint(x: frame.midX, y: frame.midY)
        player.physicsBody = SKPhysicsBody(rectangleOf: player.size)
        player.physicsBody?.isDynamic = true
        addChild(player)
        playerNode = player
    }

    /// Load an ERC-1155 game asset as a sprite from its metadata image URL
    func loadGameAsset(tokenId: String, imageData: Data, position: CGPoint) {
        guard let texture = SKTexture(data: imageData) else { return }
        let sprite = SKSpriteNode(texture: texture, size: CGSize(width: 32, height: 32))
        sprite.position = position
        sprite.name = tokenId
        addChild(sprite)
        assetNodes[tokenId] = sprite
    }

    func removeGameAsset(tokenId: String) {
        assetNodes[tokenId]?.removeFromParent()
        assetNodes.removeValue(forKey: tokenId)
    }

    override func update(_ currentTime: TimeInterval) {
        // Game loop — override per game
    }
}

extension SKTexture {
    convenience init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.init(image: image)
    }
}

/// SwiftUI wrapper for SpriteKit game scene
struct SpriteKitView: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.presentScene(scene)
        view.ignoresSiblingOrder = true
        return view
    }
    func updateUIView(_ uiView: SKView, context: Context) {}
}
