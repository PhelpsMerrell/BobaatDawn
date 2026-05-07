//
//  SaveSystemButton.swift
//  BobaAtDawn
//
//  Interactive button for save system actions
//

import SpriteKit

@objc(SaveSystemButton)
class SaveSystemButton: RotatableObject {

    private enum CodingKeys {
        static let buttonType = "editorSaveButtonType"
    }
    
    enum ButtonType {
        case saveJournal
        case clearData
        case npcStatus
        
        var emoji: String {
            switch self {
            case .saveJournal: return "📔"
            case .clearData: return "🗑️"
            case .npcStatus: return "📈"
            }
        }
        
        var name: String {
            switch self {
            case .saveJournal: return "save_journal"
            case .clearData: return "clear_data_button"
            case .npcStatus: return "npc_status_tracker"
            }
        }
    }
    
    let buttonType: ButtonType
    
    init(type: ButtonType) {
        self.buttonType = type
        
        // Create as a colored sprite node (like ingredient stations)
        super.init(type: .furniture, color: SKColor.systemBlue.withAlphaComponent(0.3), shape: "button")
        
        // Override the name
        name = type.name
        
        // Add emoji label on top
        let emojiLabel = SKLabelNode(text: type.emoji)
        emojiLabel.fontSize = 32
        emojiLabel.fontName = "Arial"
        emojiLabel.horizontalAlignmentMode = .center
        emojiLabel.verticalAlignmentMode = .center
        emojiLabel.position = .zero
        emojiLabel.zPosition = 1
        emojiLabel.name = "emoji_label"
        addChild(emojiLabel)
        
        print("🔧 Created SaveSystemButton: \(type.emoji) (\(type.name))")
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.buttonType = SaveSystemButton.buttonType(from: aDecoder.decodeObject(forKey: CodingKeys.buttonType) as? String)
        super.init(coder: aDecoder)
        ensureEmojiLabel()
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(SaveSystemButton.string(from: buttonType), forKey: CodingKeys.buttonType)
    }
    
    // Make buttons not carriable (they should stay in place)
    override var canBeCarried: Bool {
        return false
    }

    private func ensureEmojiLabel() {
        guard childNode(withName: "emoji_label") == nil else { return }

        let emojiLabel = SKLabelNode(text: buttonType.emoji)
        emojiLabel.fontSize = 32
        emojiLabel.fontName = "Arial"
        emojiLabel.horizontalAlignmentMode = .center
        emojiLabel.verticalAlignmentMode = .center
        emojiLabel.position = .zero
        emojiLabel.zPosition = 1
        emojiLabel.name = "emoji_label"
        addChild(emojiLabel)
    }
}

private extension SaveSystemButton {
    static func string(from type: ButtonType) -> String {
        switch type {
        case .saveJournal:
            return "saveJournal"
        case .clearData:
            return "clearData"
        case .npcStatus:
            return "npcStatus"
        }
    }

    static func buttonType(from string: String?) -> ButtonType {
        switch string {
        case "clearData":
            return .clearData
        case "npcStatus":
            return .npcStatus
        default:
            return .saveJournal
        }
    }
}
