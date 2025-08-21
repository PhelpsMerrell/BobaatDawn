//
//  NPCService.swift
//  BobaAtDawn
//
//  Service protocol for NPC management and behavior
//

import SpriteKit

protocol NPCService {
    // NPC lifecycle
    func spawnNPC(animal: AnimalType?, at position: GridCoordinate?) -> NPC
    func updateNPCs(_ npcs: inout [NPC], deltaTime: TimeInterval, currentTime: TimeInterval)
    func cleanupDepartedNPCs(_ npcs: inout [NPC])
    
    // Spawn timing and logic
    func shouldSpawnNPC(currentTime: TimeInterval, lastSpawnTime: TimeInterval, currentNPCCount: Int, maxNPCs: Int) -> Bool
    func getSpawnInterval(currentNPCCount: Int, maxNPCs: Int) -> TimeInterval
    func selectAnimalForSpawn(isNight: Bool) -> AnimalType
    
    // Table and scene interaction
    func findAvailableTables(in scene: SKScene) -> [RotatableObject]
    func countTablesWithDrinks(in scene: SKScene) -> Int
    
    // NPC behavior helpers
    func generateCandidateCells(from position: GridCoordinate, radius: Int) -> [GridCoordinate]
    func findPathToExit(from position: GridCoordinate) -> GridCoordinate?
    func isNearExit(_ position: GridCoordinate) -> Bool
}
