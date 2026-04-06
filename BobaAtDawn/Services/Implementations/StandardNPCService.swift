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
        Log.info(.npc, "StandardNPCService initialized")
    }
    
    // MARK: - NPC Lifecycle
    
    func spawnNPC(animal: AnimalType? = nil, at position: GridCoordinate? = nil) -> ShopNPC {
        let selectedAnimal = animal ?? selectAnimalForSpawn(isNight: timeService.currentPhase == .night)
        let startPosition = position ?? GameConfig.World.doorGridPosition
        
        let npc = ShopNPC(animal: selectedAnimal,
                          startPosition: startPosition,
                          gridService: gridService,
                          npcService: self)
        
        addEntranceAnimation(for: npc)
        Log.info(.npc, "Spawned \(selectedAnimal.rawValue) at \(startPosition)")
        return npc
    }
    
    func updateNPCs(_ npcs: inout [ShopNPC], deltaTime: TimeInterval, currentTime: TimeInterval) {
        for npc in npcs { npc.update(deltaTime: deltaTime) }
        cleanupDepartedNPCs(&npcs)
    }
    
    func cleanupDepartedNPCs(_ npcs: inout [ShopNPC]) {
        let before = npcs.count
        npcs.removeAll { $0.parent == nil }
        if npcs.count < before {
            Log.debug(.npc, "Cleanup: \(before - npcs.count) removed, \(npcs.count) remain")
        }
    }
    
    // MARK: - Spawn Logic
    
    func shouldSpawnNPC(currentTime: TimeInterval, lastSpawnTime: TimeInterval,
                        currentNPCCount: Int, maxNPCs: Int) -> Bool {
        guard currentNPCCount < maxNPCs else { return false }
        let interval = getSpawnInterval(currentNPCCount: currentNPCCount, maxNPCs: maxNPCs)
        return (currentTime - lastSpawnTime) > interval
    }
    
    func getSpawnInterval(currentNPCCount: Int, maxNPCs: Int) -> TimeInterval {
        let base: TimeInterval
        switch timeService.currentPhase {
        case .day:   base = GameConfig.NPC.daySpawnInterval
        case .dusk:  base = GameConfig.NPC.duskSpawnInterval
        case .night: base = GameConfig.NPC.nightSpawnInterval
        case .dawn:  return GameConfig.NPC.dawnSpawnInterval
        }
        let occupancy = Double(currentNPCCount) / Double(max(1, maxNPCs))
        return base * (1.0 + occupancy * GameConfig.NPC.occupancyMultiplierMax)
    }
    
    func selectAnimalForSpawn(isNight: Bool) -> AnimalType {
        if isNight && Int.random(in: 1...10) <= GameConfig.NPC.nightVisitorChance {
            return AnimalType.nightAnimals.randomElement() ?? .owl
        }
        return AnimalType.dayAnimals.randomElement() ?? .fox
    }
    
    // MARK: - Scene Interaction
    
    func findAvailableTables(in scene: SKScene) -> [RotatableObject] {
        var tables: [RotatableObject] = []
        scene.enumerateChildNodes(withName: "table") { node, _ in
            if let table = node as? RotatableObject {
                let pos = self.gridService.worldToGrid(table.position)
                if pos.adjacentCells.contains(where: { self.gridService.isCellAvailable($0) }) {
                    tables.append(table)
                }
            }
        }
        return tables
    }
    
    func countTablesWithDrinks(in scene: SKScene) -> Int {
        var count = 0
        scene.enumerateChildNodes(withName: "table") { node, _ in
            if let table = node as? RotatableObject,
               table.children.contains(where: { $0.name == "drink_on_table" }) {
                count += 1
            }
        }
        return count
    }
    
    // MARK: - Behavior Helpers
    
    func generateCandidateCells(from position: GridCoordinate, radius: Int) -> [GridCoordinate] {
        var candidates: [GridCoordinate] = []
        let bounds = GameConfig.Grid.ShopBounds.self
        
        for dx in -radius...radius {
            for dy in -radius...radius {
                if dx == 0 && dy == 0 { continue }
                let c = GridCoordinate(x: position.x + dx, y: position.y + dy)
                if c.x >= bounds.minX && c.x <= bounds.maxX &&
                   c.y >= bounds.minY && c.y <= bounds.maxY &&
                   c.isValid() && gridService.isCellAvailable(c) {
                    candidates.append(c)
                }
            }
        }
        return candidates
    }
    
    func findPathToExit(from position: GridCoordinate) -> GridCoordinate? {
        let door = GameConfig.World.doorGridPosition
        let dx = door.x - position.x
        let dy = door.y - position.y
        let sx = dx != 0 ? (dx > 0 ? 1 : -1) : 0
        let sy = dy != 0 ? (dy > 0 ? 1 : -1) : 0
        
        let primary: GridCoordinate
        if abs(dx) > abs(dy) || dx != 0 {
            primary = GridCoordinate(x: position.x + sx, y: position.y)
        } else {
            primary = GridCoordinate(x: position.x, y: position.y + sy)
        }
        
        if primary.isValid() && gridService.isCellAvailable(primary) { return primary }
        
        let alt = GridCoordinate(x: position.x + sy, y: position.y + sx)
        if alt.isValid() && gridService.isCellAvailable(alt) { return alt }
        
        return nil
    }
    
    func isNearExit(_ position: GridCoordinate) -> Bool {
        let door = GameConfig.World.doorGridPosition
        let dist = hypot(Float(position.x - door.x), Float(position.y - door.y))
        return dist <= 3.0
    }
    
    // MARK: - Animation
    
    private func addEntranceAnimation(for npc: ShopNPC) {
        npc.alpha = GameConfig.NPC.Animations.entranceStartAlpha
        npc.setScale(GameConfig.NPC.Animations.entranceStartScale)
        let anim = SKAction.group([
            SKAction.fadeIn(withDuration: GameConfig.NPC.Animations.entranceDuration),
            SKAction.scale(to: 1.0, duration: GameConfig.NPC.Animations.entranceDuration)
        ])
        anim.timingMode = .easeOut
        npc.run(anim)
    }
}
