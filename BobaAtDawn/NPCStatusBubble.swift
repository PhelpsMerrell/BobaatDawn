//
//  NPCStatusBubble.swift
//  BobaAtDawn
//
//  Scrollable status bubble showing NPC satisfaction and ritual eligibility.
//  Extracted from GameScene.swift.
//

import SpriteKit

class NPCStatusBubble: SKNode {
    private let bubbleBackground: SKShapeNode
    private let contentNode: SKNode
    private let scrollContainer: SKNode
    private var scrollOffset: CGFloat = 0
    private let maxScrollOffset: CGFloat
    private var longPressTimer: Timer?
    private let longPressDuration: TimeInterval = 0.6
    
    init(statusLines: [String], position: CGPoint) {
        let bubbleWidth: CGFloat = 280
        let bubbleHeight: CGFloat = 320
        let lineHeight: CGFloat = 18
        let padding: CGFloat = 15
        
        let contentHeight = CGFloat(statusLines.count) * lineHeight + padding
        let visibleHeight = bubbleHeight - padding * 2 - 30
        maxScrollOffset = max(0, contentHeight - visibleHeight)
        
        bubbleBackground = SKShapeNode(rectOf: CGSize(width: bubbleWidth, height: bubbleHeight), cornerRadius: 12)
        bubbleBackground.fillColor = SKColor.white.withAlphaComponent(0.95)
        bubbleBackground.strokeColor = SKColor.black.withAlphaComponent(0.7)
        bubbleBackground.lineWidth = 2
        
        scrollContainer = SKNode()
        contentNode = SKNode()
        
        super.init()
        
        self.position = position
        self.zPosition = ZLayers.statusBubble
        
        addChild(bubbleBackground)
        
        for (index, line) in statusLines.enumerated() {
            let label = SKLabelNode(text: line)
            label.fontName = line.hasPrefix("📈") ? "Arial-Bold" : "Arial"
            label.fontSize = line.hasPrefix("📈") ? 13 : 11
            label.fontColor = line.hasPrefix("📈") ? SKColor.darkGray : SKColor.black
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: (contentHeight / 2) - (CGFloat(index) * lineHeight) - padding)
            contentNode.addChild(label)
        }
        
        scrollContainer.addChild(contentNode)
        
        let clipNode = SKCropNode()
        let clipMask = SKSpriteNode(color: .white, size: CGSize(width: bubbleWidth - padding * 2, height: visibleHeight))
        clipMask.position = CGPoint(x: 0, y: 0)
        clipNode.maskNode = clipMask
        clipNode.addChild(scrollContainer)
        addChild(clipNode)
        
        let instructionText = maxScrollOffset > 0 ? "Drag to scroll · Long press to close" : "Long press to close"
        let closeLabel = SKLabelNode(text: instructionText)
        closeLabel.fontName = "Arial"
        closeLabel.fontSize = 9
        closeLabel.fontColor = SKColor.gray
        closeLabel.horizontalAlignmentMode = .center
        closeLabel.verticalAlignmentMode = .center
        closeLabel.position = CGPoint(x: 0, y: -(bubbleHeight / 2) + 12)
        addChild(closeLabel)
        
        if maxScrollOffset > 0 {
            let indicator = SKLabelNode(text: "⇅")
            indicator.fontName = "Arial"
            indicator.fontSize = 12
            indicator.fontColor = SKColor.gray
            indicator.horizontalAlignmentMode = .center
            indicator.verticalAlignmentMode = .center
            indicator.position = CGPoint(x: bubbleWidth / 2 - 15, y: 0)
            addChild(indicator)
        }
        
        bubbleBackground.name = "status_bubble"
        isUserInteractionEnabled = true
        
        alpha = 0
        setScale(0.5)
        run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.3),
            SKAction.scale(to: 1.0, duration: 0.3)
        ]))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        startLongPressTimer()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        cancelLongPressTimer()
        guard maxScrollOffset > 0 else { return }
        
        let location = touch.location(in: self)
        let prev = touch.previousLocation(in: self)
        
        if bubbleBackground.contains(location) {
            scrollOffset = max(-maxScrollOffset, min(0, scrollOffset + (location.y - prev.y)))
            contentNode.position.y = scrollOffset
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPressTimer()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPressTimer()
    }
    
    // MARK: - Long Press → Close
    
    private func startLongPressTimer() {
        cancelLongPressTimer()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.closeBubble()
        }
    }
    
    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
    
    private func closeBubble() {
        run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.scale(to: 0.8, duration: 0.2)
            ]),
            SKAction.removeFromParent()
        ]))
    }
}
