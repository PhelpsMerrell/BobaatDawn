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

class RotatableObject: SKSpriteNode {
    
    // MARK: - Properties
    let objectType: ObjectType
    private(set) var rotationState: RotationState = .north
    private var isSelected: Bool = false
    private let defaultSize = GameConfig.Objects.defaultSize
    
    // MARK: - Initialization
    init(type: ObjectType, color: SKColor, shape: String) {
        self.objectType = type
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
        fatalError("init(coder:) has not been implemented")
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
        print("📦 Checking canBeCarried for \(objectType):")
        print("📦   - name: \(name ?? "none")")
        print("📦   - objectType: \(objectType)")
        
        // Stations cannot be carried (too heavy)
        if objectType == .station {
            print("📦   - Blocked: objectType is .station")
            return false
        }
        
        // Only specific table objects cannot be carried (check for exact table pattern)
        if name == "table" || name?.hasPrefix("table_") == true {
            print("📦   - Blocked: this is an actual table object")
            return false
        }
        
        // Drinks, completed drinks, and small furniture CAN be carried
        let canCarry = objectType == .drink || objectType == .completedDrink || objectType == .furniture
        print("📦   - Result: \(canCarry) (drink:\(objectType == .drink), completedDrink:\(objectType == .completedDrink), furniture:\(objectType == .furniture))")
        return canCarry
    }
    
    var canBeArranged: Bool {
        return objectType == .furniture || objectType == .station
    }
}
