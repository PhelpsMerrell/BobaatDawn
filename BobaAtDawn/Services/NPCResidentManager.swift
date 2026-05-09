//
//  NPCResidentManager.swift
//  BobaAtDawn
//
//  Manages the living world where all NPCs are persistent residents
//  with homes in the forest.
//

import SpriteKit
import Foundation

// MARK: - Resident Status
//
// Coarse logical position of an NPC. The activity runner mutates
// this through the day; visuals (`ForestNPCEntity`, `ShopNPC`) are
// spawned/despawned by `NPCResidentManager` based on whether the
// player's current scene matches the resident's status.
//
// Persistence: only `.atHome(_)`, `.inShop`, and `.traveling` are
// serialized today (the existing schema). The newer in-transit
// states are transient — they only survive within a single day.
// At dawn the scheduler reroils plans and the runner resets every
// resident to `.atHome` before picking the day's first activity.
enum ResidentStatus: Equatable {
    case atHome(room: Int)
    case inShop
    case traveling

    /// Walking through (or actively foraging in) a forest room.
    /// Used during `forageAndTrade` while the NPC is in the woods
    /// before continuing on to the oak lobby.
    case inForestRoom(Int)

    /// Standing at the broker's desk in the big oak lobby for a
    /// trade. Used during `forageAndTrade`.
    case inOakLobby

    /// Inside a cave room (room 2 or 3) gathering mushrooms.
    /// Used during `gatherCaveMushrooms`.
    case inCaveRoom(Int)

    /// Visiting a friend at their cabin. The associated room is the
    /// friend's home room. Used during `visitFriend`.
    case atFriendHouse(npcID: String, room: Int)

    var displayName: String {
        switch self {
        case .atHome(let room):              return "At Home (Room \(room))"
        case .inShop:                         return "In Shop"
        case .traveling:                      return "Traveling"
        case .inForestRoom(let r):           return "In Forest (Room \(r))"
        case .inOakLobby:                     return "In Oak Lobby"
        case .inCaveRoom(let r):             return "In Cave (Room \(r))"
        case .atFriendHouse(_, let room):    return "Visiting Friend (Room \(room))"
        }
    }

    /// Forest-room number this resident is currently visible in (or
    /// nil if they are not in the forest). Used by
    /// `NPCResidentManager.spawnRoomNPCs` to decide which residents
    /// to render for the player.
    var visibleForestRoom: Int? {
        switch self {
        case .atHome(let room):              return room
        case .inForestRoom(let r):           return r
        case .atFriendHouse(_, let room):    return room
        case .inShop, .traveling, .inOakLobby, .inCaveRoom:
            return nil
        }
    }
}

// MARK: - NPC Resident
class NPCResident {
    let npcData: NPCData
    var status: ResidentStatus
    var shopNPC: ShopNPC?
    var forestNPC: ForestNPCEntity?
    var lastDrinkTime: TimeInterval?
    var drinkCooldown: TimeInterval = 0
    var homeHouse: Int

    /// Today's plan as set by NPCDailyScheduler at dawn rollover.
    /// Empty plan on init — the scheduler fills it in on the first
    /// dawn after the world is loaded.
    var dailyPlan: NPCDailyPlan = .empty

    // MARK: - Activity Runner Bookkeeping
    //
    // Mutated by `NPCActivityRunner`. Independent of `dailyPlan` so
    // the runner can pause/resume an activity without rewriting the
    // plan; the plan tracks WHAT to do, the runner tracks WHERE in
    // the activity we are.

    /// The activity the NPC is currently executing, or nil if idle
    /// (between activities, or done for the day).
    var currentActivity: NPCDailyActivity? = nil

    /// Sub-state of the current activity. See `NPCActivityStep` for
    /// the meaning of each case. Defaults to `.idle` when no
    /// activity is in flight.
    var currentStep: NPCActivityStep = .idle

    /// Time (CACurrentMediaTime) the current step began. Used by
    /// the runner to compute step elapsed without reaching for
    /// per-step expiry timestamps.
    var stepStartedAt: TimeInterval = 0

    /// Which leg of a multi-leg activity is in flight. Most activities
    /// have a single leg (currentLeg stays at 0). `.forageAndTrade`
    /// uses leg 0 = forage in the woods, leg 1 = trade at the broker.
    var currentLeg: Int = 0

    /// Ingredient the NPC is currently carrying back from a forage
    /// step, in flight to the broker. Cleared on trade or activity
    /// abort. Used only during `.forageAndTrade`.
    var carriedIngredient: ForageableIngredient? = nil

    /// Spawn ID the NPC is heading toward (or has picked up) during
    /// `.forageAndTrade` leg 0. Snapshotted at leg start so the NPC
    /// stays committed to a specific spawn even if other NPCs
    /// (or the player) collect nearby spawns concurrently.
    var targetForageSpawnID: String? = nil

    /// Cave room and spawn the NPC has committed to during
    /// `.gatherCaveMushrooms`. Same locking semantics as
    /// `targetForageSpawnID` but scoped to cave foraging.
    var targetCaveSpawnID: String? = nil
    var targetCaveRoom: Int? = nil

    init(npcData: NPCData) {
        self.npcData = npcData
        self.status = .atHome(room: npcData.homeRoom)
        self.homeHouse = 1
    }
    
    var isAvailableForShop: Bool {
        status == .atHome(room: npcData.homeRoom) && drinkCooldown <= 0
    }
    
    var address: String { "Room \(npcData.homeRoom), House \(homeHouse)" }
}

// MARK: - NPC Resident Manager
class NPCResidentManager {
    static let shared = NPCResidentManager()
    
    private var residents: [NPCResident] = []
    private let targetShopNPCs = 3
    private let drinkCooldownDuration: TimeInterval = 60
    
    private weak var gameScene: GameScene?
    private weak var forestScene: ForestScene?
    
    private init() {
        loadAllResidents()
    }
    
    // MARK: - Initialization
    private func loadAllResidents() {
        let allNPCs = DialogueService.shared.getAllNPCs()
        residents = allNPCs.map { NPCResident(npcData: $0) }
        assignHouseNumbers()
        restoreResidentStates()
        Log.info(.resident, "Loaded \(residents.count) residents across forest rooms")
    }

    func resetForNewGame() {
        for resident in residents {
            resident.shopNPC?.removeFromParent()
            resident.shopNPC = nil
            resident.forestNPC?.removeFromParent()
            resident.forestNPC = nil
            resident.status = .atHome(room: resident.npcData.homeRoom)
            resident.lastDrinkTime = nil
            resident.drinkCooldown = 0
            resident.dailyPlan = .empty
            resident.currentActivity = nil
            resident.currentStep = .idle
            resident.stepStartedAt = 0
            resident.currentLeg = 0
            resident.carriedIngredient = nil
            resident.targetForageSpawnID = nil
            resident.targetCaveSpawnID = nil
            resident.targetCaveRoom = nil
        }
        assignHouseNumbers()
        pendingForestTrash.removeAll()
        currentRitualNPCId = nil
        lastKnownTimePhase = .day
        Log.info(.resident, "Resident manager reset for a fresh game")
    }

    private func assignHouseNumbers() {
        var roomCounts: [Int: Int] = [:]
        for resident in residents {
            let room = resident.npcData.homeRoom
            let house = (roomCounts[room] ?? 0) + 1
            resident.homeHouse = ((house - 1) % 4) + 1
            roomCounts[room] = house
        }
    }
    
    private func restoreResidentStates() {
        guard let saved = SaveService.shared.loadResidentStates() else { return }
        for state in saved {
            guard let id = state["id"] as? String,
                  let resident = residents.first(where: { $0.npcData.id == id }) else { continue }
            if let h = state["homeHouse"] as? Int     { resident.homeHouse = h }
            if let c = state["drinkCooldown"] as? Double { resident.drinkCooldown = max(0, c) }
            if let s = state["status"] as? String {
                switch s {
                case "inShop":    resident.status = .inShop
                case "traveling": resident.status = .traveling
                default:
                    let room = state["statusRoom"] as? Int ?? resident.npcData.homeRoom
                    resident.status = .atHome(room: room)
                }
            }
        }
        Log.info(.save, "Restored resident states from save")
    }
    
    // MARK: - Scene Registration
    func registerGameScene(_ scene: GameScene)   { gameScene = scene }
    func registerForestScene(_ scene: ForestScene) { forestScene = scene }
    
    // MARK: - World Initialization
    func initializeWorld() {
        // Guest receives NPC state from host — don't spawn independently.
        guard !MultiplayerService.shared.isGuest else {
            Log.info(.resident, "Guest mode — skipping local NPC spawning, waiting for host sync")
            return
        }
        let initial = selectNPCsForShop(count: targetShopNPCs)
        for r in initial { moveResidentToShop(r) }
        spawnAllForestNPCs()
        Log.info(.resident, "World initialized: \(getShopNPCCount()) shop, \(getForestNPCCount()) forest")
    }
    
    // MARK: - Shop NPC Management
    private func selectNPCsForShop(count: Int) -> [NPCResident] {
        let available = residents.filter {
            $0.isAvailableForShop && !SaveService.shared.isNPCLiberated($0.npcData.id)
        }
        return Array(available.shuffled().prefix(count))
    }
    
    private func moveResidentToShop(_ resident: NPCResident) {
        guard let scene = gameScene else {
            Log.error(.resident, "Cannot move to shop — no game scene")
            return
        }
        resident.forestNPC?.removeFromParent()
        resident.forestNPC = nil
        
        let animal = resident.npcData.animalType ?? .fox
        let shopNPC = scene.createShopNPC(animalType: animal, resident: resident)
        resident.shopNPC = shopNPC
        resident.status = .inShop
        // Mark today's mandatory shop visit as complete in the daily plan.
        // No-op if the plan is empty (e.g. before first dawn rollover).
        NPCDailyScheduler.shared.markActivityComplete(.visitShop, npcID: resident.npcData.id)
        Log.info(.resident, "\(resident.npcData.name) moved to shop")
        // Chronicle hook
        DailyChronicleLedger.shared.recordNPCArrivedShop(
            npcID: resident.npcData.id, npcName: resident.npcData.name
        )
    }
    
    private func moveResidentToForest(_ resident: NPCResident) {
        resident.shopNPC?.removeFromParent()
        resident.shopNPC = nil
        resident.drinkCooldown = drinkCooldownDuration
        resident.lastDrinkTime = CACurrentMediaTime()
        resident.status = .atHome(room: resident.npcData.homeRoom)
        
        if let forest = forestScene, forest.currentRoom == resident.npcData.homeRoom {
            spawnForestNPC(resident, in: forest)
        }
        Log.info(.resident, "\(resident.npcData.name) returned to room \(resident.npcData.homeRoom)")
    }
    
    // MARK: - Forest NPC Management
    private func spawnAllForestNPCs() {
        guard let forest = forestScene else { return }
        let room = forest.currentRoom
        let roomResidents = residents.filter {
            $0.status.visibleForestRoom == room &&
            !SaveService.shared.isNPCLiberated($0.npcData.id)
        }
        for r in roomResidents { spawnForestNPC(r, in: forest) }
    }
    
    private func spawnForestNPC(_ resident: NPCResident, in scene: ForestScene) {
        let housePositions: [GridCoordinate] = [
            GridCoordinate(x: 8, y: 16), GridCoordinate(x: 24, y: 16),
            GridCoordinate(x: 8, y: 8),  GridCoordinate(x: 24, y: 8)
        ]
        let idx = max(0, min(3, resident.homeHouse - 1))
        let gridService = scene.gridService
        let houseWorld = gridService.gridToWorld(housePositions[idx])
        let pos = CGPoint(x: houseWorld.x + .random(in: -60...60),
                          y: houseWorld.y + .random(in: -60...60))
        
        let forestNPC = ForestNPCEntity(npcData: resident.npcData, at: pos)
        resident.forestNPC = forestNPC
        scene.addChild(forestNPC)
        Log.debug(.forest, "Spawned \(resident.npcData.name) near House \(resident.homeHouse)")
    }
    
    // MARK: - Time Phase Management
    private var lastKnownTimePhase: TimePhase = .day
    private var currentRitualNPCId: String?

    /// Current time phase as last received via `handleTimePhaseChange`.
    /// Read-only for services that gate behavior on the phase
    /// (e.g. NPCActivityRunner).
    var currentTimePhase: TimePhase { lastKnownTimePhase }
    
    func handleTimePhaseChange(_ newPhase: TimePhase) {
        guard newPhase != lastKnownTimePhase else { return }
        let old = lastKnownTimePhase
        lastKnownTimePhase = newPhase
        Log.info(.time, "Phase changed: \(old.displayName) → \(newPhase.displayName)")
        
        switch newPhase {
        case .dusk, .night, .dawn:
            // Cancel any in-flight activities so half-finished
            // walks don't leak across phases. The send-home pass
            // below will normalize statuses.
            NPCActivityRunner.shared.cancelAllActivities()
            sendAllShopNPCsHome(excludeRitualNPC: newPhase == .dawn)
            if newPhase == .dawn {
                // Roll fresh activity plans for every resident at dawn.
                // Uses GnomeManager's current day count so the log line
                // matches what the gnome simulation reports for the
                // same rollover.
                NPCDailyScheduler.shared.rollPlansForAllResidents(
                    dayCount: GnomeManager.shared.currentDayCount
                )
                // Reactive trash service — clear cooldowns and claimed
                // trash so the new day's reactions aren't gated by
                // yesterday's state.
                ForestTrashReactionService.shared.resetForDawn()
            }
        case .day:
            maintainShopPopulation()
        }
    }
    
    private func sendAllShopNPCsHome(excludeRitualNPC: Bool = false) {
        let shopResidents = residents.filter { $0.status == .inShop }
        for r in shopResidents {
            if excludeRitualNPC && r.npcData.id == currentRitualNPCId { continue }
            if let npc = r.shopNPC {
                npc.startLeaving(satisfied: true)
            } else {
                moveResidentToForest(r)
            }
        }
    }
    
    // MARK: - Update
    func update(deltaTime: TimeInterval) {
        for r in residents where r.drinkCooldown > 0 { r.drinkCooldown -= deltaTime }
        // Guest doesn't run spawn maintenance — NPCs come from host.
        if !MultiplayerService.shared.isGuest && lastKnownTimePhase == .day {
            maintainShopPopulation()
            // Drive activity-runner state machines.
            NPCActivityRunner.shared.tick(now: CACurrentMediaTime())
        }
    }
    
    private func maintainShopPopulation() {
        guard lastKnownTimePhase == .day else { return }
        let current = getShopNPCCount()
        guard current < targetShopNPCs else { return }
        
        let needed = targetShopNPCs - current
        let available = residents.filter { $0.isAvailableForShop }
        for r in available.shuffled().prefix(needed) { moveResidentToShop(r) }
    }
    
    // MARK: - NPC Lifecycle Events
    func npcLeftShop(_ npc: ShopNPC, satisfied: Bool) {
        guard let resident = residents.first(where: { $0.shopNPC === npc }) else {
            Log.error(.resident, "No resident found for departing NPC")
            return
        }
        if npc.hadDrink { scheduleForestTrash(for: resident) }
        moveResidentToForest(resident)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.maintainShopPopulation()
        }
    }
    
    // MARK: - Forest Trash
    private var pendingForestTrash: [Int: Int] = [:]
    
    private func scheduleForestTrash(for resident: NPCResident) {
        // Determine a deterministic-ish drop position. By default the
        // resident drops trash near their own home house. BUT — if
        // they hold a hostile opinion of a neighbor, there's a chance
        // they drop the trash at THAT neighbor's house instead. Petty
        // is part of the design.
        let housePositions: [GridCoordinate] = [
            GridCoordinate(x: 8, y: 16), GridCoordinate(x: 24, y: 16),
            GridCoordinate(x: 8, y: 8),  GridCoordinate(x: 24, y: 8)
        ]
        
        guard let grid: GridService = gameScene?.gridService ?? forestScene?.gridService else {
            Log.warn(.resident, "scheduleForestTrash: no grid service available — falling back to counter")
            pendingForestTrash[resident.npcData.homeRoom, default: 0] += 1
            return
        }
        
        // Decide victim. Default = self (drop at own house).
        var dropRoom = resident.npcData.homeRoom
        var dropHouseIndex = max(0, min(3, resident.homeHouse - 1))
        var victimNote = "own house \(resident.homeHouse)"
        
        // Look up hostile relationships. Use a 35% chance per leaving
        // event to actually act on hostility — keeps it occasional.
        let hostileRows = SaveService.shared.relationshipsOf(resident.npcData.id)
            .filter { $0.isHostile }
        if !hostileRows.isEmpty, CGFloat.random(in: 0...1) < 0.35 {
            // Pick the most-hated target.
            if let target = hostileRows.min(by: { $0.score < $1.score }),
               let targetResident = residents.first(where: { $0.npcData.id == target.towardNPCID }) {
                dropRoom = targetResident.npcData.homeRoom
                dropHouseIndex = max(0, min(3, targetResident.homeHouse - 1))
                victimNote = "\(targetResident.npcData.name)'s house (hostile drop)"
            }
        }
        
        let houseWorld = grid.gridToWorld(housePositions[dropHouseIndex])
        let drop = CGPoint(
            x: houseWorld.x + .random(in: -40...40),
            y: houseWorld.y + .random(in: -40...40)
        )
        
        let item = WorldItemRegistry.makeTrash(location: .forestRoom(dropRoom), at: drop)
        WorldItemRegistry.shared.add(item)
        
        Log.info(.resident, "\(resident.npcData.name) left trash near \(victimNote) in room \(dropRoom)")
        // Chronicle hook
        DailyChronicleLedger.shared.recordTrashSpawned(
            location: "forest room \(dropRoom)"
        )
    }
    
    func spawnPendingTrash(in scene: ForestScene, room: Int) {
        // Drain the legacy counter first (only non-empty on fallback paths
        // where the registry couldn't record the drop).
        if let legacy = pendingForestTrash[room], legacy > 0 {
            let w = scene.frame.width; let h = scene.frame.height; let m: CGFloat = 150
            for _ in 0..<legacy {
                let pos = CGPoint(x: .random(in: (-w/2 + m)...(w/2 - m)),
                                  y: .random(in: (-h/2 + m)...(h/2 - m)))
                let item = WorldItemRegistry.makeTrash(location: .forestRoom(room), at: pos)
                WorldItemRegistry.shared.add(item)
            }
            pendingForestTrash[room] = 0
        }
        
        // Spawn all persistent trash for this room from the registry.
        let items = WorldItemRegistry.shared.items(of: .trash, at: .forestRoom(room))
        for item in items {
            let trash = Trash(at: item.position.cgPoint, location: .forest(room: room))
            trash.userData = NSMutableDictionary()
            trash.userData?["worldItemID"] = item.id
            scene.addChild(trash)
        }
        if !items.isEmpty {
            Log.debug(.resident, "Spawned \(items.count) persisted trash in room \(room)")
        }
    }
    
    // MARK: - Forest Room Changes
    func forestRoomChanged(to newRoom: Int, scene: ForestScene) {
        clearForestNPCs(from: scene)
        self.forestScene = scene
        spawnRoomNPCs(room: newRoom, in: scene)
        spawnPendingTrash(in: scene, room: newRoom)
    }
    
    private func clearForestNPCs(from scene: ForestScene) {
        for r in residents {
            r.forestNPC?.removeFromParent()
            r.forestNPC = nil
        }
    }
    
    private func spawnRoomNPCs(room: Int, in scene: ForestScene) {
        let roomResidents = residents.filter {
            $0.status.visibleForestRoom == room &&
            !SaveService.shared.isNPCLiberated($0.npcData.id)
        }
        for r in roomResidents { spawnForestNPC(r, in: scene) }
    }

    /// Spawn a forest visual for `resident` if (a) the player is in
    /// their current visible forest room, and (b) they don't already
    /// have a visual. Called by `NPCActivityRunner` after a status
    /// transition so a freshly-arrived NPC pops into view if the
    /// player is watching that room.
    func refreshForestVisualIfPlayerInRoom(_ resident: NPCResident, room: Int) {
        guard let forest = forestScene, forest.currentRoom == room else { return }
        guard resident.forestNPC == nil else { return }
        guard !SaveService.shared.isNPCLiberated(resident.npcData.id) else { return }
        spawnForestNPC(resident, in: forest)
    }

    /// Remove the visible `ForageNode` for `spawnID` from the active
    /// forest scene (if the player is in that room). Used by
    /// `NPCActivityRunner` after an NPC collects a forageable so the
    /// emoji disappears for the host. Guest visual cleanup happens
    /// via the `.itemForaged` network message handler in
    /// `ForestScene+Multiplayer`.
    func removeForageNodeIfVisible(spawnID: String, in location: SpawnLocation) {
        guard let forest = forestScene else { return }
        guard case let .forestRoom(room) = location, room == forest.currentRoom else { return }
        let nodes = forest.children.compactMap { $0 as? ForageNode }
        guard let match = nodes.first(where: { $0.spawnID == spawnID }) else { return }
        match.pickUp { Log.debug(.forest, "NPC-collected forage node removed locally") }
    }
    
    // MARK: - Status Queries
    func getShopNPCCount() -> Int {
        residents.filter { $0.status == .inShop }.count
    }
    
    func getForestNPCCount() -> Int {
        residents.filter { $0.status.visibleForestRoom != nil }.count
    }
    
    func getResidentsInRoom(_ room: Int) -> [NPCResident] {
        residents.filter { $0.status.visibleForestRoom == room }
    }
    
    func getAllResidents() -> [NPCResident] { residents }
    
    /// Look up a resident by NPC id (e.g. "qari_deer"). Used by the dialogue
    /// system to enrich LLM prompts with home/satisfaction/etc. context.
    func findResident(byID id: String) -> NPCResident? {
        residents.first { $0.npcData.id == id }
    }
    
    // MARK: - Ritual NPC Management
    func setRitualNPC(_ npcId: String) {
        currentRitualNPCId = npcId
        Log.info(.ritual, "\(npcId) is now the ritual NPC")
    }
    
    func clearRitualNPC() {
        currentRitualNPCId = nil
    }
    
    // MARK: - Debug
    func printStatus() {
        Log.info(.resident, "=== RESIDENT STATUS ===")
        Log.info(.resident, "Phase: \(lastKnownTimePhase.displayName)")
        Log.info(.resident, "Shop: \(getShopNPCCount())/\(targetShopNPCs)")
        Log.info(.resident, "Forest: \(getForestNPCCount())")
    }
}
