//
//  RotatableObject.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import SpriteKit

// MARK: - Object Types
enum ObjectType {
    case drink        // Small, portable items (test objects)
    case furniture    // Large, arrangeable items
    case station      // Boba station parts
    case completedDrink // Finished boba drinks (non-rotatable)
}

// MARK: - Rotation States
enum RotationState: Int, CaseIterable {
    case north = 0
    case east = 90
    case south = 180
    case west = 270
    
    var angle: CGFloat {
        return CGFloat(rawValue) * .pi / 180
    }
    
    func next() -> RotationState {
        let allCases = RotationState.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        let nextIndex = (currentIndex + 1) % allCases.count
        return allCases[nextIndex]
    }
}

@objc(RotatableObject)
class RotatableObject: SKSpriteNode {

    private enum CodingKeys {
        static let objectType = "editorObjectType"
        static let rotationState = "editorRotationState"
        static let shapeName = "editorShapeName"
    }
    
    // MARK: - Properties
    let objectType: ObjectType
    private(set) var rotationState: RotationState = .north
    private var isSelected: Bool = false
    private let defaultSize = GameConfig.Objects.defaultSize
    private let shapeName: String
    
    // MARK: - Initialization
    init(type: ObjectType, color: SKColor, shape: String) {
        self.objectType = type
        self.shapeName = shape
        super.init(texture: nil, color: color, size: defaultSize)
        
        name = "rotatable_\(type)_\(shape)"
        zPosition = ZLayers.layerFor(objectType: type)
        setupVisualShape(shape)
    }
    
    // Convenience initializer with default shape
    convenience init(type: ObjectType, color: SKColor) {
        self.init(type: type, color: color, shape: "rectangle")
    }
    
    required init?(coder aDecoder: NSCoder) {
        let decodedType = RotatableObject.objectType(from: aDecoder.decodeObject(forKey: CodingKeys.objectType) as? String)
        self.objectType = decodedType
        self.shapeName = aDecoder.decodeObject(forKey: CodingKeys.shapeName) as? String ?? "rectangle"
        super.init(coder: aDecoder)
        self.rotationState = RotationState(rawValue: aDecoder.decodeInteger(forKey: CodingKeys.rotationState)) ?? .north
        normalizeLegacyTableVisualsIfNeeded()
        if visualChildren().isEmpty && self.texture == nil {
            setupVisualShape(shapeName)
        }
        self.zRotation = rotationState.angle
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(RotatableObject.string(from: objectType), forKey: CodingKeys.objectType)
        coder.encode(rotationState.rawValue, forKey: CodingKeys.rotationState)
        coder.encode(shapeName, forKey: CodingKeys.shapeName)
    }
    
    // MARK: - Visual Setup
    private func setupVisualShape(_ shape: String) {
        switch shape {
        case "station":
            if let station = self as? IngredientStation {
                // Try specific station sprite, then "station_default", else fall back to shape.
                if station.applyStationSpriteFromType() {
                    return
                } else {
                    createStationShape()
                    return
                }
            } else {
                createStationShape()
                return
            }

        case "drink":
            if tryAddSprite(atlasName: "Objects", textureNames: ["drink_base", "drink_default"]) { return }
            createDrinkShape()

        case "table":
            if applyBuiltInTexture(named: "table") { return }
            if tryAddSprite(atlasName: "Objects", textureNames: ["table", "table_default"]) { return }
            createTableShape()

        case "arrow":
            if tryAddSprite(atlasName: "Objects", textureNames: ["arrow", "shape_arrow"]) { return }
            createArrowShape()

        case "L":
            if tryAddSprite(atlasName: "Objects", textureNames: ["shape_L"]) { return }
            createLShape()

        case "triangle":
            if tryAddSprite(atlasName: "Objects", textureNames: ["shape_triangle"]) { return }
            createTriangleShape()

        case "rectangle":
            _ = tryAddSprite(atlasName: "Objects", textureNames: ["shape_rectangle", "rectangle_default"])
            // Rectangle has its own base; no fallback shape call here.

        default:
            break
        }
    }

    /// Attempts to add a sprite from an atlas. Returns true on success, false if none of the names are found.
    @discardableResult
    private func tryAddSprite(atlasName: String, textureNames: [String]) -> Bool {
        let atlas = SKTextureAtlas(named: atlasName)
        guard let name = textureNames.first(where: { atlas.textureNames.contains($0) }) else {
            return false
        }

        let texture = atlas.textureNamed(name)
        let node = SKSpriteNode(texture: texture)
        node.name = "shape_sprite_\(name)"
        node.zPosition = 1
        node.position = .zero
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // Remove any prior visual children added by this class
        self.children
            .filter { $0.name?.hasPrefix("station_") == true || $0.name?.hasPrefix("shape_") == true }
            .forEach { $0.removeFromParent() }

        self.addChild(node)
        return true
    }

    private func visualChildren() -> [SKNode] {
        children.filter {
            guard let name = $0.name else { return false }
            return name.hasPrefix("station_") ||
                   name.hasPrefix("shape_") ||
                   name.hasPrefix("drink_") ||
                   name.hasPrefix("table_") ||
                   name == "direction_indicator" ||
                   name.hasPrefix("L_") ||
                   name == "triangle_indicator"
        }
    }

    @discardableResult
    private func applyBuiltInTexture(named textureName: String) -> Bool {
        let texture = SKTexture(imageNamed: textureName)
        texture.filteringMode = .nearest
        self.texture = texture
        color = .clear
        colorBlendFactor = 0
        return true
    }

    private func normalizeLegacyTableVisualsIfNeeded() {
        guard isTableLikeNode else { return }

        if texture == nil {
            _ = applyBuiltInTexture(named: "table")
        }

        children
            .filter {
                guard let name = $0.name else { return false }
                return name == "table_center" || name.hasPrefix("table_corner_")
            }
            .forEach { $0.removeFromParent() }
    }
    
    private func createArrowShape() {
        // Add arrow indicator showing direction
        let arrow = SKSpriteNode(color: .white, size: CGSize(width: 8, height: 20))
        arrow.position = CGPoint(x: 0, y: 15)
        arrow.name = "direction_indicator"
        arrow.alpha = GameConfig.Objects.indicatorAlpha
        addChild(arrow)
    }
    
    private func createLShape() {
        // Create L-shaped visual indicator
        let vertical = SKSpriteNode(color: .white, size: CGSize(width: 6, height: 30))
        vertical.position = CGPoint(x: -10, y: 5)
        vertical.name = "L_vertical"
        vertical.alpha = GameConfig.Objects.indicatorAlpha
        addChild(vertical)
        
        let horizontal = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 6))
        horizontal.position = CGPoint(x: 0, y: -10)
        horizontal.name = "L_horizontal"
        horizontal.alpha = GameConfig.Objects.indicatorAlpha
        addChild(horizontal)
    }
    
    private func createTriangleShape() {
        // Create triangular visual indicator
        let triangle = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 20))
        triangle.position = CGPoint(x: 0, y: 8)
        triangle.name = "triangle_indicator"
        triangle.alpha = GameConfig.Objects.indicatorAlpha
        addChild(triangle)
    }
    
    private func createStationShape() {
        // Station shape indicators (larger, more complex)
        let centerDot = SKSpriteNode(color: .white, size: CGSize(width: 12, height: 12))
        centerDot.position = CGPoint(x: 0, y: 0)
        centerDot.name = "station_center"
        centerDot.alpha = GameConfig.Objects.stationIndicatorAlpha
        addChild(centerDot)
        
        // Corner indicators
        let corners = [
            CGPoint(x: -25, y: 25),
            CGPoint(x: 25, y: 25),
            CGPoint(x: -25, y: -25),
            CGPoint(x: 25, y: -25)
        ]
        
        for (index, corner) in corners.enumerated() {
            let cornerDot = SKSpriteNode(color: .white, size: CGSize(width: 6, height: 6))
            cornerDot.position = corner
            cornerDot.name = "station_corner_\(index)"
            cornerDot.alpha = GameConfig.Objects.cornerIndicatorAlpha
            addChild(cornerDot)
        }
    }
    
    private func createDrinkShape() {
        // Small drink visual indicator
        let lid = SKSpriteNode(color: .white, size: CGSize(width: 16, height: 4))
        lid.position = CGPoint(x: 0, y: 12)
        lid.name = "drink_lid"
        lid.alpha = GameConfig.Objects.indicatorAlpha
        addChild(lid)
        
        let straw = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 20))
        straw.position = CGPoint(x: 6, y: 8)
        straw.name = "drink_straw"
        straw.alpha = GameConfig.Objects.indicatorAlpha
        addChild(straw)
    }
    
    private func createTableShape() {
        // Table visual indicator - simple geometric pattern
        let centerDot = SKSpriteNode(color: .white, size: GameConfig.Objects.tableCenterDotSize)
        centerDot.position = CGPoint(x: 0, y: 0)
        centerDot.name = "table_center"
        centerDot.alpha = 0.6
        addChild(centerDot)
        
        // Corner dots to show it's a table
        let corners = [
            CGPoint(x: -GameConfig.Objects.tableIndicatorOffset, y: GameConfig.Objects.tableIndicatorOffset),
            CGPoint(x: GameConfig.Objects.tableIndicatorOffset, y: GameConfig.Objects.tableIndicatorOffset),
            CGPoint(x: -GameConfig.Objects.tableIndicatorOffset, y: -GameConfig.Objects.tableIndicatorOffset),
            CGPoint(x: GameConfig.Objects.tableIndicatorOffset, y: -GameConfig.Objects.tableIndicatorOffset)
        ]
        
        for (index, corner) in corners.enumerated() {
            let cornerDot = SKSpriteNode(color: .white, size: GameConfig.Objects.tableCornerDotSize)
            cornerDot.position = corner
            cornerDot.name = "table_corner_\(index)"
            cornerDot.alpha = GameConfig.Objects.cornerIndicatorAlpha
            addChild(cornerDot)
        }
    }
    
    // MARK: - Rotation System
    func rotateToNextState() {
        rotationState = rotationState.next()
        
        // Animate rotation
        let rotateAction = SKAction.rotate(toAngle: rotationState.angle, duration: GameConfig.Objects.rotationDuration)
        rotateAction.timingMode = .easeInEaseOut
        run(rotateAction)
        
        // Add rotation feedback
        let scaleAction = SKAction.sequence([
            SKAction.scale(to: GameConfig.Objects.rotationFeedbackScale, duration: GameConfig.Objects.rotationFeedbackDuration),
            SKAction.scale(to: 1.0, duration: GameConfig.Objects.rotationFeedbackDuration)
        ])
        run(scaleAction)
    }
    
    func setRotationState(_ state: RotationState) {
        rotationState = state
        let rotateAction = SKAction.rotate(toAngle: state.angle, duration: GameConfig.Objects.rotationDuration / 1.5)
        run(rotateAction)
    }
    
    // MARK: - Selection System (Removed - No UI Elements)
    func setSelected(_ selected: Bool) {
        // No visual selection indicators - clean minimalist approach
        isSelected = selected
    }
    
    func forceHideSelection() {
        // No visual selection indicators - clean minimalist approach
        isSelected = false
    }
    
    // MARK: - State Queries
    var isRotatable: Bool {
        // Completed drinks are not rotatable
        return objectType != .completedDrink
    }
    
    var canBeCarried: Bool {
        if objectType == .station { return false }
        if name == "sacred_table" { return false }
        
        if name == "table" || name?.hasPrefix("table_") == true {
            return children.filter({ $0.name == "drink_on_table" }).isEmpty
        }
        
        return objectType == .drink || objectType == .completedDrink || objectType == .furniture
    }
    
    var canBeArranged: Bool {
        return objectType == .furniture || objectType == .station
    }
    func fadeAway() {
        run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 1.5),
                SKAction.scale(to: 0.3, duration: 1.5)
            ]),
            SKAction.removeFromParent()
        ]))
    }
}

private extension RotatableObject {
    var isTableLikeNode: Bool {
        name == "table" || name?.hasPrefix("table_") == true || shapeName == "table"
    }

    static func string(from type: ObjectType) -> String {
        switch type {
        case .drink:
            return "drink"
        case .furniture:
            return "furniture"
        case .station:
            return "station"
        case .completedDrink:
            return "completedDrink"
        }
    }

    static func objectType(from string: String?) -> ObjectType {
        switch string {
        case "drink":
            return .drink
        case "station":
            return .station
        case "completedDrink":
            return .completedDrink
        default:
            return .furniture
        }
    }
}
