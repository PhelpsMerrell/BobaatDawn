//
//  RemoteCharacter.swift
//  BobaAtDawn
//
//  Sprite representing the other player. Driven entirely by network updates.
//  Visually distinguished with a blue tint and "P2" label.
//  Shows a floating drink above the character when the remote player is carrying one.
//

import SpriteKit

class RemoteCharacter: SKSpriteNode {

    private var animationController: PlayerAnimationController?
    private var isRemoteMoving = false
    private var targetPosition: CGPoint = .zero
    private let lerpSpeed: CGFloat = 12.0
    private var playerLabel: SKLabelNode!
    
    // MARK: - Carried Drink Visual
    private var carriedDrinkNode: SKNode?
    private var lastDrinkCode: String? = nil

    init() {
        super.init(texture: nil, color: .clear, size: GameConfig.Character.size)
        name = "remote_character"
        zPosition = ZLayers.character - 1
        alpha = 0.9

        // Blue tint applied directly to the sprite — persists across texture changes
        self.color = SKColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0)
        self.colorBlendFactor = 0.35

        // "P2" label floating above the character
        playerLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        playerLabel.text = "P2"
        playerLabel.fontSize = 12
        playerLabel.fontColor = SKColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.9)
        playerLabel.horizontalAlignmentMode = .center
        playerLabel.verticalAlignmentMode = .bottom
        playerLabel.position = CGPoint(x: 0, y: size.height / 2 + 4)
        playerLabel.zPosition = 200
        addChild(playerLabel)

        setupAnimationController()
        Log.info(.network, "RemoteCharacter created with blue tint + P2 label")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupAnimationController() {
        animationController = PlayerAnimationController(character: self)
    }

    func applyRemoteUpdate(_ msg: PlayerPositionMessage) {
        targetPosition = msg.position.cgPoint

        if msg.isMoving {
            if let dirString = msg.animationDirection,
               let dir = animationDirectionFromString(dirString) {
                animationController?.startWalking(direction: dir)
            }
            isRemoteMoving = true
        } else {
            animationController?.stopWalking()
            isRemoteMoving = false
        }

        // Re-apply color blend after texture changes from animation
        self.colorBlendFactor = 0.35
        
        // Update carried drink visual
        updateCarriedDrink(isCarrying: msg.isCarrying, drinkCode: msg.carriedItemType)
    }

    func interpolate(deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)
        let dx = targetPosition.x - position.x
        let dy = targetPosition.y - position.y
        let factor = min(1.0, lerpSpeed * dt)
        position = CGPoint(x: position.x + dx * factor,
                           y: position.y + dy * factor)
    }
    
    // MARK: - Carried Drink Visual
    
    private func updateCarriedDrink(isCarrying: Bool, drinkCode: String?) {
        if !isCarrying || drinkCode == nil {
            // Not carrying — remove drink visual if present
            if carriedDrinkNode != nil {
                carriedDrinkNode?.removeFromParent()
                carriedDrinkNode = nil
                lastDrinkCode = nil
            }
            return
        }
        
        // Only rebuild if the drink ingredients changed
        guard drinkCode != lastDrinkCode else { return }
        lastDrinkCode = drinkCode
        
        // Remove old visual
        carriedDrinkNode?.removeFromParent()
        
        // Build new drink visual from code string
        let drinkNode = buildDrinkFromCode(drinkCode!)
        drinkNode.position = CGPoint(x: 0, y: GameConfig.Character.carryOffset)
        drinkNode.zPosition = ZLayers.carriedItems
        addChild(drinkNode)
        
        // Floating animation
        let float = SKAction.repeatForever(SKAction.sequence([
            SKAction.moveBy(x: 0, y: GameConfig.Character.floatDistance, duration: GameConfig.Character.floatDuration),
            SKAction.moveBy(x: 0, y: -GameConfig.Character.floatDistance, duration: GameConfig.Character.floatDuration)
        ]))
        drinkNode.run(float, withKey: "remote_drink_float")
        
        carriedDrinkNode = drinkNode
    }
    
    /// Build a drink visual from a compact ingredient code string.
    /// "T" = tea, "I" = ice, "B" = boba, "F" = foam, "L" = lid, "C" = empty cup only.
    private func buildDrinkFromCode(_ code: String) -> SKNode {
        let container = SKNode()
        let atlas = SKTextureAtlas(named: "Boba")
        let cupTex = atlas.textureNamed("cup_empty")
        let scale = 25.0 / cupTex.size().width
        
        func addLayer(_ texName: String, z: CGFloat) {
            guard atlas.textureNames.contains(texName) else { return }
            let tex = atlas.textureNamed(texName)
            tex.filteringMode = .nearest
            let node = SKSpriteNode(texture: tex)
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.position = .zero
            node.setScale(scale)
            node.zPosition = z
            node.blendMode = .alpha
            node.name = texName
            container.addChild(node)
        }
        
        addLayer("cup_empty", z: 0)
        if code.contains("T") { addLayer("tea_black",       z: 1) }
        if code.contains("I") { addLayer("ice_cubes",       z: 2) }
        if code.contains("B") { addLayer("topping_tapioca", z: 3) }
        if code.contains("F") { addLayer("foam_cheese",     z: 4) }
        if code.contains("L") { addLayer("lid_straw",       z: 5) }
        
        return container
    }

    private func animationDirectionFromString(_ s: String) -> AnimationDirection? {
        switch s.lowercased() {
        case "up":        return .up
        case "down":      return .down
        case "left":      return .left
        case "right":     return .right
        case "upleft":    return .upLeft
        case "upright":   return .upRight
        case "downleft":  return .downLeft
        case "downright": return .downRight
        default:          return nil
        }
    }
}
