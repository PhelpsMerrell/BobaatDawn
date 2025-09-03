//
//  GameConfiguration.swift
//  BobaAtDawn
//
//  Centralized configuration for all game constants and tunable values
//

import SpriteKit

// MARK: - Main Configuration Container
struct GameConfig {
    
    // MARK: - World Configuration
    struct World {
        static let width: CGFloat = 2000
        static let height: CGFloat = 1500
        
        // Scene bounds and safe areas
        static let wallThickness: CGFloat = 40
        static let wallInset: CGFloat = 20
        
        // FIXED: Door positioning using grid coordinates
        static let doorGridPosition = GridCoordinate(x: 1, y: 12)  // Left wall, center height
        static let doorSize: CGFloat = 80
        
        // FIXED: Shop floor area using grid coordinates
        // Define rectangular area under brewing stations
        static let shopFloorArea = (
            topLeft: GridCoordinate(x: 10, y: 8),
            bottomRight: GridCoordinate(x: 23, y: 18)
        )
        static let shopFloorColor = SKColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.6)
        
        // Background colors
        static let backgroundColor = SKColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 1.0)
        static let floorColor = SKColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1.0)
        static let wallColor = SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0)
    }
    
    // MARK: - Grid System Configuration
    struct Grid {
        static let cellSize: CGFloat = 60
        static let columns = 33
        static let rows = 25
        
        // FIXED: Center the grid in the world
        // Grid total size: 33*60 = 1980w, 25*60 = 1500h
        // Centered origin: -990, -750
        static let shopOrigin = CGPoint(x: -990, y: -750)
        
        // Character starting position (center of world)
        static let characterStartPosition = GridCoordinate(x: 16, y: 12)
        
        // Shop boundaries for NPCs (keep them away from edges)
        struct ShopBounds {
            static let minX = 3
            static let maxX = 29
            static let minY = 3
            static let maxY = 21
        }
    }
    
    // MARK: - Character Configuration
    struct Character {
        static let size = CGSize(width: 40, height: 60)
        static let color = SKColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
        static let carryOffset: CGFloat = 80
        static let zPosition: CGFloat = 10
        
        // Movement configuration
        static let baseMovementSpeed: CGFloat = 300 // Points per second
        static let minMovementDuration: TimeInterval = 0.15
        static let maxMovementDuration: TimeInterval = 0.6
        
        // Carried item floating animation
        static let floatDistance: CGFloat = 5
        static let floatDuration: TimeInterval = 1.0
    }
    
    // MARK: - Camera Configuration
    struct Camera {
        static let lerpSpeed: CGFloat = 2.0
        static let defaultScale: CGFloat = 1.0
        static let minZoom: CGFloat = 0.3
        static let maxZoom: CGFloat = 1.5
        
        // Camera bounds (how close to edges camera can go)
        static let edgeInset: CGFloat = 80
        
        // Gesture configuration
        static let zoomResetDuration: TimeInterval = 0.3
    }
    
    // MARK: - Ingredient Stations Configuration
    struct IngredientStations {
        static let size = CGSize(width: 80, height: 80)
        static let spacing: CGFloat = 2 // Grid cells between stations
        static let baseRow = 15 // Y coordinate for all stations
        
        // Station positions (X coordinates)
        static let iceColumn = 12
        static let bobaColumn = 14
        static let foamColumn = 16
        static let teaColumn = 18
        static let lidColumn = 20
        
        // DrinkCreator position
        static let drinkCreatorPosition = GridCoordinate(x: 16, y: 13)
        
        // Station colors
        static let iceColor = SKColor.cyan
        static let bobaColor = SKColor.black
        static let foamColor = SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1.0)
        static let teaColor = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0)
        static let lidColor = SKColor.gray
        
        // Interaction feedback
        static let interactionScaleAmount: CGFloat = 1.2
        static let interactionDuration: TimeInterval = 0.1
    }
    
    // MARK: - NPC Configuration
    struct NPC {
        static let fontSize: CGFloat = 36
        static let fontName = "Arial"
        static let zPosition: CGFloat = 12
        static let maxNPCs = 3
        
        // Movement configuration
        static let moveSpeed: TimeInterval = 1.2
        static let wanderRadius = 3 // Grid cells
        static let exitThreshold = 6 // How close to door is "near exit"
        static let exitYTolerance = 2 // Y-axis tolerance for exit area
        
        // Behavior timing (in seconds)
        static let enteringDuration = (min: 5.0, max: 10.0)
        static let wanderingDuration = (min: 30.0, max: 60.0)
        static let sittingTimeout = (min: 60.0, max: 120.0)
        static let drinkEnjoymentTime = (min: 5.0, max: 10.0)
        static let maxLifetime: TimeInterval = 300 // 5 minutes safety timeout
        
        // Spawn timing based on time of day
        static let daySpawnInterval: TimeInterval = 15.0
        static let duskSpawnInterval: TimeInterval = 25.0
        static let nightSpawnInterval: TimeInterval = 45.0
        static let dawnSpawnInterval: TimeInterval = 999 // No spawning during dawn
        
        // Dynamic spawn adjustments
        static let occupancyMultiplierMax: Double = 0.5
        static let drinkBonusMultiplier: Double = 0.7 // 30% faster when drinks available
        
        // Night visitor probability (out of 10)
        static let nightVisitorChance = 3 // 30% chance for mysterious night animals
        
        // Animation configuration
        struct Animations {
            // Entrance
            static let entranceDuration: TimeInterval = 0.5
            static let entranceStartAlpha: CGFloat = 0.0
            static let entranceStartScale: CGFloat = 0.8
            
            // Happy leaving (satisfied customers)
            static let shimmerScaleAmount: CGFloat = 1.15
            static let shimmerDuration: TimeInterval = 0.25
            static let shakeDistance: CGFloat = 3
            static let shakeDuration: TimeInterval = 0.1
            static let colorFlashDuration: TimeInterval = 0.2
            static let happyCelebrationTime = (min: 5.0, max: 10.0)
            
            // Neutral leaving (disappointed customers)
            static let neutralScaleAmount: CGFloat = 0.95
            static let neutralSighDuration: TimeInterval = 1.0
            static let neutralGrayBlend: CGFloat = 0.15
            static let neutralFadeDuration: TimeInterval = 0.5
            
            // Animation reset
            static let resetDuration: TimeInterval = 0.2
        }
        
        // Carried drink configuration
        struct CarriedDrink {
            static let size = CGSize(width: 25, height: 35)
            static let carryOffset = CGPoint(x: 0, y: 50)
            static let lidSize = CGSize(width: 20, height: 5)
            static let lidOffset = CGPoint(x: 0, y: 15)
            static let strawSize = CGSize(width: 2, height: 25)
            static let strawOffset = CGPoint(x: 8, y: 10)
            static let floatDistance: CGFloat = 3
            static let floatDuration: TimeInterval = 1.0
        }
    }
    
    // MARK: - Touch & Interaction Configuration
    struct Touch {
        static let longPressDuration: TimeInterval = 0.8
        static let interactionSearchDepth = 5 // How many parent nodes to check
        
        // Feedback configuration
        static let occupiedCellFeedbackRadius: CGFloat = 18 // 30% of cell size
        static let feedbackColor = SKColor.orange.withAlphaComponent(0.4)
        static let feedbackLineWidth: CGFloat = 2
        static let feedbackZPosition: CGFloat = 5
        
        // Feedback animation timing
        static let feedbackScaleAmount: CGFloat = 1.2
        static let feedbackScaleDuration: TimeInterval = 0.15
        static let feedbackWaitDuration: TimeInterval = 0.2
        static let feedbackFadeDuration: TimeInterval = 0.4
    }
    
    // MARK: - Time System Configuration
    struct Time {
        // Phase durations (in seconds)
        static let dawnDuration: TimeInterval = 4 * 60  // 4 minutes
        static let dayDuration: TimeInterval = 12 * 60  // 12 minutes  
        static let duskDuration: TimeInterval = 4 * 60  // 4 minutes
        static let nightDuration: TimeInterval = 12 * 60 // 12 minutes
        
        // FIXED: Time system positioning using grid coordinates
        static let breakerGridPosition = GridCoordinate(x: 3, y: 20)   // Top-left area
        static let windowGridPosition = GridCoordinate(x: 28, y: 18)   // Top-right area
        static let labelGridPosition = GridCoordinate(x: 28, y: 18)    // Same as window
        
        // Time display configuration
        static let labelFontSize: CGFloat = 24
        static let labelFontName = "Arial-Bold"
        static let labelZPosition: CGFloat = 11
        
        // Phase colors
        static let dawnColor = SKColor.systemPink
        static let dayColor = SKColor.blue
        static let duskColor = SKColor.orange
        static let nightColor = SKColor.purple
    }
    
    // MARK: - Table Service Configuration
    struct TableService {
        // Table drink positioning
        static let drinkOnTableOffset = CGPoint(x: 0, y: 25)
        static let drinkOnTableZPosition: CGFloat = 1
        static let drinkOnTableSize = CGSize(width: 20, height: 30)
        
        // Table drink components
        static let tableLidSize = CGSize(width: 16, height: 4)
        static let tableLidOffset = CGPoint(x: 0, y: 12)
        static let tableStrawSize = CGSize(width: 2, height: 20)
        static let tableStrawOffset = CGPoint(x: 6, y: 8)
        
        // Colors
        static let tableLidColor = SKColor.lightGray
        static let tableStrawColor = SKColor.white
    }
    
    // MARK: - Forest Transition Configuration
    struct ForestTransition {
        static let fadeOutDuration: TimeInterval = 0.5
        static let fadeInDuration: TimeInterval = 0.5
        static let sceneTransitionDuration: TimeInterval = 0.5
    }
    
    // MARK: - Object Configuration
    struct Objects {
        static let defaultSize = CGSize(width: 60, height: 60)
        static let defaultZPosition: CGFloat = 3
        static let carryZPosition: CGFloat = 15
        
        // Rotation configuration
        static let rotationDuration: TimeInterval = 0.3
        static let rotationFeedbackScale: CGFloat = 1.1
        static let rotationFeedbackDuration: TimeInterval = 0.15
        
        // Visual indicators
        static let indicatorAlpha: CGFloat = 0.8
        static let cornerIndicatorAlpha: CGFloat = 0.4
        static let stationIndicatorAlpha: CGFloat = 0.7
        
        // Table configuration
        static let tableColor = SKColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1.0)
        static let tableCenterDotSize = CGSize(width: 8, height: 8)
        static let tableCornerDotSize = CGSize(width: 4, height: 4)
        static let tableIndicatorOffset: CGFloat = 20
    }
    
    // MARK: - Animation Configuration
    struct Animation {
        // Basic animation defaults
        static let defaultDuration: TimeInterval = 0.3
        static let quickDuration: TimeInterval = 0.15
        static let slowDuration: TimeInterval = 0.6
        
        // Pulse effects
        static let pulseScale: CGFloat = 1.1
        static let pulseDuration: TimeInterval = 0.2
        
        // Floating effects
        static let floatDistance: CGFloat = 5.0
        static let floatDuration: TimeInterval = 1.0
        
        // Fade effects
        static let fadeInDuration: TimeInterval = 0.3
        static let fadeOutDuration: TimeInterval = 0.3
        
        // Scale feedback
        static let feedbackScale: CGFloat = 1.15
        static let feedbackDuration: TimeInterval = 0.1
        
        // Entrance animations
        static let entranceDuration: TimeInterval = 0.5
        static let entranceStartScale: CGFloat = 0.8
        static let entranceStartAlpha: CGFloat = 0.0
    }
    
    // MARK: - Debug Configuration
    struct Debug {
        static let showGridOverlay = false
        static let gridOverlayAlpha: CGFloat = 0.1
        static let gridOverlayZPosition: CGFloat = -5
        static let logNPCStatusInterval: TimeInterval = 5.0 // Every 5 seconds
    }
}

// MARK: - Convenience Extensions
extension GameConfig {
    
    // FIXED: Grid positioning helpers
    
    /// Convert grid coordinate to world position using current grid settings
    static func gridToWorld(_ gridPos: GridCoordinate) -> CGPoint {
        let x = Grid.shopOrigin.x + (CGFloat(gridPos.x) * Grid.cellSize) + (Grid.cellSize / 2)
        let y = Grid.shopOrigin.y + (CGFloat(gridPos.y) * Grid.cellSize) + (Grid.cellSize / 2)
        return CGPoint(x: x, y: y)
    }
    
    /// Get world position for time system components
    static func timeSystemPositions() -> (breaker: CGPoint, window: CGPoint, label: CGPoint) {
        return (
            breaker: gridToWorld(Time.breakerGridPosition),
            window: gridToWorld(Time.windowGridPosition),
            label: gridToWorld(Time.labelGridPosition)
        )
    }
    
    /// Get world position for door
    static func doorWorldPosition() -> CGPoint {
        return gridToWorld(World.doorGridPosition)
    }
    
    /// Get shop floor rectangle in world coordinates - FIXED
    static func shopFloorRect() -> (position: CGPoint, size: CGSize) {
        // Calculate the rectangle more carefully
        let topLeftGrid = World.shopFloorArea.topLeft
        let bottomRightGrid = World.shopFloorArea.bottomRight
        
        print("🔍 shopFloorRect debug:")
        print("   topLeft grid: \(topLeftGrid)")
        print("   bottomRight grid: \(bottomRightGrid)")
        
        // Calculate grid dimensions
        let gridWidth = bottomRightGrid.x - topLeftGrid.x + 1  // +1 to include both endpoints
        let gridHeight = bottomRightGrid.y - topLeftGrid.y + 1
        
        print("   grid dimensions: \(gridWidth) x \(gridHeight) cells")
        
        // Convert to world dimensions
        let width = CGFloat(gridWidth) * Grid.cellSize
        let height = CGFloat(gridHeight) * Grid.cellSize
        
        print("   world dimensions: \(width) x \(height)")
        
        // Calculate center position
        let centerGridX = (topLeftGrid.x + bottomRightGrid.x) / 2
        let centerGridY = (topLeftGrid.y + bottomRightGrid.y) / 2
        let centerGrid = GridCoordinate(x: centerGridX, y: centerGridY)
        let centerWorld = gridToWorld(centerGrid)
        
        let calculatedSize = CGSize(width: width, height: height)
        print("   final size: \(calculatedSize)")
        print("   final position: \(centerWorld)")
        
        // Validation
        guard calculatedSize.width > 0 && calculatedSize.height > 0 else {
            print("❌ CRITICAL: shopFloorRect calculated invalid size: \(calculatedSize)")
            // Return a safe fallback size
            return (
                position: CGPoint(x: 0, y: 0),
                size: CGSize(width: 780, height: 600)  // Reasonable fallback
            )
        }
        
        return (
            position: centerWorld,
            size: calculatedSize
        )
    }
    
    // Get ingredient station position by type
    static func stationPosition(for type: IngredientStation.StationType) -> GridCoordinate {
        let column: Int
        switch type {
        case .ice: column = IngredientStations.iceColumn
        case .boba: column = IngredientStations.bobaColumn  
        case .foam: column = IngredientStations.foamColumn
        case .tea: column = IngredientStations.teaColumn
        case .lid: column = IngredientStations.lidColumn
        }
        return GridCoordinate(x: column, y: IngredientStations.baseRow)
    }
    
    // Get station color by type
    static func stationColor(for type: IngredientStation.StationType) -> SKColor {
        switch type {
        case .ice: return IngredientStations.iceColor
        case .boba: return IngredientStations.bobaColor
        case .foam: return IngredientStations.foamColor
        case .tea: return IngredientStations.teaColor
        case .lid: return IngredientStations.lidColor
        }
    }
    
    // Get spawn interval for current time phase
    static func spawnInterval(for phase: TimePhase) -> TimeInterval {
        switch phase {
        case .day: return NPC.daySpawnInterval
        case .dusk: return NPC.duskSpawnInterval
        case .night: return NPC.nightSpawnInterval
        case .dawn: return NPC.dawnSpawnInterval
        }
    }
    
    // Get time phase color
    static func timePhaseColor(for phase: TimePhase) -> SKColor {
        switch phase {
        case .dawn: return Time.dawnColor
        case .day: return Time.dayColor
        case .dusk: return Time.duskColor
        case .night: return Time.nightColor
        }
    }
}
