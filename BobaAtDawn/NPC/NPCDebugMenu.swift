//
//  NPCDebugMenu.swift
//  BobaAtDawn
//
//  Developer-only full-screen menu listing every forest NPC with their
//  satisfaction score and liberation status. Each row exposes -/+
//  buttons for live editing (with hold-to-repeat) plus a per-row
//  "Reset Liberation" action for liberated NPCs.
//
//  Tap any row to switch the menu into "opinion mode" for that NPC:
//  the row is highlighted, all other rows replace their satisfaction
//  controls with the pair of NPC ↔ NPC opinion scores
//  (this NPC -> selected, selected -> this NPC). Tapping the selected
//  row again clears the selection and returns to normal editing mode.
//
//  Trigger: long-press the 📈 npc_status_tracker debug button in the
//  shop. Replaces the older NPCStatusBubble for status reporting.
//
//  All sizes here are in SCENE UNITS, not view points. The caller is
//  expected to pass a `visibleSize` computed via
//  SKScene.convertPoint(fromView:) so the menu fills a sensible
//  fraction of whatever the camera is currently showing, regardless of
//  zoom level. No camera-scale compensation is applied to this node;
//  it sits as a plain camera child.
//
//  Mutations are persisted to SwiftData immediately on each tap, AND
//  broadcast to the multiplayer partner via NPCSatisfactionSync so
//  both devices stay in lockstep. When a remote update is received,
//  any open menu is refreshed in place.
//

import SpriteKit

// MARK: - NPC Debug Menu

class NPCDebugMenu: SKNode {

    // MARK: - Public Entry Type

    /// One row's worth of data. NPCMemory is a SwiftData @Model class,
    /// so the menu mutates it in place; the SaveService.persistNPCMemoryChanges
    /// call afterwards just commits the model context.
    struct Entry {
        let npcData: NPCData
        let memory: NPCMemory
    }

    // MARK: - Layout (all in scene units, derived from visibleSize)

    private let menuWidth: CGFloat
    private let menuHeight: CGFloat
    private let rowHeight: CGFloat
    private let rowSpacing: CGFloat
    private let menuPadding: CGFloat
    private let headerHeight: CGFloat
    private let footerHeight: CGFloat

    // Font sizes
    private let titleFontSize: CGFloat
    private let bodyFontSize: CGFloat
    private let smallFontSize: CGFloat
    private let scoreFontSize: CGFloat
    private let buttonFontSize: CGFloat
    private let bigButtonFontSize: CGFloat
    private let emojiFontSize: CGFloat
    private let levelEmojiFontSize: CGFloat
    private let opinionFontSize: CGFloat

    // Button sizes
    private let bigButtonSide: CGFloat
    private let saveButtonSize: CGSize
    private let closeButtonSize: CGSize
    private let resetButtonSize: CGSize

    // MARK: - Hold-Repeat Tuning

    private let holdInitialDelay: TimeInterval = 0.4
    private let holdRepeatInterval: TimeInterval = 0.05

    // MARK: - State

    private let onClose: () -> Void
    private let onForceSave: () -> Void

    /// Live entry list. Re-fetched when refreshFromSavedData() runs.
    private var entries: [Entry]

    /// Currently-selected NPC for opinion-mode display, or nil for
    /// normal satisfaction-editing mode.
    private var selectedNPCID: String? = nil

    private let backdrop: SKShapeNode
    private let menuPanel: SKShapeNode
    private var titleLabel: SKLabelNode!

    // Scroll machinery
    private let scrollContainer = SKNode()
    private let contentNode = SKNode()
    private let cropNode = SKCropNode()
    private var listAreaHeight: CGFloat = 0
    private var rowAreaWidth: CGFloat = 0
    private var scrollMinY: CGFloat = 0
    private var scrollMaxY: CGFloat = 0
    private var canScroll: Bool = false

    // Touch tracking
    private var initialTouchPoint: CGPoint = .zero
    private var draggingForScroll: Bool = false
    private let dragThresholdFraction: CGFloat = 0.012
    private var pendingRowTapNPCID: String?

    // Hold-repeat state
    private var heldButtonName: String?
    private var heldButtonNode: SKNode?
    private var heldNPCID: String?
    private var heldDelta: Int = 0
    private var holdInitialTimer: Timer?
    private var holdRepeatTimer: Timer?

    // Per-row UI cache (live mutation targets)
    private var satisfactionLabels: [String: SKLabelNode] = [:]
    private var levelEmojiLabels: [String: SKLabelNode] = [:]

    // Whole-row cache for in-place rebuild
    private var rowNodesByID: [String: SKNode] = [:]
    private var rowPositionsByID: [String: CGPoint] = [:]

    // Footer feedback
    private var footerStatusLabel: SKLabelNode?
    private let defaultFooterText = "Tap row to view opinions · Hold ± to ramp"
    private let opinionFooterText = "Showing opinions · tap selected row to clear"

    // MARK: - Init

    /// - Parameters:
    ///   - entries: NPCs to display.
    ///   - visibleSize: visible camera viewport, in **scene units**.
    ///                  Caller should compute via `scene.convertPoint(fromView:)`
    ///                  so the menu sizes correctly for the current zoom.
    init(entries: [Entry],
         visibleSize: CGSize,
         onClose: @escaping () -> Void,
         onForceSave: @escaping () -> Void) {

        self.onClose = onClose
        self.onForceSave = onForceSave
        self.entries = entries

        // Menu fills ~92% × 88% of visible viewport, with an aspect cap.
        let widthBudget = visibleSize.width * 0.92
        let heightBudget = visibleSize.height * 0.88
        let cappedWidth = min(widthBudget, heightBudget * 0.8)

        self.menuWidth = max(160, cappedWidth)
        self.menuHeight = max(220, heightBudget)

        // `s` = "1 unit ≈ 1% of menuWidth". All sub-sizes derive from this.
        let s = self.menuWidth / 100.0

        self.menuPadding = s * 3.5
        self.headerHeight = s * 12
        self.footerHeight = s * 6
        self.rowHeight = s * 13
        self.rowSpacing = s * 1.4

        self.titleFontSize     = s * 4.0
        self.bodyFontSize      = s * 3.2
        self.smallFontSize     = s * 2.6
        self.scoreFontSize     = s * 4.6
        self.buttonFontSize    = s * 3.0
        self.bigButtonFontSize = s * 5.2
        self.emojiFontSize     = s * 6.2
        self.levelEmojiFontSize = s * 4.6
        self.opinionFontSize    = s * 3.0

        self.bigButtonSide   = s * 9.0
        self.saveButtonSize  = CGSize(width: s * 22, height: s * 8.0)
        self.closeButtonSize = CGSize(width: s * 9.0,  height: s * 8.0)
        self.resetButtonSize = CGSize(width: s * 22, height: s * 7.5)

        backdrop = SKShapeNode(rectOf: CGSize(width: visibleSize.width * 2,
                                              height: visibleSize.height * 2))
        backdrop.fillColor = SKColor.black.withAlphaComponent(0.62)
        backdrop.strokeColor = .clear
        backdrop.zPosition = 0
        backdrop.name = "debug_menu_backdrop"

        menuPanel = SKShapeNode(rectOf: CGSize(width: menuWidth, height: menuHeight),
                                cornerRadius: s * 3)
        menuPanel.fillColor = SKColor.white.withAlphaComponent(0.97)
        menuPanel.strokeColor = SKColor.black.withAlphaComponent(0.55)
        menuPanel.lineWidth = max(1, s * 0.2)
        menuPanel.zPosition = 1
        menuPanel.name = "debug_menu_panel"

        super.init()

        zPosition = ZLayers.debugOverlay
        isUserInteractionEnabled = true
        name = "npc_debug_menu"

        addChild(backdrop)
        addChild(menuPanel)

        buildHeader()
        buildScrollMachinery()
        rebuildAllRows()
        buildFooter()

        // Reveal animation
        alpha = 0
        setScale(0.96)
        run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.18),
            SKAction.scale(to: 1.0, duration: 0.18)
        ]))

        // Stay locked to the camera so the menu doesn't slide off as the
        // player walks. We're parented to the scene (not the camera) for
        // sizing reasons — see GameScene+SaveSystem.showNPCDebugMenu —
        // so this per-frame position sync replaces the "automatic" follow
        // we'd otherwise get from being a camera child.
        let follow = SKAction.customAction(
            withDuration: TimeInterval.greatestFiniteMagnitude
        ) { node, _ in
            guard let cam = node.scene?.camera else { return }
            node.position = cam.position
        }
        run(follow, withKey: "npc_debug_menu_follow_camera")
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancelHoldTimers()
    }

    // MARK: - Header (title + close + force-save)

    private func buildHeader() {
        let headerCenterY = menuHeight / 2 - headerHeight / 2 - menuPadding * 0.2

        let title = SKLabelNode(text: "📈 NPC DEBUG")
        title.fontName = "Arial-Bold"
        title.fontSize = titleFontSize
        title.fontColor = .black
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: -menuWidth / 2 + menuPadding, y: headerCenterY)
        title.name = "debug_menu_title"
        menuPanel.addChild(title)
        titleLabel = title

        // Save button (top-right)
        let saveBtn = makePillButton(
            label: "💾 Save",
            size: saveButtonSize,
            fontSize: buttonFontSize,
            fill: SKColor.systemGreen.withAlphaComponent(0.9),
            name: "debug_menu_save_btn"
        )
        saveBtn.position = CGPoint(
            x: menuWidth / 2 - menuPadding - saveButtonSize.width / 2,
            y: headerCenterY
        )
        menuPanel.addChild(saveBtn)

        // Close button (left of save)
        let closeBtn = makePillButton(
            label: "✕",
            size: closeButtonSize,
            fontSize: bigButtonFontSize * 0.7,
            fill: SKColor.systemGray.withAlphaComponent(0.78),
            name: "debug_menu_close_btn"
        )
        closeBtn.position = CGPoint(
            x: menuWidth / 2 - menuPadding - saveButtonSize.width - menuPadding * 0.5
                - closeButtonSize.width / 2,
            y: headerCenterY
        )
        menuPanel.addChild(closeBtn)

        // Divider
        let divider = SKShapeNode(rectOf: CGSize(width: menuWidth - menuPadding * 2,
                                                 height: max(1, menuWidth * 0.002)))
        divider.fillColor = SKColor.black.withAlphaComponent(0.18)
        divider.strokeColor = .clear
        divider.position = CGPoint(x: 0, y: menuHeight / 2 - headerHeight)
        menuPanel.addChild(divider)
    }

    private func updateTitleForSelection() {
        if let id = selectedNPCID,
           let entry = entries.first(where: { $0.npcData.id == id }) {
            titleLabel.text = "📈 \(entry.npcData.emoji) \(entry.npcData.name) — opinions"
        } else {
            titleLabel.text = "📈 NPC DEBUG"
        }
        footerStatusLabel?.text = (selectedNPCID == nil) ? defaultFooterText : opinionFooterText
        footerStatusLabel?.fontColor = SKColor.black.withAlphaComponent(0.55)
    }

    // MARK: - Footer (instruction + save feedback)

    private func buildFooter() {
        let footerCenterY = -menuHeight / 2 + footerHeight / 2 + menuPadding * 0.2

        let footer = SKLabelNode(text: defaultFooterText)
        footer.fontName = "Arial"
        footer.fontSize = smallFontSize
        footer.fontColor = SKColor.black.withAlphaComponent(0.55)
        footer.horizontalAlignmentMode = .center
        footer.verticalAlignmentMode = .center
        footer.position = CGPoint(x: 0, y: footerCenterY)
        menuPanel.addChild(footer)
        footerStatusLabel = footer
    }

    // MARK: - Scroll Container (built once, refilled on rebuild)

    private func buildScrollMachinery() {
        let listAreaTop = menuHeight / 2 - headerHeight - menuPadding * 0.4
        let listAreaBottom = -menuHeight / 2 + footerHeight + menuPadding * 0.4
        let height = listAreaTop - listAreaBottom
        let centerY = (listAreaTop + listAreaBottom) / 2

        listAreaHeight = height
        rowAreaWidth = menuWidth - menuPadding * 2

        let mask = SKSpriteNode(color: .white,
                                size: CGSize(width: rowAreaWidth + 2, height: height))
        mask.position = .zero
        cropNode.maskNode = mask
        cropNode.position = CGPoint(x: 0, y: centerY)
        cropNode.zPosition = 2
        scrollContainer.addChild(contentNode)
        cropNode.addChild(scrollContainer)
        menuPanel.addChild(cropNode)
    }

    // MARK: - Row Population (initial + rebuild after selection / refresh)

    private func sortedEntries() -> [Entry] {
        // Liberated to bottom; selected NPC pinned just below header so
        // the user can always see what they selected.
        return entries.sorted { lhs, rhs in
            // Selected first
            if let sel = selectedNPCID {
                let lSel = (lhs.npcData.id == sel)
                let rSel = (rhs.npcData.id == sel)
                if lSel != rSel { return lSel }
            }
            if lhs.memory.isLiberated != rhs.memory.isLiberated {
                return !lhs.memory.isLiberated
            }
            return lhs.npcData.name < rhs.npcData.name
        }
    }

    private func rebuildAllRows() {
        // Tear down old rows
        contentNode.removeAllChildren()
        rowNodesByID.removeAll()
        rowPositionsByID.removeAll()
        satisfactionLabels.removeAll()
        levelEmojiLabels.removeAll()

        let sorted = sortedEntries()
        let totalContentHeight = max(0, CGFloat(sorted.count) * (rowHeight + rowSpacing) - rowSpacing)

        for (index, entry) in sorted.enumerated() {
            let row = makeRow(for: entry, width: rowAreaWidth)
            let firstRowCenterY = totalContentHeight / 2 - rowHeight / 2
            let rowY = firstRowCenterY - CGFloat(index) * (rowHeight + rowSpacing)
            row.position = CGPoint(x: 0, y: rowY)
            contentNode.addChild(row)

            rowNodesByID[entry.npcData.id] = row
            rowPositionsByID[entry.npcData.id] = row.position
        }

        // Update scroll bounds
        let contentTop = totalContentHeight / 2
        let contentBottom = -totalContentHeight / 2
        let visibleTop = listAreaHeight / 2
        let visibleBottom = -listAreaHeight / 2

        if totalContentHeight > listAreaHeight {
            canScroll = true
            scrollMinY = visibleTop - contentTop
            scrollMaxY = visibleBottom - contentBottom
            // Clamp current offset into new bounds (keeps view roughly stable
            // through a refresh; resets to top on selection change).
            contentNode.position.y = max(scrollMinY,
                                         min(scrollMaxY, contentNode.position.y))
            // First open / mode change → snap to top.
            if rowNodesByID.count == sorted.count {
                contentNode.position.y = scrollMinY
            }
        } else {
            canScroll = false
            scrollMinY = 0
            scrollMaxY = 0
            contentNode.position.y = 0
        }

        updateTitleForSelection()
    }

    // MARK: - Row Construction

    private func makeRow(for entry: Entry, width: CGFloat) -> SKNode {
        let row = SKNode()
        row.name = "debug_menu_row_\(entry.npcData.id)"

        let isSelected = (selectedNPCID == entry.npcData.id)
        let inOpinionMode = (selectedNPCID != nil)

        // Background pill
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: rowHeight),
                             cornerRadius: rowHeight * 0.18)
        if isSelected {
            bg.fillColor = SKColor.systemYellow.withAlphaComponent(0.28)
            bg.strokeColor = SKColor.systemOrange
            bg.lineWidth = max(2, menuWidth * 0.004)
        } else if entry.memory.isLiberated {
            bg.fillColor = SKColor.systemYellow.withAlphaComponent(0.10)
            bg.strokeColor = SKColor.black.withAlphaComponent(0.15)
            bg.lineWidth = 1
        } else {
            bg.fillColor = SKColor.systemGray.withAlphaComponent(0.10)
            bg.strokeColor = SKColor.black.withAlphaComponent(0.15)
            bg.lineWidth = 1
        }
        row.addChild(bg)

        // Animal emoji
        let emojiX = -width / 2 + menuPadding * 1.0
        let emoji = SKLabelNode(text: entry.npcData.emoji)
        emoji.fontName = "Arial"
        emoji.fontSize = emojiFontSize
        emoji.horizontalAlignmentMode = .center
        emoji.verticalAlignmentMode = .center
        emoji.position = CGPoint(x: emojiX, y: 0)
        row.addChild(emoji)

        // Name + species
        let textX = emojiX + emojiFontSize * 0.7
        let name = SKLabelNode(text: entry.npcData.name)
        name.fontName = "Arial-Bold"
        name.fontSize = bodyFontSize
        name.fontColor = .black
        name.horizontalAlignmentMode = .left
        name.verticalAlignmentMode = .baseline
        name.position = CGPoint(x: textX, y: bodyFontSize * 0.15)
        row.addChild(name)

        let species = SKLabelNode(text: entry.npcData.animal)
        species.fontName = "Arial"
        species.fontSize = smallFontSize
        species.fontColor = SKColor.black.withAlphaComponent(0.55)
        species.horizontalAlignmentMode = .left
        species.verticalAlignmentMode = .baseline
        species.position = CGPoint(x: textX, y: -smallFontSize * 1.1)
        row.addChild(species)

        // Right-side controls vary by mode + state
        if inOpinionMode {
            if isSelected {
                buildSelectedRowBadge(in: row, width: width)
            } else {
                buildOpinionRowControls(in: row, for: entry,
                                        selectedID: selectedNPCID!,
                                        width: width)
            }
        } else {
            if entry.memory.isLiberated {
                buildLiberatedRowControls(in: row, for: entry, width: width)
            } else {
                buildLivingRowControls(in: row, for: entry, width: width)
            }
        }

        return row
    }

    // Normal mode, living NPC: [-]  73  😊  [+]
    private func buildLivingRowControls(in row: SKNode, for entry: Entry, width: CGFloat) {
        let plusX = width / 2 - menuPadding * 0.6 - bigButtonSide / 2

        let plusBtn = makePillButton(
            label: "＋",
            size: CGSize(width: bigButtonSide, height: bigButtonSide),
            fontSize: bigButtonFontSize,
            fill: SKColor.systemBlue.withAlphaComponent(0.85),
            name: "debug_menu_plus_\(entry.npcData.id)"
        )
        plusBtn.position = CGPoint(x: plusX, y: 0)
        row.addChild(plusBtn)

        let emojiSpacing = bigButtonSide / 2 + menuPadding * 0.6
        let levelEmojiX = plusX - emojiSpacing
        let levelEmoji = SKLabelNode(text: entry.memory.satisfactionLevel.emoji)
        levelEmoji.fontName = "Arial"
        levelEmoji.fontSize = levelEmojiFontSize
        levelEmoji.horizontalAlignmentMode = .center
        levelEmoji.verticalAlignmentMode = .center
        levelEmoji.position = CGPoint(x: levelEmojiX, y: 0)
        row.addChild(levelEmoji)
        levelEmojiLabels[entry.npcData.id] = levelEmoji

        let scoreSpacing = levelEmojiFontSize * 0.6 + menuPadding * 0.6
        let scoreX = levelEmojiX - scoreSpacing
        let scoreLabel = SKLabelNode(text: "\(entry.memory.satisfactionScore)")
        scoreLabel.fontName = "Arial-Bold"
        scoreLabel.fontSize = scoreFontSize
        scoreLabel.fontColor = .black
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: scoreX, y: 0)
        row.addChild(scoreLabel)
        satisfactionLabels[entry.npcData.id] = scoreLabel

        let minusSpacing = scoreFontSize * 0.9 + menuPadding * 0.6 + bigButtonSide / 2
        let minusX = scoreX - minusSpacing
        let minusBtn = makePillButton(
            label: "−",
            size: CGSize(width: bigButtonSide, height: bigButtonSide),
            fontSize: bigButtonFontSize,
            fill: SKColor.systemRed.withAlphaComponent(0.82),
            name: "debug_menu_minus_\(entry.npcData.id)"
        )
        minusBtn.position = CGPoint(x: minusX, y: 0)
        row.addChild(minusBtn)
    }

    // Normal mode, liberated NPC: [LIBERATED ✨ badge]   [↩ Reset]
    private func buildLiberatedRowControls(in row: SKNode, for entry: Entry, width: CGFloat) {
        let resetBtn = makePillButton(
            label: "↩ Reset",
            size: resetButtonSize,
            fontSize: buttonFontSize,
            fill: SKColor.systemOrange.withAlphaComponent(0.88),
            name: "debug_menu_reset_\(entry.npcData.id)"
        )
        resetBtn.position = CGPoint(
            x: width / 2 - menuPadding * 0.6 - resetButtonSize.width / 2,
            y: 0
        )
        row.addChild(resetBtn)

        let badge = SKLabelNode(text: "LIBERATED ✨")
        badge.fontName = "Arial-Bold"
        badge.fontSize = bodyFontSize
        badge.fontColor = SKColor.systemOrange
        badge.horizontalAlignmentMode = .right
        badge.verticalAlignmentMode = .center
        badge.position = CGPoint(
            x: resetBtn.position.x - resetButtonSize.width / 2 - menuPadding * 0.6,
            y: 0
        )
        row.addChild(badge)
    }

    // Opinion mode, selected: pinned row gets a "SHOWING OPINIONS" badge.
    private func buildSelectedRowBadge(in row: SKNode, width: CGFloat) {
        let badge = SKLabelNode(text: "📌 SHOWING OPINIONS — tap to clear")
        badge.fontName = "Arial-Bold"
        badge.fontSize = smallFontSize
        badge.fontColor = SKColor.systemOrange
        badge.horizontalAlignmentMode = .right
        badge.verticalAlignmentMode = .center
        badge.position = CGPoint(x: width / 2 - menuPadding * 0.6, y: 0)
        row.addChild(badge)
    }

    // Opinion mode, non-selected: show two relationship scores.
    private func buildOpinionRowControls(in row: SKNode,
                                         for entry: Entry,
                                         selectedID: String,
                                         width: CGFloat) {
        // X → selected: how this NPC feels about the selected NPC.
        let outScore = SaveService.shared.getRelationship(
            of: entry.npcData.id, toward: selectedID
        )?.score
        // selected → X: how the selected NPC feels about this one.
        let inScore = SaveService.shared.getRelationship(
            of: selectedID, toward: entry.npcData.id
        )?.score

        // Right-cluster: [→ NN]   [← NN]
        let rightEdge = width / 2 - menuPadding * 0.6
        let pairWidth = (width * 0.42)
        let leftCol = rightEdge - pairWidth + (pairWidth * 0.25)
        let rightCol = rightEdge - (pairWidth * 0.18)

        let outLabel = makeOpinionLabel(prefix: "→",
                                        score: outScore,
                                        position: CGPoint(x: leftCol, y: 0))
        let inLabel = makeOpinionLabel(prefix: "←",
                                       score: inScore,
                                       position: CGPoint(x: rightCol, y: 0))

        row.addChild(outLabel)
        row.addChild(inLabel)
    }

    private func makeOpinionLabel(prefix: String, score: Int?, position: CGPoint) -> SKLabelNode {
        let l = SKLabelNode()
        l.fontName = "Arial-Bold"
        l.fontSize = opinionFontSize
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .center
        l.position = position

        if let s = score {
            let signed = s >= 0 ? "+\(s)" : "\(s)"
            l.text = "\(prefix)  \(signed)"
            l.fontColor = colorForOpinionScore(s)
        } else {
            l.text = "\(prefix)  —"
            l.fontColor = SKColor.darkGray
        }
        return l
    }

    /// Color-code opinion scores using the same hostility thresholds the
    /// rest of the codebase uses (HostilityThreshold).
    private func colorForOpinionScore(_ s: Int) -> SKColor {
        if s <= HostilityThreshold.hostile      { return SKColor.systemRed }
        if s <= HostilityThreshold.avoidant     { return SKColor.systemOrange }
        if s >= HostilityThreshold.close        { return SKColor(red: 0.10, green: 0.55, blue: 0.20, alpha: 1.0) }
        if s >= HostilityThreshold.friendly     { return SKColor.systemGreen }
        return SKColor.darkGray
    }

    // MARK: - Pill button helper

    private func makePillButton(label: String,
                                size: CGSize,
                                fontSize: CGFloat,
                                fill: SKColor,
                                name: String) -> SKShapeNode {
        let pill = SKShapeNode(rectOf: size, cornerRadius: min(size.width, size.height) / 2)
        pill.fillColor = fill
        pill.strokeColor = .clear
        pill.name = name
        pill.zPosition = 3

        let l = SKLabelNode(text: label)
        l.fontName = "Arial-Bold"
        l.fontSize = fontSize
        l.fontColor = .white
        l.horizontalAlignmentMode = .center
        l.verticalAlignmentMode = .center
        l.position = .zero
        l.zPosition = 4
        pill.addChild(l)

        return pill
    }

    // MARK: - Touch Handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        initialTouchPoint = location
        draggingForScroll = false
        pendingRowTapNPCID = nil

        guard let action = hitAction(at: location) else {
            // Tap on backdrop (outside menu panel) → dismiss.
            if !menuPanel.contains(location) {
                triggerHaptic(.light)
                isUserInteractionEnabled = false
                onClose()
            }
            return
        }

        switch action.kind {
        case .close:
            triggerHaptic(.light)
            pulse(action.node)
            isUserInteractionEnabled = false
            onClose()

        case .save:
            triggerHaptic(.success)
            pulse(action.node)
            onForceSave()
            flashFooter("Saved ✓", color: .systemGreen)

        case .plus(let npcID):
            beginHold(buttonName: action.name, buttonNode: action.node, npcID: npcID, delta: 1)

        case .minus(let npcID):
            beginHold(buttonName: action.name, buttonNode: action.node, npcID: npcID, delta: -1)

        case .reset(let npcID):
            triggerHaptic(.success)
            pulse(action.node)
            performLiberationReset(npcID: npcID)

        case .selectRow(let npcID):
            // Defer the toggle until touchesEnded so a drag-to-scroll
            // doesn't accidentally flip the selection.
            pendingRowTapNPCID = npcID
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let prev = touch.previousLocation(in: self)
        let delta = CGPoint(x: location.x - initialTouchPoint.x,
                            y: location.y - initialTouchPoint.y)

        // If we're holding a -/+ button and the finger drifts off it,
        // cancel the hold.
        if heldButtonNode != nil {
            if let held = heldButtonNode, !held.contains(location) {
                cancelHoldTimers()
                heldButtonNode = nil
                heldButtonName = nil
                heldNPCID = nil
                heldDelta = 0
            }
            return
        }

        // Drag past threshold cancels any pending row-tap and may begin scroll.
        if hypot(delta.x, delta.y) > menuWidth * dragThresholdFraction {
            pendingRowTapNPCID = nil
            if !draggingForScroll {
                draggingForScroll = canScroll && menuPanel.contains(initialTouchPoint)
            }
        }
        guard draggingForScroll else { return }

        let newY = contentNode.position.y + (location.y - prev.y)
        contentNode.position.y = max(scrollMinY, min(scrollMaxY, newY))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelHoldTimers()

        // Fire the deferred row-tap if it survived without being dragged.
        if let id = pendingRowTapNPCID, !draggingForScroll {
            triggerHaptic(.selection)
            toggleSelection(npcID: id)
        }

        heldButtonNode = nil
        heldButtonName = nil
        heldNPCID = nil
        heldDelta = 0
        pendingRowTapNPCID = nil
        draggingForScroll = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelHoldTimers()
        heldButtonNode = nil
        heldButtonName = nil
        heldNPCID = nil
        heldDelta = 0
        pendingRowTapNPCID = nil
        draggingForScroll = false
    }

    // MARK: - Hit-testing → Action

    private enum HitAction {
        case close
        case save
        case plus(npcID: String)
        case minus(npcID: String)
        case reset(npcID: String)
        case selectRow(npcID: String)
    }

    /// Walk hit-test results and return the first recognized action.
    /// Buttons are matched before the row containing them (taps land on
    /// buttons first because they sit at higher zPosition); plain
    /// row-body taps fall through to the row name and resolve to
    /// `.selectRow`.
    private func hitAction(at point: CGPoint) -> (kind: HitAction, name: String, node: SKNode)? {
        let hits = nodes(at: point)
        for node in hits {
            var cursor: SKNode? = node
            while let c = cursor {
                if let n = c.name {
                    if n == "debug_menu_close_btn"  { return (.close, n, c) }
                    if n == "debug_menu_save_btn"   { return (.save, n, c) }
                    if let id = parseID(prefix: "debug_menu_plus_", from: n) {
                        return (.plus(npcID: id), n, c)
                    }
                    if let id = parseID(prefix: "debug_menu_minus_", from: n) {
                        return (.minus(npcID: id), n, c)
                    }
                    if let id = parseID(prefix: "debug_menu_reset_", from: n) {
                        return (.reset(npcID: id), n, c)
                    }
                    if let id = parseID(prefix: "debug_menu_row_", from: n) {
                        return (.selectRow(npcID: id), n, c)
                    }
                }
                cursor = c.parent
            }
        }
        return nil
    }

    private func parseID(prefix: String, from name: String) -> String? {
        guard name.hasPrefix(prefix) else { return nil }
        return String(name.dropFirst(prefix.count))
    }

    // MARK: - Selection

    private func toggleSelection(npcID: String) {
        if selectedNPCID == npcID {
            selectedNPCID = nil
        } else {
            selectedNPCID = npcID
        }
        rebuildAllRows()
    }

    // MARK: - Hold-to-repeat

    private func beginHold(buttonName: String, buttonNode: SKNode, npcID: String, delta: Int) {
        cancelHoldTimers()
        heldButtonName = buttonName
        heldButtonNode = buttonNode
        heldNPCID = npcID
        heldDelta = delta

        triggerHaptic(.selection)
        pulse(buttonNode)

        applyDelta(npcID: npcID, delta: delta)

        holdInitialTimer = Timer.scheduledTimer(
            withTimeInterval: holdInitialDelay,
            repeats: false
        ) { [weak self] _ in
            self?.startRepeatingHold()
        }
    }

    private func startRepeatingHold() {
        holdInitialTimer = nil
        holdRepeatTimer = Timer.scheduledTimer(
            withTimeInterval: holdRepeatInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self = self,
                  let id = self.heldNPCID else { return }
            self.applyDelta(npcID: id, delta: self.heldDelta)
        }
    }

    private func cancelHoldTimers() {
        holdInitialTimer?.invalidate()
        holdInitialTimer = nil
        holdRepeatTimer?.invalidate()
        holdRepeatTimer = nil
    }

    // MARK: - Mutations

    /// Mutate satisfaction (clamped 1...100), persist, broadcast, refresh row.
    private func applyDelta(npcID: String, delta: Int) {
        guard let memory = SaveService.shared.getNPCMemory(npcID) else {
            Log.warn(.save, "Debug menu: no NPCMemory for \(npcID)")
            return
        }
        guard !memory.isLiberated else { return }

        let newScore = max(1, min(100, memory.satisfactionScore + delta))
        guard newScore != memory.satisfactionScore else {
            triggerHaptic(.light)
            return
        }

        memory.satisfactionScore = newScore
        SaveService.shared.persistNPCMemoryChanges(memory)
        broadcastSatisfaction(memory)

        // Live-update displayed labels (only meaningful in normal mode;
        // opinion mode doesn't show -/+ controls anyway).
        satisfactionLabels[npcID]?.text = "\(newScore)"
        levelEmojiLabels[npcID]?.text = memory.satisfactionLevel.emoji
    }

    /// Clear an NPC's liberation state and rebuild its row in place.
    private func performLiberationReset(npcID: String) {
        guard let memory = SaveService.shared.getNPCMemory(npcID) else {
            Log.warn(.save, "Debug menu: no NPCMemory for \(npcID)")
            return
        }
        memory.isLiberated = false
        memory.liberationDate = nil
        SaveService.shared.persistNPCMemoryChanges(memory)
        broadcastSatisfaction(memory)
        Log.info(.save, "Debug menu: reset liberation for \(memory.name) (\(npcID))")

        // Rebuild this single row to pick up the new state.
        rebuildRow(npcID: npcID, memory: memory)
        flashFooter("Liberation reset for \(memory.name)", color: .systemOrange)
    }

    /// Send a per-NPC satisfaction sync to the partner so both clients
    /// stay aligned without waiting for a full worldSync.
    private func broadcastSatisfaction(_ memory: NPCMemory) {
        guard MultiplayerService.shared.isConnected else { return }
        let entry = NPCSatisfactionSync.Entry(
            npcID: memory.npcID,
            satisfactionScore: memory.satisfactionScore,
            totalDrinksReceived: memory.totalDrinksReceived,
            isLiberated: memory.isLiberated
        )
        MultiplayerService.shared.send(
            type: .npcSatisfactionSync,
            payload: NPCSatisfactionSync(entries: [entry])
        )
    }

    /// In-place rebuild of a single row after its state shape changed
    /// (e.g., liberated → not). Called only outside opinion mode; in
    /// opinion mode we use rebuildAllRows so the new row's layout
    /// adopts the opinion-row controls.
    private func rebuildRow(npcID: String, memory: NPCMemory) {
        guard let oldRow = rowNodesByID[npcID],
              let position = rowPositionsByID[npcID] else { return }

        guard let npcData = DialogueService.shared.getAllNPCs()
            .first(where: { $0.id == npcID }) else {
            Log.warn(.save, "Debug menu: no NPCData for \(npcID) during rebuild")
            return
        }

        // Replace the entry in our cached list so future rebuilds see it.
        if let idx = entries.firstIndex(where: { $0.npcData.id == npcID }) {
            entries[idx] = Entry(npcData: npcData, memory: memory)
        }

        satisfactionLabels.removeValue(forKey: npcID)
        levelEmojiLabels.removeValue(forKey: npcID)

        oldRow.removeFromParent()

        let entry = Entry(npcData: npcData, memory: memory)
        let newRow = makeRow(for: entry, width: rowAreaWidth)
        newRow.position = position
        contentNode.addChild(newRow)
        rowNodesByID[npcID] = newRow
    }

    // MARK: - Refresh Hooks (called by multiplayer receiver)

    /// Re-fetch every entry's memory from SwiftData and rebuild rows.
    /// Used when a remote NPCSatisfactionSync arrives and the menu is
    /// visible. Selection state is preserved.
    func refreshFromSavedData() {
        let allNPCs = DialogueService.shared.getAllNPCs()
        var fresh: [Entry] = []
        for npcData in allNPCs {
            guard let memory = SaveService.shared.getNPCMemory(npcData.id) else { continue }
            fresh.append(Entry(npcData: npcData, memory: memory))
        }
        self.entries = fresh
        rebuildAllRows()
    }

    /// Walks the camera (or scene) for a live menu instance and asks it
    /// to refresh. No-op if the menu is closed.
    static func refreshIfOpen(in scene: SKScene) {
        let candidates: [SKNode] = [scene.camera, scene].compactMap { $0 }
        for host in candidates {
            if let menu = host.childNode(withName: "npc_debug_menu") as? NPCDebugMenu {
                menu.refreshFromSavedData()
                return
            }
        }
    }

    // MARK: - Visual / Haptic helpers

    private func pulse(_ node: SKNode) {
        let action = SKAction.sequence([
            SKAction.scale(to: 0.92, duration: 0.06),
            SKAction.scale(to: 1.0, duration: 0.08)
        ])
        node.run(action)
    }

    private func flashFooter(_ message: String, color: SKColor) {
        guard let footer = footerStatusLabel else { return }
        let restoreText = (selectedNPCID == nil) ? defaultFooterText : opinionFooterText
        let originalColor = SKColor.black.withAlphaComponent(0.55)

        footer.text = message
        footer.fontColor = color
        footer.run(SKAction.sequence([
            SKAction.wait(forDuration: 1.4),
            SKAction.run { [weak footer] in
                footer?.text = restoreText
                footer?.fontColor = originalColor
            }
        ]))
    }

    private func triggerHaptic(_ kind: HapticKind) {
        switch kind {
        case .light:     UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success:   UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private enum HapticKind { case light, selection, success }
}
