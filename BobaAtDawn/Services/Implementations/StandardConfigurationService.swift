//
//  StandardConfigurationService.swift
//  BobaAtDawn
//
//  Standard implementation of ConfigurationService that wraps GameConfig
//

import SpriteKit

class StandardConfigurationService: ConfigurationService {
    
    // MARK: - World Configuration
    var worldWidth: CGFloat { GameConfig.World.width }
    var worldHeight: CGFloat { GameConfig.World.height }
    var wallThickness: CGFloat { GameConfig.World.wallThickness }
    var wallInset: CGFloat { GameConfig.World.wallInset }
    var doorPosition: GridCoordinate { GameConfig.World.doorPosition }
    var doorSize: CGFloat { GameConfig.World.doorSize }
    var doorOffsetFromWall: CGFloat { GameConfig.World.doorOffsetFromWall }
    var shopFloorSize: CGSize { GameConfig.World.shopFloorSize }
    var shopFloorOffset: CGPoint { GameConfig.World.shopFloorOffset }
    var shopFloorColor: SKColor { GameConfig.World.shopFloorColor }
    var backgroundColor: SKColor { GameConfig.World.backgroundColor }
    var floorColor: SKColor { GameConfig.World.floorColor }
    var wallColor: SKColor { GameConfig.World.wallColor }
    
    // MARK: - Grid System Configuration
    var gridCellSize: CGFloat { GameConfig.Grid.cellSize }
    var gridColumns: Int { GameConfig.Grid.columns }
    var gridRows: Int { GameConfig.Grid.rows }
    var gridShopOrigin: CGPoint { GameConfig.Grid.shopOrigin }
    var characterStartPosition: GridCoordinate { GameConfig.Grid.characterStartPosition }
    var shopBoundsMinX: Int { GameConfig.Grid.ShopBounds.minX }
    var shopBoundsMaxX: Int { GameConfig.Grid.ShopBounds.maxX }
    var shopBoundsMinY: Int { GameConfig.Grid.ShopBounds.minY }
    var shopBoundsMaxY: Int { GameConfig.Grid.ShopBounds.maxY }
    
    // MARK: - Character Configuration
    var characterSize: CGSize { GameConfig.Character.size }
    var characterColor: SKColor { GameConfig.Character.color }
    var characterCarryOffset: CGFloat { GameConfig.Character.carryOffset }
    var characterZPosition: CGFloat { GameConfig.Character.zPosition }
    var characterBaseMovementSpeed: CGFloat { GameConfig.Character.baseMovementSpeed }
    var characterMinMovementDuration: TimeInterval { GameConfig.Character.minMovementDuration }
    var characterMaxMovementDuration: TimeInterval { GameConfig.Character.maxMovementDuration }
    var characterFloatDistance: CGFloat { GameConfig.Character.floatDistance }
    var characterFloatDuration: TimeInterval { GameConfig.Character.floatDuration }
    
    // MARK: - Camera Configuration
    var cameraLerpSpeed: CGFloat { GameConfig.Camera.lerpSpeed }
    var cameraDefaultScale: CGFloat { GameConfig.Camera.defaultScale }
    var cameraMinZoom: CGFloat { GameConfig.Camera.minZoom }
    var cameraMaxZoom: CGFloat { GameConfig.Camera.maxZoom }
    var cameraEdgeInset: CGFloat { GameConfig.Camera.edgeInset }
    var cameraZoomResetDuration: TimeInterval { GameConfig.Camera.zoomResetDuration }
    
    // MARK: - Ingredient Stations Configuration
    var stationSize: CGSize { GameConfig.IngredientStations.size }
    var stationSpacing: CGFloat { GameConfig.IngredientStations.spacing }
    var stationBaseRow: Int { GameConfig.IngredientStations.baseRow }
    var stationIceColumn: Int { GameConfig.IngredientStations.iceColumn }
    var stationBobaColumn: Int { GameConfig.IngredientStations.bobaColumn }
    var stationFoamColumn: Int { GameConfig.IngredientStations.foamColumn }
    var stationTeaColumn: Int { GameConfig.IngredientStations.teaColumn }
    var stationLidColumn: Int { GameConfig.IngredientStations.lidColumn }
    var drinkCreatorPosition: GridCoordinate { GameConfig.IngredientStations.drinkCreatorPosition }
    var stationIceColor: SKColor { GameConfig.IngredientStations.iceColor }
    var stationBobaColor: SKColor { GameConfig.IngredientStations.bobaColor }
    var stationFoamColor: SKColor { GameConfig.IngredientStations.foamColor }
    var stationTeaColor: SKColor { GameConfig.IngredientStations.teaColor }
    var stationLidColor: SKColor { GameConfig.IngredientStations.lidColor }
    var stationInteractionScaleAmount: CGFloat { GameConfig.IngredientStations.interactionScaleAmount }
    var stationInteractionDuration: TimeInterval { GameConfig.IngredientStations.interactionDuration }
    
    // MARK: - NPC Configuration
    var npcFontSize: CGFloat { GameConfig.NPC.fontSize }
    var npcFontName: String { GameConfig.NPC.fontName }
    var npcZPosition: CGFloat { GameConfig.NPC.zPosition }
    var npcMaxCount: Int { GameConfig.NPC.maxNPCs }
    var npcMoveSpeed: TimeInterval { GameConfig.NPC.moveSpeed }
    var npcWanderRadius: Int { GameConfig.NPC.wanderRadius }
    var npcExitThreshold: Int { GameConfig.NPC.exitThreshold }
    var npcExitYTolerance: Int { GameConfig.NPC.exitYTolerance }
    var npcEnteringDurationMin: TimeInterval { GameConfig.NPC.enteringDuration.min }
    var npcEnteringDurationMax: TimeInterval { GameConfig.NPC.enteringDuration.max }
    var npcWanderingDurationMin: TimeInterval { GameConfig.NPC.wanderingDuration.min }
    var npcWanderingDurationMax: TimeInterval { GameConfig.NPC.wanderingDuration.max }
    var npcSittingTimeoutMin: TimeInterval { GameConfig.NPC.sittingTimeout.min }
    var npcSittingTimeoutMax: TimeInterval { GameConfig.NPC.sittingTimeout.max }
    var npcDrinkEnjoymentTimeMin: TimeInterval { GameConfig.NPC.drinkEnjoymentTime.min }
    var npcDrinkEnjoymentTimeMax: TimeInterval { GameConfig.NPC.drinkEnjoymentTime.max }
    var npcMaxLifetime: TimeInterval { GameConfig.NPC.maxLifetime }
    var npcDaySpawnInterval: TimeInterval { GameConfig.NPC.daySpawnInterval }
    var npcDuskSpawnInterval: TimeInterval { GameConfig.NPC.duskSpawnInterval }
    var npcNightSpawnInterval: TimeInterval { GameConfig.NPC.nightSpawnInterval }
    var npcDawnSpawnInterval: TimeInterval { GameConfig.NPC.dawnSpawnInterval }
    var npcOccupancyMultiplierMax: Double { GameConfig.NPC.occupancyMultiplierMax }
    var npcDrinkBonusMultiplier: Double { GameConfig.NPC.drinkBonusMultiplier }
    var npcNightVisitorChance: Int { GameConfig.NPC.nightVisitorChance }
    
    // MARK: - Touch & Interaction Configuration
    var touchLongPressDuration: TimeInterval { GameConfig.Touch.longPressDuration }
    var touchInteractionSearchDepth: Int { GameConfig.Touch.interactionSearchDepth }
    var touchOccupiedCellFeedbackRadius: CGFloat { GameConfig.Touch.occupiedCellFeedbackRadius }
    var touchFeedbackColor: SKColor { GameConfig.Touch.feedbackColor }
    var touchFeedbackLineWidth: CGFloat { GameConfig.Touch.feedbackLineWidth }
    var touchFeedbackZPosition: CGFloat { GameConfig.Touch.feedbackZPosition }
    var touchFeedbackScaleAmount: CGFloat { GameConfig.Touch.feedbackScaleAmount }
    var touchFeedbackScaleDuration: TimeInterval { GameConfig.Touch.feedbackScaleDuration }
    var touchFeedbackWaitDuration: TimeInterval { GameConfig.Touch.feedbackWaitDuration }
    var touchFeedbackFadeDuration: TimeInterval { GameConfig.Touch.feedbackFadeDuration }
    
    // MARK: - Time System Configuration
    var timeDawnDuration: TimeInterval { GameConfig.Time.dawnDuration }
    var timeDayDuration: TimeInterval { GameConfig.Time.dayDuration }
    var timeDuskDuration: TimeInterval { GameConfig.Time.duskDuration }
    var timeNightDuration: TimeInterval { GameConfig.Time.nightDuration }
    var timeLabelFontSize: CGFloat { GameConfig.Time.labelFontSize }
    var timeLabelFontName: String { GameConfig.Time.labelFontName }
    var timeLabelZPosition: CGFloat { GameConfig.Time.labelZPosition }
    var timeDawnColor: SKColor { GameConfig.Time.dawnColor }
    var timeDayColor: SKColor { GameConfig.Time.dayColor }
    var timeDuskColor: SKColor { GameConfig.Time.duskColor }
    var timeNightColor: SKColor { GameConfig.Time.nightColor }
    var timeBreakerPosition: CGPoint { GameConfig.Time.breakerPosition }
    var timeWindowPosition: CGPoint { GameConfig.Time.windowPosition }
    var timeLabelPosition: CGPoint { GameConfig.Time.labelPosition }
    
    // MARK: - Forest Transition Configuration
    var forestTransitionFadeOutDuration: TimeInterval { GameConfig.ForestTransition.fadeOutDuration }
    var forestTransitionFadeInDuration: TimeInterval { GameConfig.ForestTransition.fadeInDuration }
    var forestTransitionSceneDuration: TimeInterval { GameConfig.ForestTransition.sceneTransitionDuration }
    
    // MARK: - Objects Configuration
    var objectDefaultSize: CGSize { GameConfig.Objects.defaultSize }
    var objectDefaultZPosition: CGFloat { GameConfig.Objects.defaultZPosition }
    var objectCarryZPosition: CGFloat { GameConfig.Objects.carryZPosition }
    var objectRotationDuration: TimeInterval { GameConfig.Objects.rotationDuration }
    var objectRotationFeedbackScale: CGFloat { GameConfig.Objects.rotationFeedbackScale }
    var objectRotationFeedbackDuration: TimeInterval { GameConfig.Objects.rotationFeedbackDuration }
    var objectIndicatorAlpha: CGFloat { GameConfig.Objects.indicatorAlpha }
    var objectCornerIndicatorAlpha: CGFloat { GameConfig.Objects.cornerIndicatorAlpha }
    var objectStationIndicatorAlpha: CGFloat { GameConfig.Objects.stationIndicatorAlpha }
    var objectTableColor: SKColor { GameConfig.Objects.tableColor }
    var objectTableCenterDotSize: CGSize { GameConfig.Objects.tableCenterDotSize }
    var objectTableCornerDotSize: CGSize { GameConfig.Objects.tableCornerDotSize }
    var objectTableIndicatorOffset: CGFloat { GameConfig.Objects.tableIndicatorOffset }
    
    // MARK: - Table Service Configuration
    var tableDrinkOnTableOffset: CGPoint { GameConfig.TableService.drinkOnTableOffset }
    var tableDrinkOnTableZPosition: CGFloat { GameConfig.TableService.drinkOnTableZPosition }
    var tableDrinkOnTableSize: CGSize { GameConfig.TableService.drinkOnTableSize }
    var tableLidSize: CGSize { GameConfig.TableService.tableLidSize }
    var tableLidOffset: CGPoint { GameConfig.TableService.tableLidOffset }
    var tableStrawSize: CGSize { GameConfig.TableService.tableStrawSize }
    var tableStrawOffset: CGPoint { GameConfig.TableService.tableStrawOffset }
    var tableLidColor: SKColor { GameConfig.TableService.tableLidColor }
    var tableStrawColor: SKColor { GameConfig.TableService.tableStrawColor }
    
    // MARK: - Debug Configuration
    var debugShowGridOverlay: Bool { GameConfig.Debug.showGridOverlay }
    var debugGridOverlayAlpha: CGFloat { GameConfig.Debug.gridOverlayAlpha }
    var debugGridOverlayZPosition: CGFloat { GameConfig.Debug.gridOverlayZPosition }
    var debugLogNPCStatusInterval: TimeInterval { GameConfig.Debug.logNPCStatusInterval }
    
    // MARK: - Convenience Methods
    func stationPosition(for type: IngredientStation.StationType) -> GridCoordinate {
        return GameConfig.stationPosition(for: type)
    }
    
    func stationColor(for type: IngredientStation.StationType) -> SKColor {
        return GameConfig.stationColor(for: type)
    }
    
    func spawnInterval(for phase: TimePhase) -> TimeInterval {
        return GameConfig.spawnInterval(for: phase)
    }
    
    func timePhaseColor(for phase: TimePhase) -> SKColor {
        return GameConfig.timePhaseColor(for: phase)
    }
}
