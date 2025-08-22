//
//  ForestScene+GridPositioning.swift
//  BobaAtDawn
//
//  Forest room positioning using grid coordinates - FIXED
//

import SpriteKit

// MARK: - Forest Room Configuration
struct ForestRoomConfig {
    let roomNumber: Int
    let emoji: String
    
    // Grid positions for room elements
    let roomIdentifierPosition: GridCoordinate
    let backDoorPosition: GridCoordinate?  // Only Room 1
    let leftHintPosition: GridCoordinate
    let rightHintPosition: GridCoordinate
    
    // Special object positions
    let specialObjects: [String: GridCoordinate]
    
    static func config(for room: Int) -> ForestRoomConfig {
        let roomEmojis = ["", "🍄", "⛰️", "⭐", "💎", "🌳"]
        
        switch room {
        case 1: // Mushroom Room
            return ForestRoomConfig(
                roomNumber: 1,
                emoji: roomEmojis[1],
                roomIdentifierPosition: GridCoordinate(x: 16, y: 12),
                backDoorPosition: GridCoordinate(x: 16, y: 20),
                leftHintPosition: GridCoordinate(x: 3, y: 12),
                rightHintPosition: GridCoordinate(x: 29, y: 12),
                specialObjects: [
                    "small_mushroom_1": GridCoordinate(x: 8, y: 15),
                    "small_mushroom_2": GridCoordinate(x: 24, y: 9),
                    "fairy_ring": GridCoordinate(x: 12, y: 18)
                ]
            )
            
        case 2: // Mountain Room
            return ForestRoomConfig(
                roomNumber: 2,
                emoji: roomEmojis[2],
                roomIdentifierPosition: GridCoordinate(x: 16, y: 12),
                backDoorPosition: nil,
                leftHintPosition: GridCoordinate(x: 3, y: 12),
                rightHintPosition: GridCoordinate(x: 29, y: 12),
                specialObjects: [
                    "small_rock_1": GridCoordinate(x: 10, y: 16),
                    "small_rock_2": GridCoordinate(x: 22, y: 8),
                    "cave_entrance": GridCoordinate(x: 16, y: 18)
                ]
            )
            
        case 3: // Star Room
            return ForestRoomConfig(
                roomNumber: 3,
                emoji: roomEmojis[3],
                roomIdentifierPosition: GridCoordinate(x: 16, y: 12),
                backDoorPosition: nil,
                leftHintPosition: GridCoordinate(x: 3, y: 12),
                rightHintPosition: GridCoordinate(x: 29, y: 12),
                specialObjects: [
                    "star_fragment_1": GridCoordinate(x: 12, y: 16),
                    "star_fragment_2": GridCoordinate(x: 20, y: 8),
                    "crystal_pool": GridCoordinate(x: 16, y: 6)
                ]
            )
            
        case 4: // Diamond Room  
            return ForestRoomConfig(
                roomNumber: 4,
                emoji: roomEmojis[4],
                roomIdentifierPosition: GridCoordinate(x: 16, y: 12),
                backDoorPosition: nil,
                leftHintPosition: GridCoordinate(x: 3, y: 12),
                rightHintPosition: GridCoordinate(x: 29, y: 12),
                specialObjects: [
                    "gem_1": GridCoordinate(x: 14, y: 18),
                    "gem_2": GridCoordinate(x: 18, y: 6),
                    "treasure_chest": GridCoordinate(x: 25, y: 15)
                ]
            )
            
        case 5: // Tree Room
            return ForestRoomConfig(
                roomNumber: 5,
                emoji: roomEmojis[5],
                roomIdentifierPosition: GridCoordinate(x: 16, y: 12),
                backDoorPosition: nil,
                leftHintPosition: GridCoordinate(x: 3, y: 12),
                rightHintPosition: GridCoordinate(x: 29, y: 12),
                specialObjects: [
                    "ancient_tree": GridCoordinate(x: 16, y: 16),
                    "tree_hollow": GridCoordinate(x: 8, y: 18),
                    "wisdom_stone": GridCoordinate(x: 24, y: 8)
                ]
            )
            
        default:
            return config(for: 1) // Default to Room 1
        }
    }
}

// MARK: - ForestScene Grid Positioning Extension
extension ForestScene {
    
    /// Setup room using grid positioning system
    /// - Parameter roomNumber: Which room to set up (1-5)
    func setupRoomWithGrid(_ roomNumber: Int) {
        let config = ForestRoomConfig.config(for: roomNumber)
        
        // Remove previous room elements
        roomIdentifier?.removeFromParent()
        backDoor?.removeFromParent()
        leftHintEmoji?.removeFromParent()
        rightHintEmoji?.removeFromParent()
        
        // Clear any special objects from previous room
        removeSpecialObjects()
        
        // Room identifier (big emoji in center)
        roomIdentifier = SKLabelNode(text: config.emoji)
        roomIdentifier!.fontSize = 120
        roomIdentifier!.fontName = "Arial"
        roomIdentifier!.horizontalAlignmentMode = .center
        roomIdentifier!.verticalAlignmentMode = .center
        roomIdentifier!.position = gridService.gridToWorld(config.roomIdentifierPosition)
        roomIdentifier!.zPosition = 5
        addChild(roomIdentifier!)
        
        // Back door (only in Room 1)
        if let doorPos = config.backDoorPosition {
            backDoor = SKLabelNode(text: "🚪")
            backDoor!.fontSize = 80
            backDoor!.fontName = "Arial"
            backDoor!.horizontalAlignmentMode = .center
            backDoor!.verticalAlignmentMode = .center
            backDoor!.position = gridService.gridToWorld(doorPos)
            backDoor!.zPosition = 10
            backDoor!.name = "back_door"
            addChild(backDoor!)
            
            print("🚪 Back door positioned at grid \\(doorPos)")
        }
        
        // Hint emojis
        let previousRoomEmoji = roomEmojis[getPreviousRoom()]
        leftHintEmoji = SKLabelNode(text: previousRoomEmoji)
        leftHintEmoji!.fontSize = 40
        leftHintEmoji!.fontName = "Arial"
        leftHintEmoji!.alpha = 0.3
        leftHintEmoji!.horizontalAlignmentMode = .center
        leftHintEmoji!.verticalAlignmentMode = .center
        leftHintEmoji!.position = gridService.gridToWorld(config.leftHintPosition)
        leftHintEmoji!.zPosition = 3
        addChild(leftHintEmoji!)
        
        let nextRoomEmoji = roomEmojis[getNextRoom()]
        rightHintEmoji = SKLabelNode(text: nextRoomEmoji)
        rightHintEmoji!.fontSize = 40
        rightHintEmoji!.fontName = "Arial"
        rightHintEmoji!.alpha = 0.3
        rightHintEmoji!.horizontalAlignmentMode = .center
        rightHintEmoji!.verticalAlignmentMode = .center
        rightHintEmoji!.position = gridService.gridToWorld(config.rightHintPosition)
        rightHintEmoji!.zPosition = 3
        addChild(rightHintEmoji!)
        
        // Add special objects for this room
        addSpecialObjects(config.specialObjects)
        
        print("🌲 Room \\(roomNumber) (\\(config.emoji)) setup with grid positioning")
        print("   Room center: \\(config.roomIdentifierPosition)")
        print("   Special objects: \\(config.specialObjects.count)")
    }
    
    /// Add special objects to the current room
    /// - Parameter objects: Dictionary of object name to grid position
    private func addSpecialObjects(_ objects: [String: GridCoordinate]) {
        for (objectName, gridPos) in objects {
            let object = createSpecialObject(named: objectName)
            object.position = gridService.gridToWorld(gridPos)
            object.name = objectName
            addChild(object)
            
            print("✨ Added \\(objectName) at grid \\(gridPos)")
        }
    }
    
    /// Create special objects for forest rooms
    /// - Parameter name: Object identifier
    /// - Returns: Configured SKNode
    private func createSpecialObject(named name: String) -> SKNode {
        switch name {
        // Mushroom room objects
        case "small_mushroom_1", "small_mushroom_2":
            let mushroom = SKLabelNode(text: "🍄")
            mushroom.fontSize = 30
            mushroom.alpha = 0.7
            mushroom.zPosition = 2
            mushroom.fontName = "Arial"
            mushroom.horizontalAlignmentMode = .center
            mushroom.verticalAlignmentMode = .center
            return mushroom
            
        case "fairy_ring":
            let ring = SKShapeNode(circleOfRadius: 25)
            ring.strokeColor = .magenta.withAlphaComponent(0.3)
            ring.fillColor = .clear
            ring.lineWidth = 2
            ring.zPosition = 1
            return ring
            
        // Mountain room objects
        case "small_rock_1", "small_rock_2":
            let rock = SKLabelNode(text: "🪨")
            rock.fontSize = 25
            rock.alpha = 0.8
            rock.zPosition = 2
            rock.fontName = "Arial"
            rock.horizontalAlignmentMode = .center
            rock.verticalAlignmentMode = .center
            return rock
            
        case "cave_entrance":
            let cave = SKLabelNode(text: "🕳️")
            cave.fontSize = 40
            cave.alpha = 0.9
            cave.zPosition = 2
            cave.fontName = "Arial"
            cave.horizontalAlignmentMode = .center
            cave.verticalAlignmentMode = .center
            return cave
            
        // Star room objects
        case "star_fragment_1", "star_fragment_2":
            let star = SKLabelNode(text: "⭐")
            star.fontSize = 20
            star.alpha = 0.8
            star.zPosition = 2
            star.fontName = "Arial"
            star.horizontalAlignmentMode = .center
            star.verticalAlignmentMode = .center
            // Add sparkle animation
            let sparkle = SKAction.sequence([
                SKAction.scale(to: 1.2, duration: 1.0),
                SKAction.scale(to: 0.8, duration: 1.0)
            ])
            star.run(SKAction.repeatForever(sparkle))
            return star
            
        case "crystal_pool":
            let pool = SKShapeNode(circleOfRadius: 30)
            pool.strokeColor = .cyan.withAlphaComponent(0.5)
            pool.fillColor = .blue.withAlphaComponent(0.2)
            pool.lineWidth = 2
            pool.zPosition = 1
            return pool
            
        // Diamond room objects
        case "gem_1", "gem_2":
            let gem = SKLabelNode(text: "💎")
            gem.fontSize = 25
            gem.alpha = 0.9
            gem.zPosition = 2
            gem.fontName = "Arial"
            gem.horizontalAlignmentMode = .center
            gem.verticalAlignmentMode = .center
            return gem
            
        case "treasure_chest":
            let chest = SKLabelNode(text: "📦")
            chest.fontSize = 35
            chest.alpha = 0.9
            chest.zPosition = 2
            chest.fontName = "Arial"
            chest.horizontalAlignmentMode = .center
            chest.verticalAlignmentMode = .center
            return chest
            
        // Tree room objects
        case "ancient_tree":
            let tree = SKLabelNode(text: "🌳")
            tree.fontSize = 60
            tree.alpha = 0.8
            tree.zPosition = 2
            tree.fontName = "Arial"
            tree.horizontalAlignmentMode = .center
            tree.verticalAlignmentMode = .center
            return tree
            
        case "tree_hollow":
            let hollow = SKLabelNode(text: "🕳️")
            hollow.fontSize = 30
            hollow.alpha = 0.7
            hollow.zPosition = 2
            hollow.fontName = "Arial"
            hollow.horizontalAlignmentMode = .center
            hollow.verticalAlignmentMode = .center
            return hollow
            
        case "wisdom_stone":
            let stone = SKLabelNode(text: "🗿")
            stone.fontSize = 40
            stone.alpha = 0.9
            stone.zPosition = 2
            stone.fontName = "Arial"
            stone.horizontalAlignmentMode = .center
            stone.verticalAlignmentMode = .center
            return stone
            
        default:
            // Generic forest object
            let generic = SKLabelNode(text: "🌿")
            generic.fontSize = 25
            generic.alpha = 0.6
            generic.zPosition = 2
            generic.fontName = "Arial"
            generic.horizontalAlignmentMode = .center
            generic.verticalAlignmentMode = .center
            return generic
        }
    }
    
    /// Remove all special objects from current room
    private func removeSpecialObjects() {
        let objectNames = [
            "small_mushroom_1", "small_mushroom_2", "fairy_ring",
            "small_rock_1", "small_rock_2", "cave_entrance",
            "star_fragment_1", "star_fragment_2", "crystal_pool",
            "gem_1", "gem_2", "treasure_chest",
            "ancient_tree", "tree_hollow", "wisdom_stone"
        ]
        
        for objectName in objectNames {
            childNode(withName: objectName)?.removeFromParent()
        }
        
        print("🧹 Removed special objects from previous room")
    }
}