//
//  PlayerAnimationController.swift
//  BobaAtDawn
//
//  Character sprite animation controller for Boba in the Woods
//

import SpriteKit

// MARK: - Animation Configuration
struct PlayerAnimationConfig {
    static let frameCount = 3 // Frames per direction
    static let animationDuration = 0.6 // Total duration for full cycle
    static let use8Directions = true // 8-directional vs 4-directional
    static let idleFrame = 1 // Middle frame for idle (0-indexed)
}

// MARK: - Direction Mapping
enum AnimationDirection: Int, CaseIterable {
    case down = 0
    case downRight = 1
    case right = 2
    case upRight = 3
    case up = 4
    case upLeft = 5
    case left = 6
    case downLeft = 7
    
    // 4-directional fallback mapping
    var simplified: AnimationDirection {
        switch self {
        case .down, .downRight, .downLeft:
            return .down
        case .right, .upRight:
            return .right
        case .up, .upLeft:
            return .up
        case .left:
            return .left
        }
    }
    
    static func fromVector(_ direction: CGVector) -> AnimationDirection {
        let angle = atan2(direction.dy, direction.dx)
        let degrees = angle * 180 / .pi
        let normalizedDegrees = degrees < 0 ? degrees + 360 : degrees
        
        if PlayerAnimationConfig.use8Directions {
            // 8-directional mapping
            switch normalizedDegrees {
            case 337.5...360, 0..<22.5:
                return .right
            case 22.5..<67.5:
                return .upRight
            case 67.5..<112.5:
                return .up
            case 112.5..<157.5:
                return .upLeft
            case 157.5..<202.5:
                return .left
            case 202.5..<247.5:
                return .downLeft
            case 247.5..<292.5:
                return .down
            case 292.5..<337.5:
                return .downRight
            default:
                return .down
            }
        } else {
            // 4-directional mapping
            switch normalizedDegrees {
            case 315...360, 0..<45:
                return .right
            case 45..<135:
                return .up
            case 135..<225:
                return .left
            case 225..<315:
                return .down
            default:
                return .down
            }
        }
    }
}

// MARK: - Player Animation Controller
class PlayerAnimationController {
    
    // MARK: - Properties
    private weak var character: SKSpriteNode?
    private var walkAnimations: [AnimationDirection: SKAction] = [:]
    private var idleTextures: [AnimationDirection: SKTexture] = [:]
    private var currentDirection: AnimationDirection = .down
    private var isAnimating = false
    
    // MARK: - Texture Atlas
    private var playerAtlas: SKTextureAtlas?
    
    // MARK: - Initialization
    init(character: SKSpriteNode) {
        self.character = character
        setupTextureAtlas()
        setupAnimations()
    }
    
    // MARK: - Setup
    private func setupTextureAtlas() {
        // Load the player sprite atlas
        playerAtlas = SKTextureAtlas(named: "Player")
        print("🎭 Player atlas loaded with \(playerAtlas?.textureNames.count ?? 0) textures")
    }
    
    private func setupAnimations() {
        guard let atlas = playerAtlas else {
            print("❌ Cannot setup animations: Player atlas not loaded")
            return
        }
        
        let directions: [AnimationDirection] = PlayerAnimationConfig.use8Directions ? 
            AnimationDirection.allCases : 
            [.down, .right, .up, .left]
        
        for direction in directions {
            setupAnimationForDirection(direction, atlas: atlas)
        }
        
        // Set initial idle texture
        setIdleTexture(direction: .down)
        print("🎭 Setup complete for \(directions.count) directions")
    }
    
    private func setupAnimationForDirection(_ direction: AnimationDirection, atlas: SKTextureAtlas) {
        var textures: [SKTexture] = []
        
        // Load textures for this direction
        for frame in 0..<PlayerAnimationConfig.frameCount {
            let textureName = "player_\(direction.rawValue)_\(frame)"
            
            // Try to get texture from atlas
            if let texture = getTextureFromAtlas(atlas, named: textureName) {
                textures.append(texture)
            } else {
                print("⚠️ Missing texture: \(textureName)")
                // Create a fallback texture if needed
                if let fallbackTexture = createFallbackTexture() {
                    textures.append(fallbackTexture)
                }
            }
        }
        
        guard !textures.isEmpty else {
            print("❌ No textures loaded for direction \(direction)")
            return
        }
        
        // Store idle texture (middle frame)
        let idleIndex = min(PlayerAnimationConfig.idleFrame, textures.count - 1)
        idleTextures[direction] = textures[idleIndex]
        
        // Create walk animation
        let frameDuration = PlayerAnimationConfig.animationDuration / Double(textures.count)
        let walkAnimation = SKAction.repeatForever(
            SKAction.animate(with: textures, timePerFrame: frameDuration)
        )
        walkAnimations[direction] = walkAnimation
        
        print("🎭 Setup animation for \(direction): \(textures.count) frames")
    }
    
    private func getTextureFromAtlas(_ atlas: SKTextureAtlas, named textureName: String) -> SKTexture? {
        // Check if texture exists in atlas
        if atlas.textureNames.contains(textureName) {
            return atlas.textureNamed(textureName)
        }
        
        // Try alternative naming conventions
        let alternatives = [
            "player_walk_\(textureName.split(separator: "_").dropFirst().joined(separator: "_"))",
            "char_\(textureName.split(separator: "_").dropFirst().joined(separator: "_"))",
            textureName.replacingOccurrences(of: "player_", with: "")
        ]
        
        for altName in alternatives {
            if atlas.textureNames.contains(altName) {
                return atlas.textureNamed(altName)
            }
        }
        
        return nil
    }
    
    private func createFallbackTexture() -> SKTexture? {
        // Create a simple colored square as fallback
        let size = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        
        return SKTexture(image: image)
    }
    
    // MARK: - Animation Control
    func startWalking(direction: CGVector) {
        let animDirection = AnimationDirection.fromVector(direction)
        startWalking(direction: animDirection)
    }
    
    func startWalking(direction: AnimationDirection) {
        guard let character = character else { return }
        
        let targetDirection = PlayerAnimationConfig.use8Directions ? direction : direction.simplified
        
        // Only change animation if direction changed or not currently animating
        if currentDirection != targetDirection || !isAnimating {
            character.removeAction(forKey: "walk_animation")
            
            if let walkAnimation = walkAnimations[targetDirection] {
                character.run(walkAnimation, withKey: "walk_animation")
                currentDirection = targetDirection
                isAnimating = true
                print("🚶‍♂️ Started walking animation: \(targetDirection)")
            }
        }
    }
    
    func stopWalking() {
        guard let character = character else { return }
        
        character.removeAction(forKey: "walk_animation")
        setIdleTexture(direction: currentDirection)
        isAnimating = false
        print("🛑 Stopped walking animation")
    }
    
    private func setIdleTexture(direction: AnimationDirection) {
        guard let character = character else { return }
        
        let targetDirection = PlayerAnimationConfig.use8Directions ? direction : direction.simplified
        
        if let idleTexture = idleTextures[targetDirection] {
            character.texture = idleTexture
        }
    }
    
    // MARK: - Utility
    func getCurrentDirection() -> AnimationDirection {
        return currentDirection
    }
    
    func isCurrentlyAnimating() -> Bool {
        return isAnimating
    }
    
    // MARK: - Manual Frame Setting (for debugging)
    func setFrame(direction: AnimationDirection, frame: Int) {
        guard let atlas = playerAtlas else { return }
        guard let character = character else { return }
        
        let frameIndex = max(0, min(frame, PlayerAnimationConfig.frameCount - 1))
        let textureName = "player_\(direction.rawValue)_\(frameIndex)"
        
        if let texture = getTextureFromAtlas(atlas, named: textureName) {
            character.texture = texture
            print("🎭 Manually set frame: \(textureName)")
        }
    }
}
