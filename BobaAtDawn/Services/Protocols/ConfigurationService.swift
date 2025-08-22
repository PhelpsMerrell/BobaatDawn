//
//  ConfigurationService.swift
//  BobaAtDawn
//
//  Dependency injection protocol for game configuration access
//

import SpriteKit

// MARK: - Configuration Service Protocol
protocol ConfigurationService {
    
    // MARK: - World Configuration
    var worldWidth: CGFloat { get }
    var worldHeight: CGFloat { get }
    var wallThickness: CGFloat { get }
    var wallInset: CGFloat { get }
    var doorGridPosition: GridCoordinate { get }  // FIXED
    var doorSize: CGFloat { get }
    var shopFloorColor: SKColor { get }
    var backgroundColor: SKColor { get }
    var floorColor: SKColor { get }
    var wallColor: SKColor { get }
    
    // MARK: - Grid System Configuration
    var gridCellSize: CGFloat { get }
    var gridColumns: Int { get }
    var gridRows: Int { get }
    var gridShopOrigin: CGPoint { get }
    var characterStartPosition: GridCoordinate { get }
    var shopBoundsMinX: Int { get }
    var shopBoundsMaxX: Int { get }
    var shopBoundsMinY: Int { get }
    var shopBoundsMaxY: Int { get }
    
    // MARK: - Character Configuration
    var characterSize: CGSize { get }
    var characterColor: SKColor { get }
    var characterCarryOffset: CGFloat { get }
    var characterZPosition: CGFloat { get }
    var characterBaseMovementSpeed: CGFloat { get }
    var characterMinMovementDuration: TimeInterval { get }
    var characterMaxMovementDuration: TimeInterval { get }
    var characterFloatDistance: CGFloat { get }
    var characterFloatDuration: TimeInterval { get }
    
    // MARK: - Camera Configuration
    var cameraLerpSpeed: CGFloat { get }
    var cameraDefaultScale: CGFloat { get }
    var cameraMinZoom: CGFloat { get }
    var cameraMaxZoom: CGFloat { get }
    var cameraEdgeInset: CGFloat { get }
    var cameraZoomResetDuration: TimeInterval { get }
    
    // MARK: - Ingredient Stations Configuration
    var stationSize: CGSize { get }
    var stationSpacing: CGFloat { get }
    var stationBaseRow: Int { get }
    var stationIceColumn: Int { get }
    var stationBobaColumn: Int { get }
    var stationFoamColumn: Int { get }
    var stationTeaColumn: Int { get }
    var stationLidColumn: Int { get }
    var drinkCreatorPosition: GridCoordinate { get }
    var stationIceColor: SKColor { get }
    var stationBobaColor: SKColor { get }
    var stationFoamColor: SKColor { get }
    var stationTeaColor: SKColor { get }
    var stationLidColor: SKColor { get }
    var stationInteractionScaleAmount: CGFloat { get }
    var stationInteractionDuration: TimeInterval { get }
    
    // MARK: - NPC Configuration
    var npcFontSize: CGFloat { get }
    var npcFontName: String { get }
    var npcZPosition: CGFloat { get }
    var npcMaxCount: Int { get }
    var npcMoveSpeed: TimeInterval { get }
    var npcWanderRadius: Int { get }
    var npcExitThreshold: Int { get }
    var npcExitYTolerance: Int { get }
    var npcEnteringDurationMin: TimeInterval { get }
    var npcEnteringDurationMax: TimeInterval { get }
    var npcWanderingDurationMin: TimeInterval { get }
    var npcWanderingDurationMax: TimeInterval { get }
    var npcSittingTimeoutMin: TimeInterval { get }
    var npcSittingTimeoutMax: TimeInterval { get }
    var npcDrinkEnjoymentTimeMin: TimeInterval { get }
    var npcDrinkEnjoymentTimeMax: TimeInterval { get }
    var npcMaxLifetime: TimeInterval { get }
    var npcDaySpawnInterval: TimeInterval { get }
    var npcDuskSpawnInterval: TimeInterval { get }
    var npcNightSpawnInterval: TimeInterval { get }
    var npcDawnSpawnInterval: TimeInterval { get }
    var npcOccupancyMultiplierMax: Double { get }
    var npcDrinkBonusMultiplier: Double { get }
    var npcNightVisitorChance: Int { get }
    
    // MARK: - Touch & Interaction Configuration
    var touchLongPressDuration: TimeInterval { get }
    var touchInteractionSearchDepth: Int { get }
    var touchOccupiedCellFeedbackRadius: CGFloat { get }
    var touchFeedbackColor: SKColor { get }
    var touchFeedbackLineWidth: CGFloat { get }
    var touchFeedbackZPosition: CGFloat { get }
    var touchFeedbackScaleAmount: CGFloat { get }
    var touchFeedbackScaleDuration: TimeInterval { get }
    var touchFeedbackWaitDuration: TimeInterval { get }
    var touchFeedbackFadeDuration: TimeInterval { get }
    
    // MARK: - Time System Configuration
    var timeDawnDuration: TimeInterval { get }
    var timeDayDuration: TimeInterval { get }
    var timeDuskDuration: TimeInterval { get }
    var timeNightDuration: TimeInterval { get }
    var timeLabelFontSize: CGFloat { get }
    var timeLabelFontName: String { get }
    var timeLabelZPosition: CGFloat { get }
    var timeDawnColor: SKColor { get }
    var timeDayColor: SKColor { get }
    var timeDuskColor: SKColor { get }
    var timeNightColor: SKColor { get }
    // FIXED: Time system uses grid positioning now
    var timeBreakerGridPosition: GridCoordinate { get }
    var timeWindowGridPosition: GridCoordinate { get }
    var timeLabelGridPosition: GridCoordinate { get }
    
    // MARK: - Forest Transition Configuration
    var forestTransitionFadeOutDuration: TimeInterval { get }
    var forestTransitionFadeInDuration: TimeInterval { get }
    var forestTransitionSceneDuration: TimeInterval { get }
    
    // MARK: - Objects Configuration
    var objectDefaultSize: CGSize { get }
    var objectDefaultZPosition: CGFloat { get }
    var objectCarryZPosition: CGFloat { get }
    var objectRotationDuration: TimeInterval { get }
    var objectRotationFeedbackScale: CGFloat { get }
    var objectRotationFeedbackDuration: TimeInterval { get }
    var objectIndicatorAlpha: CGFloat { get }
    var objectCornerIndicatorAlpha: CGFloat { get }
    var objectStationIndicatorAlpha: CGFloat { get }
    var objectTableColor: SKColor { get }
    var objectTableCenterDotSize: CGSize { get }
    var objectTableCornerDotSize: CGSize { get }
    var objectTableIndicatorOffset: CGFloat { get }
    
    // MARK: - Table Service Configuration
    var tableDrinkOnTableOffset: CGPoint { get }
    var tableDrinkOnTableZPosition: CGFloat { get }
    var tableDrinkOnTableSize: CGSize { get }
    var tableLidSize: CGSize { get }
    var tableLidOffset: CGPoint { get }
    var tableStrawSize: CGSize { get }
    var tableStrawOffset: CGPoint { get }
    var tableLidColor: SKColor { get }
    var tableStrawColor: SKColor { get }
    
    // MARK: - Debug Configuration
    var debugShowGridOverlay: Bool { get }
    var debugGridOverlayAlpha: CGFloat { get }
    var debugGridOverlayZPosition: CGFloat { get }
    var debugLogNPCStatusInterval: TimeInterval { get }
    
    // MARK: - Convenience Methods
    func stationPosition(for type: IngredientStation.StationType) -> GridCoordinate
    func stationColor(for type: IngredientStation.StationType) -> SKColor
    func spawnInterval(for phase: TimePhase) -> TimeInterval
    func timePhaseColor(for phase: TimePhase) -> SKColor
}
