//
//  StandardNPCService.swift
//  BobaAtDawn
//
//  Standard implementation of NPCService
//

import SpriteKit

class StandardNPCService: NPCService {
    
    private let gridService: GridService
    private let timeService: TimeService
    
    init(gridService: GridService, timeService: TimeService) {
        self.gridService = gridService
        self.timeService = timeService
        print("🦊 StandardNPCService initialized with injected dependencies")
    }
    
    // MARK: - NPC Lifecycle
    
    func spawnNPC(animal: AnimalType? = nil, at position: GridCoordinate? = nil) -> NPC {
        // Choose random animal if not specified
        let selectedAnimal = animal ?? selectAnimalForSpawn(isNight: timeService.currentPhase == .night)
        
        // Default start position (at front door)
        let doorPosition = GameConfig.World.doorGridPosition  // FIXED: Use new property name
        let startPosition = position ?? doorPosition
        
        // Create NPC with dependencies injected
        let npc = NPC(animal: selectedAnimal, 
                      startPosition: startPosition,
                      gridService: gridService,
                      npcService: self)
        
        // Add entrance animation
        addEntranceAnimation(for: npc)
        
        print("🦊 ✨ SPAWNED \(selectedAnimal.rawValue) at \(startPosition)")
        return npc
    }
    
    func updateNPCs(_ npcs: inout [NPC], deltaTime: TimeInterval, currentTime: TimeInterval) {
        // Update existing NPCs
        for npc in npcs {
            npc.update(deltaTime: deltaTime)
        }
        
        // Clean up departed NPCs
        cleanupDepartedNPCs(&npcs)
    }
    
    func cleanupDepartedNPCs(_ npcs: inout [NPC]) {
        let initialCount = npcs.count
        npcs.removeAll { npc in
            if npc.parent == nil {
                print("🦊 Cleaned up departed NPC \(npc.animalType.rawValue)")
                return true
            }
            return false
        }
        
        // Log if NPCs were cleaned up
        if npcs.count < initialCount {
            print("🦊 NPC cleanup: \(initialCount - npcs.count) NPCs removed, \(npcs.count) remain")
        }
    }
    
    // MARK: - Spawn Logic
    
    func shouldSpawnNPC(currentTime: TimeInterval, lastSpawnTime: TimeInterval, currentNPCCount: Int, maxNPCs: Int) -> Bool {
        // Don't spawn if at capacity
        guard currentNPCCount < maxNPCs else { return false }
        
        // Calculate spawn interval based on time of day
        let spawnInterval = getSpawnInterval(currentNPCCount: currentNPCCount, maxNPCs: maxNPCs)
        let timeSinceLastSpawn = currentTime - lastSpawnTime
        
        return timeSinceLastSpawn > spawnInterval
    }
    
    func getSpawnInterval(currentNPCCount: Int, maxNPCs: Int) -> TimeInterval {
        // Base interval based on time of day
        let baseInterval: TimeInterval
        
        switch timeService.currentPhase {
        case .day:
            baseInterval = GameConfig.NPC.daySpawnInterval
        case .dusk:
            baseInterval = GameConfig.NPC.duskSpawnInterval
        case .night:
            baseInterval = GameConfig.NPC.nightSpawnInterval
        case .dawn:
            return GameConfig.NPC.dawnSpawnInterval // No spawning during dawn
        }
        
        // Dynamic adjustments based on shop state
        let currentOccupancy = Double(currentNPCCount) / Double(maxNPCs)
        let occupancyMultiplier = 1.0 + (currentOccupancy * GameConfig.NPC.occupancyMultiplierMax)
        
        let finalInterval = baseInterval * occupancyMultiplier
        
        print("🦊 Spawn timing: base=\(baseInterval)s, occupancy=\(String(format: "%.1f", occupancyMultiplier))x, final=\(String(format: "%.1f", finalInterval))s")
        
        return finalInterval
    }
    
    func selectAnimalForSpawn(isNight: Bool) -> AnimalType {
        if isNight {
            // Night: 70% normal animals, 30% mysterious night visitors
            if Int.random(in: 1...10) <= GameConfig.NPC.nightVisitorChance {
                return AnimalType.nightAnimals.randomElement() ?? .owl
            } else {
                return AnimalType.dayAnimals.randomElement() ?? .fox
            }
        } else {
            // Day/Dusk: mostly normal animals with some variety
            let allDayAnimals = AnimalType.dayAnimals
            return allDayAnimals.randomElement() ?? .fox
        }
    }
    
    // MARK: - Scene Interaction
    
    func findAvailableTables(in scene: SKScene) -> [RotatableObject] {
        var tables: [RotatableObject] = []
        scene.enumerateChildNodes(withName: "table") { node, _ in
            if let table = node as? RotatableObject {
                let tableGridPos = self.gridService.worldToGrid(table.position)
                if tableGridPos.adjacentCells.contains(where: { self.gridService.isCellAvailable($0) }) {
                    tables.append(table)
                }
            }
        }
        
        print("🦊 Found \(tables.count) available tables in scene")
        return tables
    }
    
    func countTablesWithDrinks(in scene: SKScene) -> Int {
        var count = 0
        scene.enumerateChildNodes(withName: "table") { node, _ in
            if let table = node as? RotatableObject {
                if table.children.contains(where: { $0.name == "drink_on_table" }) {
                    count += 1
                }
            }
        }
        return count
    }
    
    // MARK: - NPC Behavior Helpers
    
    func generateCandidateCells(from position: GridCoordinate, radius: Int) -> [GridCoordinate] {
        var candidates: [GridCoordinate] = []
        
        for dx in -radius...radius {
            for dy in -radius...radius {
                if dx == 0 && dy == 0 { continue } // Skip current position
                
                let candidate = GridCoordinate(x: position.x + dx, y: position.y + dy)
                
                // Keep NPCs within shop bounds using configuration
                let shopBounds = GameConfig.Grid.ShopBounds.self
                
                if candidate.x >= shopBounds.minX && candidate.x <= shopBounds.maxX &&
                   candidate.y >= shopBounds.minY && candidate.y <= shopBounds.maxY &&
                   candidate.isValid() && gridService.isCellAvailable(candidate) {
                    candidates.append(candidate)
                }
            }
        }
        
        return candidates
    }
    
    func findPathToExit(from position: GridCoordinate) -> GridCoordinate? {
        // Move toward front door (exit) - improved pathfinding
        let doorPosition = GameConfig.World.doorGridPosition  // FIXED: Use new property name
        
        // Calculate direction to door
        let deltaX = doorPosition.x - position.x
        let deltaY = doorPosition.y - position.y
        
        // Move one step closer (prioritize x movement to get to door area)
        let stepX = deltaX != 0 ? (deltaX > 0 ? 1 : -1) : 0
        let stepY = deltaY != 0 ? (deltaY > 0 ? 1 : -1) : 0
        
        // Try X movement first (toward door), then Y if needed
        var targetCell: GridCoordinate
        if abs(deltaX) > abs(deltaY) || deltaX != 0 {
            targetCell = GridCoordinate(x: position.x + stepX, y: position.y)
        } else {
            targetCell = GridCoordinate(x: position.x, y: position.y + stepY)
        }
        
        // Ensure target is valid and available
        if targetCell.isValid() && gridService.isCellAvailable(targetCell) {
            return targetCell
        } else {
            // If direct path blocked, try alternative
            let alternativeCell = GridCoordinate(x: position.x + stepY, y: position.y + stepX)
            if alternativeCell.isValid() && gridService.isCellAvailable(alternativeCell) {
                return alternativeCell
            }
        }
        
        return nil
    }
    
    func isNearExit(_ position: GridCoordinate) -> Bool {
        return position.x <= GameConfig.NPC.exitThreshold && 
               abs(position.y - GameConfig.World.doorGridPosition.y) <= GameConfig.NPC.exitYTolerance  // FIXED: Use new property name
    }
    
    // MARK: - Animations
    
    private func addEntranceAnimation(for npc: NPC) {
        // Subtle entrance effect
        npc.alpha = GameConfig.NPC.Animations.entranceStartAlpha
        npc.setScale(GameConfig.NPC.Animations.entranceStartScale)
        
        let entranceAnimation = SKAction.group([
            SKAction.fadeIn(withDuration: GameConfig.NPC.Animations.entranceDuration),
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.entranceDuration)
        ])
        entranceAnimation.timingMode = .easeOut
        
        npc.run(entranceAnimation)
        
        print("🎭 Added entrance animation for \(npc.animalType.rawValue)")
    }
}
