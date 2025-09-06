//
//  NPCResidentManager.swift
//  BobaAtDawn
//
//  Manages the living world where all NPCs are residents with homes in the forest
//

import SpriteKit
import Foundation

// MARK: - Resident Status
enum ResidentStatus: Equatable {
    case atHome(room: Int)
    case inShop
    case traveling
    
    var displayName: String {
        switch self {
        case .atHome(let room): return "At Home (Room \(room))"
        case .inShop: return "In Shop"
        case .traveling: return "Traveling"
        }
    }
}

// MARK: - NPC Resident
class NPCResident {
    let npcData: NPCData
    var status: ResidentStatus
    var shopNPC: NPC? // Reference to the actual NPC in shop
    var forestNPC: ForestNPC? // Reference to the actual NPC in forest
    var lastDrinkTime: TimeInterval?
    var drinkCooldown: TimeInterval = 0
    
    init(npcData: NPCData) {
        self.npcData = npcData
        self.status = .atHome(room: npcData.homeRoom)
    }
    
    var isAvailableForShop: Bool {
        return status == .atHome(room: npcData.homeRoom) && drinkCooldown <= 0
    }
    
    var needsToGoHome: Bool {
        return status == .inShop && drinkCooldown > 0
    }
}

// MARK: - NPC Resident Manager
class NPCResidentManager {
    static let shared = NPCResidentManager()
    
    private var residents: [NPCResident] = []
    private let targetShopNPCs = 3
    private let drinkCooldownDuration: TimeInterval = 300 // 5 minutes between shop visits
    
    // Scene references
    private weak var gameScene: GameScene?
    private weak var forestScene: ForestScene?
    
    private init() {
        loadAllResidents()
    }
    
    // MARK: - Initialization
    private func loadAllResidents() {
        let allNPCs = DialogueService.shared.getAllNPCs()
        residents = allNPCs.map { NPCResident(npcData: $0) }
        
        print("🏘️ Loaded \(residents.count) residents across forest rooms")
        printResidentDistribution()
    }
    
    private func printResidentDistribution() {
        for room in 1...5 {
            let roomResidents = residents.filter { $0.npcData.homeRoom == room }
            let names = roomResidents.map { $0.npcData.name }.joined(separator: ", ")
            print("🏠 Room \(room): \(names)")
        }
    }
    
    // MARK: - Scene Registration
    func registerGameScene(_ scene: GameScene) {
        self.gameScene = scene
        print("🏪 Game scene registered with resident manager")
    }
    
    func registerForestScene(_ scene: ForestScene) {
        self.forestScene = scene
        print("🌲 Forest scene registered with resident manager")
    }
    
    // MARK: - World Initialization
    func initializeWorld() {
        // Start 3 NPCs in the shop
        let initialShopNPCs = selectNPCsForShop(count: targetShopNPCs)
        
        for resident in initialShopNPCs {
            moveResidentToShop(resident)
        }
        
        // Place remaining NPCs in their home rooms
        spawnAllForestNPCs()
        
        print("🌍 World initialized: \(getShopNPCCount()) NPCs in shop, \(getForestNPCCount()) NPCs in forest")
        print("🌍 Starting time phase: \(lastKnownTimePhase.displayName)")
    }
    
    // MARK: - Shop NPC Management
    private func selectNPCsForShop(count: Int) -> [NPCResident] {
        let availableResidents = residents.filter { $0.isAvailableForShop }
        return Array(availableResidents.shuffled().prefix(count))
    }
    
    private func moveResidentToShop(_ resident: NPCResident) {
        guard let gameScene = gameScene else {
            print("❌ Cannot move resident to shop - no game scene registered")
            return
        }
        
        // Remove from forest if present
        resident.forestNPC?.removeFromParent()
        resident.forestNPC = nil
        
        // Create shop NPC
        let animalType = AnimalType.allCases.first { $0.characterId == resident.npcData.id } ?? .fox
        let shopNPC = gameScene.createShopNPC(animalType: animalType, resident: resident)
        
        resident.shopNPC = shopNPC
        resident.status = .inShop
        
        print("🏪 \(resident.npcData.name) moved to shop")
    }
    
    private func moveResidentToForest(_ resident: NPCResident) {
        // Remove from shop
        resident.shopNPC?.removeFromParent()
        resident.shopNPC = nil
        
        // Set cooldown
        resident.drinkCooldown = drinkCooldownDuration
        resident.lastDrinkTime = CACurrentMediaTime()
        
        // Move back to forest home
        resident.status = .atHome(room: resident.npcData.homeRoom)
        
        // If forest scene is active and matches home room, spawn there
        if let forestScene = forestScene, forestScene.currentRoom == resident.npcData.homeRoom {
            spawnForestNPC(resident, in: forestScene)
        }
        
        print("🏠 \(resident.npcData.name) returned home to room \(resident.npcData.homeRoom)")
    }
    
    // MARK: - Forest NPC Management
    private func spawnAllForestNPCs() {
        guard let forestScene = forestScene else { return }
        
        let currentRoom = forestScene.currentRoom
        let roomResidents = residents.filter { 
            $0.npcData.homeRoom == currentRoom && $0.status == .atHome(room: currentRoom)
        }
        
        for resident in roomResidents {
            spawnForestNPC(resident, in: forestScene)
        }
        
        print("🌲 Spawned \(roomResidents.count) forest NPCs in room \(currentRoom)")
    }
    
    private func spawnForestNPC(_ resident: NPCResident, in scene: ForestScene) {
        // Generate random position within forest bounds
        let margin: CGFloat = 150
        let worldWidth = scene.frame.width
        let worldHeight = scene.frame.height
        
        let xRange = (-worldWidth/2 + margin)...(worldWidth/2 - margin)
        let yRange = (-worldHeight/2 + margin)...(worldHeight/2 - margin)
        
        let randomX = CGFloat.random(in: xRange)
        let randomY = CGFloat.random(in: yRange)
        let position = CGPoint(x: randomX, y: randomY)
        
        // Create forest NPC
        let forestNPC = ForestNPC(npcData: resident.npcData, at: position)
        resident.forestNPC = forestNPC
        
        scene.addChild(forestNPC)
        print("🏠 Spawned \(resident.npcData.name) in their home (room \(resident.npcData.homeRoom))")
    }
    
    // MARK: - Time Phase Management
    private var lastKnownTimePhase: TimePhase = .day
    private var currentRitualNPCId: String? = nil // Track which NPC is currently in ritual
    
    func handleTimePhaseChange(_ newPhase: TimePhase) {
        guard newPhase != lastKnownTimePhase else { return }
        
        let oldPhase = lastKnownTimePhase
        lastKnownTimePhase = newPhase
        
        print("🌅 Time phase changed from \(oldPhase.displayName) to \(newPhase.displayName)")
        
        switch newPhase {
        case .dusk, .night, .dawn:
            // NPCs should leave the shop and go home (except ritual NPC during dawn)
            let excludeRitual = newPhase == .dawn
            print("🌅 Time phase: \(newPhase.displayName) - exclude ritual NPC: \(excludeRitual)")
            sendAllShopNPCsHome(excludeRitualNPC: excludeRitual)
        case .day:
            // NPCs can come to the shop
            maintainShopPopulation()
        }
    }
    
    private func sendAllShopNPCsHome(excludeRitualNPC: Bool = false) {
        let shopResidents = residents.filter { $0.status == .inShop }
        
        print("🌙 Sending \(shopResidents.count) NPCs home for the night...")
        
        if shopResidents.isEmpty {
            print("🌙 No NPCs currently in shop to send home")
            return
        }
        
        for resident in shopResidents {
            // Skip ritual NPC during dawn if specified
            if excludeRitualNPC && resident.npcData.id == currentRitualNPCId {
                print("🕯️ Keeping \(resident.npcData.name) in shop for dawn ritual")
                continue
            }
            
            if let shopNPC = resident.shopNPC {
                // Force NPCs to leave satisfied when going home for night
                print("🏠 \(resident.npcData.name) is heading home to room \(resident.npcData.homeRoom)")
                shopNPC.startLeaving(satisfied: true)
            } else {
                // If no shop NPC, just move them directly home
                print("🏠 Moving \(resident.npcData.name) directly home (no shop NPC found)")
                moveResidentToForest(resident)
            }
        }
    }
    
    // MARK: - Update System
    func update(deltaTime: TimeInterval) {
        // Update cooldowns
        for resident in residents {
            if resident.drinkCooldown > 0 {
                resident.drinkCooldown -= deltaTime
            }
        }
        
        // Only maintain shop population during day
        if lastKnownTimePhase == .day {
            maintainShopPopulation()
        }
    }
    
    private func maintainShopPopulation() {
        // Don't send NPCs to shop during dusk/night/dawn
        guard lastKnownTimePhase == .day else {
            print("🌙 Not maintaining shop population during \(lastKnownTimePhase.displayName)")
            return
        }
        
        let currentShopCount = getShopNPCCount()
        
        if currentShopCount < targetShopNPCs {
            let neededCount = targetShopNPCs - currentShopCount
            let availableResidents = residents.filter { $0.isAvailableForShop }
            
            if !availableResidents.isEmpty {
                let newShopNPCs = Array(availableResidents.shuffled().prefix(neededCount))
                
                for resident in newShopNPCs {
                    moveResidentToShop(resident)
                }
                
                print("🏪 Sent \(newShopNPCs.count) NPCs to shop to maintain population")
            }
        }
    }
    
    // MARK: - NPC Lifecycle Events
    func npcLeftShop(_ npc: NPC, satisfied: Bool) {
        // Find the resident for this NPC
        guard let resident = residents.first(where: { $0.shopNPC === npc }) else {
            print("❌ Could not find resident for departing NPC")
            return
        }
        
        print("🚪 \(resident.npcData.name) left shop (\(satisfied ? "satisfied" : "disappointed"))")
        
        // Move resident back to forest
        moveResidentToForest(resident)
        
        // Trigger shop population maintenance
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.maintainShopPopulation()
        }
    }
    
    // MARK: - Forest Room Changes
    func forestRoomChanged(to newRoom: Int, scene: ForestScene) {
        // Clear existing forest NPCs from scene
        clearForestNPCs(from: scene)
        
        // Update forest scene reference
        self.forestScene = scene
        
        // Spawn NPCs for the new room
        spawnRoomNPCs(room: newRoom, in: scene)
    }
    
    private func clearForestNPCs(from scene: ForestScene) {
        for resident in residents {
            resident.forestNPC?.removeFromParent()
            resident.forestNPC = nil
        }
    }
    
    private func spawnRoomNPCs(room: Int, in scene: ForestScene) {
        let roomResidents = residents.filter { 
            $0.npcData.homeRoom == room && $0.status == .atHome(room: room)
        }
        
        for resident in roomResidents {
            spawnForestNPC(resident, in: scene)
        }
        
        print("🌲 Room \(room): Spawned \(roomResidents.count) residents")
    }
    
    // MARK: - Status Queries
    func getShopNPCCount() -> Int {
        return residents.filter { $0.status == .inShop }.count
    }
    
    func getForestNPCCount() -> Int {
        return residents.filter { 
            if case .atHome = $0.status { return true }
            return false
        }.count
    }
    
    func getResidentsInRoom(_ room: Int) -> [NPCResident] {
        return residents.filter { $0.npcData.homeRoom == room && $0.status == .atHome(room: room) }
    }
    
    func getAllResidents() -> [NPCResident] {
        return residents
    }
    
    // MARK: - Debug Info
    func printStatus() {
        print("🌍 === RESIDENT MANAGER STATUS ===")
        print("🌅 Current Time Phase: \(lastKnownTimePhase.displayName)")
        print("🏪 Shop NPCs: \(getShopNPCCount())/\(targetShopNPCs)")
        print("🌲 Forest NPCs: \(getForestNPCCount())")
        
        for room in 1...5 {
            let roomCount = getResidentsInRoom(room).count
            print("🏠 Room \(room): \(roomCount) residents")
        }
        
        print("🕒 Cooldown status:")
        for resident in residents {
            if resident.drinkCooldown > 0 {
                let minutes = Int(resident.drinkCooldown / 60)
                let seconds = Int(resident.drinkCooldown.truncatingRemainder(dividingBy: 60))
                print("   \(resident.npcData.name): \(minutes)m \(seconds)s remaining")
            }
        }
        print("================================")
    }
    
    // MARK: - Ritual NPC Management
    func setRitualNPC(_ npcId: String) {
        currentRitualNPCId = npcId
        print("🕯️ \(npcId) is now the ritual NPC")
    }
    
    func clearRitualNPC() {
        if let ritualId = currentRitualNPCId {
            print("🕯️ \(ritualId) is no longer the ritual NPC")
        }
        currentRitualNPCId = nil
    }
}
