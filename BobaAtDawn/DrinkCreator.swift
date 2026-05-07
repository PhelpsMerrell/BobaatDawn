//
//  DrinkCreator.swift
//  BobaAtDawn
//
//  The empty-cup dispenser on the counter. Post-refactor it has ONE job:
//  visually represent "a stack of cups." Tapping it hands the player an
//  empty cup RotatableObject, which they then carry to the ingredient
//  stations and add layers to.
//
//  Ingredient application no longer lives here as "read the station state
//  and rebuild the display." Instead:
//    - `spawnEmptyCup()` returns a fresh, empty, carriable cup.
//    - `applyIngredient(to:type:)` additively stamps one ingredient layer
//       onto a drink-in-hand.
//    - `hasIngredient(_:in:)` / `isComplete(drink:)` are helpers for the
//       interact flow (to detect already-applied ingredients and lidded-
//       complete drinks).
//

import SpriteKit

@objc(DrinkCreator)
class DrinkCreator: SKNode {
    
    private var drinkDisplay: RotatableObject!
    
    // MARK: - Layer name constants (match atlas texture names)
    
    private static let cupLayer  = "cup_empty"
    private static let teaLayer  = "tea_black"
    private static let iceLayer  = "ice_cubes"
    private static let bobaLayer = "topping_tapioca"
    private static let foamLayer = "foam_cheese"
    private static let lidLayer  = "lid_straw"
    
    // MARK: - Init
    
    override init() {
        super.init()
        setupDrinkDisplay()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        drinkDisplay = childNode(withName: "drink_display") as? RotatableObject
        if drinkDisplay == nil {
            setupDrinkDisplay()
        }
        // Regardless of how we got here, the display is always a static
        // empty cup now — no recipe state carried over from old saves.
        rebuildDisplayAsEmptyCup()
    }
    
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
    }
    
    private func setupDrinkDisplay() {
        drinkDisplay = RotatableObject(type: .completedDrink, color: .clear, shape: "drink")
        drinkDisplay.size = CGSize(width: 40, height: 60)
        drinkDisplay.name = "drink_display"
        addChild(drinkDisplay)
        rebuildDisplayAsEmptyCup()
    }
    
    // MARK: - Counter Display (always a plain empty cup)
    
    /// Repaint the counter display as a plain empty cup. No recipe data,
    /// no shaking, no "completed_drink_pickup" name. Called on init, after
    /// the player picks up a cup, and during any external reset.
    func rebuildDisplayAsEmptyCup() {
        drinkDisplay.removeAllActions()
        drinkDisplay.removeAllChildren()
        drinkDisplay.name = "drink_display"
        
        let atlas = SKTextureAtlas(named: "Boba")
        guard atlas.textureNames.contains(Self.cupLayer) else {
            Log.warn(.drink, "DrinkCreator: Boba atlas missing \(Self.cupLayer) texture")
            return
        }
        let cupTex = atlas.textureNamed(Self.cupLayer)
        cupTex.filteringMode = .nearest
        let scale = 35.0 / cupTex.size().width
        
        let cup = SKSpriteNode(texture: cupTex)
        cup.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        cup.position = .zero
        cup.setScale(scale)
        cup.zPosition = 0
        cup.blendMode = .alpha
        cup.name = Self.cupLayer
        drinkDisplay.addChild(cup)
    }
    
    /// Legacy alias kept for external callers that still want to "reset
    /// the display." Everything routes through `rebuildDisplayAsEmptyCup`
    /// now, which is all any caller ever actually needed.
    func resetDisplayToEmptyCup() {
        rebuildDisplayAsEmptyCup()
    }
    
    // MARK: - Empty Cup Spawning (pickup from counter)
    
    /// Build a fresh, empty, carriable cup. Handed to the player when they
    /// long-press the drink display.
    func spawnEmptyCup() -> RotatableObject {
        let drink = RotatableObject(type: .drink, color: .clear, shape: "drink")
        drink.size = CGSize(width: 30, height: 45)
        drink.name = "picked_up_drink"
        
        addCupLayerToDrink(drink)
        return drink
    }
    
    // MARK: - Ingredient Application (the whole refactor point)
    
    /// Additively apply an ingredient to a drink-in-hand. Returns true if
    /// the ingredient was applied, false if it was a no-op (already on the
    /// drink, or drink is lidded-complete, or station is .trash).
    ///
    /// `.trash` is NOT handled here — the caller should route trash taps
    /// through `discardCarriedDrink`.
    @discardableResult
    func applyIngredient(to drink: RotatableObject, type: IngredientStation.StationType) -> Bool {
        // Trash isn't an ingredient — caller's bug if we see it here.
        guard type != .trash else {
            Log.warn(.drink, "applyIngredient called with .trash — caller should use discardCarriedDrink")
            return false
        }
        
        // If the drink is already lidded, it's sealed — further ingredients
        // are locked out. Includes lid-on-lid.
        if isComplete(drink: drink) {
            Log.debug(.drink, "applyIngredient: drink is lidded/complete, no-op")
            return false
        }
        
        guard let layerName = layerName(for: type) else {
            // .trash already filtered; shouldn't reach here.
            return false
        }
        
        // Already applied → no-op (additive-only, no doubling).
        if hasIngredient(named: layerName, in: drink) {
            Log.debug(.drink, "applyIngredient: \(layerName) already present, no-op")
            return false
        }
        
        addIngredientLayer(layerName, to: drink)
        
        // Renaming after lid-apply so pickup/NPC logic can identify
        // completed drinks by name (consistent with pre-refactor behavior).
        if type == .lid {
            drink.name = "completed_drink"
        } else if drink.name != "completed_drink" {
            drink.name = "picked_up_drink"
        }
        
        Log.debug(.drink, "applyIngredient: added \(layerName) to drink in hand")
        return true
    }
    
    /// Discard a carried drink — "throw it in the trash." Strips all
    /// children (including the cup) so the node can be removed from the
    /// player's hand cleanly. Caller is responsible for dropItemSilently()
    /// and any haptic feedback.
    func discardCarriedDrink(_ drink: RotatableObject) {
        drink.removeAllActions()
        drink.removeAllChildren()
        Log.info(.drink, "discardCarriedDrink: drink emptied")
    }
    
    // MARK: - Query Helpers
    
    /// True if the drink has a lid applied (it's ready to serve).
    func isComplete(drink: RotatableObject) -> Bool {
        hasIngredient(named: Self.lidLayer, in: drink)
    }
    
    /// True if the given named ingredient layer is already on the drink.
    func hasIngredient(named layerName: String, in drink: RotatableObject) -> Bool {
        drink.children.contains { $0.name == layerName }
    }
    
    /// Read which ingredient layers are currently on a drink. Used by the
    /// table-placement path, the registry, and the network broadcast.
    func ingredientFlags(for drink: RotatableObject) -> (hasTea: Bool, hasIce: Bool, hasBoba: Bool, hasFoam: Bool, hasLid: Bool) {
        (
            hasTea:  hasIngredient(named: Self.teaLayer,  in: drink),
            hasIce:  hasIngredient(named: Self.iceLayer,  in: drink),
            hasBoba: hasIngredient(named: Self.bobaLayer, in: drink),
            hasFoam: hasIngredient(named: Self.foamLayer, in: drink),
            hasLid:  hasIngredient(named: Self.lidLayer,  in: drink)
        )
    }
    
    // MARK: - Layer Construction
    
    private func layerName(for type: IngredientStation.StationType) -> String? {
        switch type {
        case .tea:   return Self.teaLayer
        case .ice:   return Self.iceLayer
        case .boba:  return Self.bobaLayer
        case .foam:  return Self.foamLayer
        case .lid:   return Self.lidLayer
        case .trash: return nil
        }
    }
    
    /// Z-order for each ingredient layer (must match original stacking).
    private func zOrder(for layerName: String) -> CGFloat {
        switch layerName {
        case Self.cupLayer:  return 0
        case Self.teaLayer:  return 1
        case Self.iceLayer:  return 2
        case Self.bobaLayer: return 3
        case Self.foamLayer: return 4
        case Self.lidLayer:  return 5
        default:             return 0
        }
    }
    
    private func addCupLayerToDrink(_ drink: RotatableObject) {
        addLayer(named: Self.cupLayer, to: drink)
    }
    
    /// Add a single ingredient sprite to a drink, using the same atlas
    /// and 25pt cup scale as the pre-refactor `buildPortableDrink`.
    private func addIngredientLayer(_ layerName: String, to drink: RotatableObject) {
        addLayer(named: layerName, to: drink)
    }
    
    private func addLayer(named layerName: String, to drink: RotatableObject) {
        let atlas = SKTextureAtlas(named: "Boba")
        guard atlas.textureNames.contains(layerName) else {
            Log.warn(.drink, "DrinkCreator: Boba atlas missing \(layerName) texture")
            return
        }
        let tex = atlas.textureNamed(layerName)
        tex.filteringMode = .nearest
        
        // Scale derived from cup_empty so all layers share one ratio.
        let cupTex = atlas.textureNamed(Self.cupLayer)
        let scale = 25.0 / cupTex.size().width
        
        let node = SKSpriteNode(texture: tex)
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.position = .zero
        node.setScale(scale)
        node.zPosition = zOrder(for: layerName)
        node.blendMode = .alpha
        node.name = layerName
        drink.addChild(node)
    }
}
