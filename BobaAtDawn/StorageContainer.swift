//
//  StorageContainer.swift
//  BobaAtDawn
//
//  Moveable furniture that holds gathered ingredients (pantry + fridge).
//
//  EDITOR SETUP:
//  1. In GameScene.sks, add a Color Sprite node
//  2. Set Custom Class to "StorageContainer"
//  3. Set the node name to "pantry" or "fridge"
//  4. Add a child SKLabelNode with the text "PANTRY" or "FRIDGE"
//     (or leave it — the code adds a label if none exists)
//  5. Position and size it in the editor however you like
//
//  INVENTORY MODEL (post-refactor):
//    - Contents live in StorageRegistry.shared, keyed by container name.
//    - 5 UNIQUE ingredient slots per container; each slot stacks unlimited.
//    - This class renders slot sprites around the container when opened
//      and routes interactions. It does NOT own the data.
//
//  INTERACTION:
//    - Long-press container (empty-handed) → toggles open/closed.
//    - Long-press container (carrying a depositable item) → deposits it.
//    - Long-press a slot sprite → retrieves one unit of that ingredient.
//    - Closes automatically if the player walks more than `autoCloseDistance`
//      points away, polled from GameScene's update loop.
//

import SpriteKit

// MARK: - Storage Type

enum StorageType: String {
    case pantry = "pantry"
    case fridge = "fridge"

    var displayName: String {
        switch self {
        case .pantry: return "PANTRY"
        case .fridge: return "FRIDGE"
        }
    }

    var defaultColor: SKColor {
        switch self {
        case .pantry: return SKColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0)
        case .fridge: return SKColor(red: 0.75, green: 0.85, blue: 0.90, alpha: 1.0)
        }
    }
}

// MARK: - Storage Container

@objc(StorageContainer)
class StorageContainer: RotatableObject {

    private enum CodingKeys {
        static let storageType = "editorStorageType"
    }
    
    // MARK: - Slot Sprite Layout
    
    /// Distance from container center to each slot sprite when open.
    private static let slotRadius: CGFloat = 60
    
    /// Size of each slot sprite (the circular icon + count).
    private static let slotSize: CGFloat = 36
    
    /// Walk-away distance that auto-closes the container.
    static let autoCloseDistance: CGFloat = 180

    // MARK: - Properties

    /// What kind of storage this is (pantry vs fridge).
    private(set) var storageType: StorageType

    /// True while the player has opened this container. Controls whether
    /// slot sprites are visible and interactive.
    private(set) var isOpen: Bool = false

    /// The label child node showing the container's name + count.
    private var nameLabel: SKLabelNode?
    
    /// Container parent node for the currently-rendered slot sprites.
    /// Recreated from scratch every time the inventory changes while open,
    /// rather than trying to diff.
    private var slotsContainer: SKNode?

    // MARK: - Init (code-created, for testing)

    init(storageType: StorageType) {
        self.storageType = storageType
        super.init(type: .furniture, color: storageType.defaultColor, shape: "rectangle")
        self.name = storageType.rawValue
        self.size = CGSize(width: 80, height: 80)
        setupLabel()
    }

    // MARK: - Init (editor-loaded via .sks)

    required init?(coder aDecoder: NSCoder) {
        let typeString = aDecoder.decodeObject(forKey: CodingKeys.storageType) as? String
        self.storageType = StorageType(rawValue: typeString ?? "") ?? .pantry
        super.init(coder: aDecoder)

        // When first placed in the editor the explicit key won't exist.
        // Derive storage type from the node name the user set ("pantry"
        // or "fridge"). Lowercased so either "Pantry" or "pantry" work.
        if typeString == nil, let nodeName = self.name,
           let derived = StorageType(rawValue: nodeName.lowercased()) {
            self.storageType = derived
        }

        // If the editor node doesn't already have a label child, add one.
        nameLabel = children.compactMap { $0 as? SKLabelNode }.first
        if nameLabel == nil {
            setupLabel()
        } else {
            // Ensure existing label shows the correct name + current stock
            updateLabel()
        }
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(storageType.rawValue, forKey: CodingKeys.storageType)
    }

    // MARK: - Label

    private func setupLabel() {
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = storageType.displayName
        label.fontSize = 11
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 2
        label.name = "storage_label"
        addChild(label)
        nameLabel = label
        updateLabel()
    }
    
    /// Refresh the label text from StorageRegistry. Called on every
    /// deposit / retrieval / sync.
    func updateLabel() {
        let contents = StorageRegistry.shared.contents(of: storageType.rawValue)
        if contents.isEmpty {
            nameLabel?.text = storageType.displayName
        } else {
            nameLabel?.text = "\(storageType.displayName) (\(contents.totalCount))"
        }
    }

    // MARK: - Open / Close
    
    /// Toggle open state. Called when the player long-presses the
    /// container body with empty hands.
    func toggleOpen() {
        if isOpen { close() } else { open() }
    }
    
    func open() {
        guard !isOpen else { return }
        isOpen = true
        rebuildSlotSprites()
        Log.info(.game, "\(storageType.displayName) opened")
    }
    
    func close() {
        guard isOpen else { return }
        isOpen = false
        removeSlotSprites()
        Log.info(.game, "\(storageType.displayName) closed")
    }
    
    /// Called by GameScene's update loop — auto-close if the player has
    /// wandered away. `playerPosition` is in scene coordinates.
    func checkAutoClose(playerPosition: CGPoint) {
        guard isOpen else { return }
        let dx = playerPosition.x - position.x
        let dy = playerPosition.y - position.y
        if hypot(dx, dy) > Self.autoCloseDistance {
            close()
        }
    }
    
    /// External signal that storage contents changed (either locally or
    /// from a network message). If the container is open, rebuild the
    /// slot sprites so the visible counts stay current.
    func onInventoryChanged() {
        updateLabel()
        if isOpen {
            rebuildSlotSprites()
        }
    }

    // MARK: - Slot Sprite Rendering
    
    private func removeSlotSprites() {
        slotsContainer?.removeFromParent()
        slotsContainer = nil
    }
    
    /// Build a slot sprite for each unique ingredient currently stored,
    /// arranged in an arc above the container. Each slot sprite has the
    /// name `storage_slot_<ingredient>` so GameScene's long-press handler
    /// can match and route the retrieval.
    ///
    /// Slot-sprite userData holds `containerName` and `ingredient` so
    /// the handler knows exactly what to pull.
    private func rebuildSlotSprites() {
        removeSlotSprites()
        
        let contents = StorageRegistry.shared.contents(of: storageType.rawValue)
        guard !contents.isEmpty else {
            // Open but empty — show no slots. The label still reads
            // "PANTRY" (without a count).
            return
        }
        
        let container = SKNode()
        container.name = "storage_slots"
        container.zPosition = 10
        addChild(container)
        slotsContainer = container
        
        let slotCount = contents.slotOrder.count
        // Arrange slots in a gentle arc above the container.
        // Span: -60° to +60° from vertical, centered on the container top.
        let spanRadians: CGFloat = .pi * 2.0 / 3.0  // 120° total
        let startAngle: CGFloat = .pi / 2 + spanRadians / 2  // 150° (left)
        let stepAngle: CGFloat = slotCount > 1 ? (spanRadians / CGFloat(slotCount - 1)) : 0
        
        for (index, ingredient) in contents.slotOrder.enumerated() {
            let angle = startAngle - stepAngle * CGFloat(index)
            let x = cos(angle) * Self.slotRadius
            let y = sin(angle) * Self.slotRadius
            
            let slot = makeSlotSprite(for: ingredient, count: contents.counts[ingredient] ?? 0)
            slot.position = CGPoint(x: x, y: y)
            container.addChild(slot)
        }
        
        // Fade/scale-in animation for the whole slots container.
        container.alpha = 0.0
        container.setScale(0.6)
        let appear = SKAction.group([
            SKAction.fadeIn(withDuration: 0.18),
            SKAction.scale(to: 1.0, duration: 0.18)
        ])
        appear.timingMode = .easeOut
        container.run(appear)
    }
    
    /// Build a single slot sprite. It's a `SKSpriteNode` so the input
    /// system's hit-test finds it as a normal interactable.
    private func makeSlotSprite(for ingredient: String, count: Int) -> SKSpriteNode {
        let bg = SKSpriteNode(
            color: SKColor(white: 0.1, alpha: 0.75),
            size: CGSize(width: Self.slotSize, height: Self.slotSize)
        )
        bg.name = "storage_slot_\(ingredient)"
        bg.userData = NSMutableDictionary()
        bg.userData?["containerName"] = storageType.rawValue
        bg.userData?["ingredient"] = ingredient
        bg.zPosition = 1
        
        // Ingredient icon (emoji label for now — extend with atlas later).
        let icon = SKLabelNode(text: ingredientEmoji(for: ingredient))
        icon.fontSize = 22
        icon.fontName = "Arial"
        icon.horizontalAlignmentMode = .center
        icon.verticalAlignmentMode = .center
        icon.position = .zero
        icon.zPosition = 2
        // Do not name — we want taps to resolve to the background sprite,
        // not the label, so hit-testing routes through `storage_slot_*`.
        bg.addChild(icon)
        
        // Count badge in the corner.
        let badge = SKLabelNode(fontNamed: "Helvetica-Bold")
        badge.text = "\(count)"
        badge.fontSize = 11
        badge.fontColor = .white
        badge.horizontalAlignmentMode = .right
        badge.verticalAlignmentMode = .bottom
        badge.position = CGPoint(x: Self.slotSize / 2 - 3, y: -Self.slotSize / 2 + 3)
        badge.zPosition = 3
        bg.addChild(badge)
        
        return bg
    }
    
    /// Map an ingredient name to a display emoji. Reads from
    /// ForageableIngredient so any new forageable is automatically
    /// visible in pantry/fridge slots with no edits here.
    private func ingredientEmoji(for ingredient: String) -> String {
        if let forageable = ForageableIngredient(rawValue: ingredient) {
            return forageable.displayEmoji
        }
        return "❓"
    }
    
    // MARK: - Override: do not allow being picked up as a RotatableObject
    
    // Storage containers should not be carriable via the default
    // RotatableObject pickup path. GameScene's long-press handler has
    // explicit branches for `as? StorageContainer` that run before the
    // carry fallback, so no `override canBeCarried` override is needed
    // (and would be a language-compatibility hazard given that
    // `RotatableObject.canBeCarried` isn't marked `open`).
}
