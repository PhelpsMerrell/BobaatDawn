//
//  NPCDialogueProxy.swift
//  BobaAtDawn
//
//  Bridge to connect shop NPCs with ForestNPC dialogue interface
//

import SpriteKit

/// Proxy class that makes shop NPCs compatible with DialogueService
/// DialogueService expects ForestNPC interface, but shop uses NPC class
class NPCDialogueProxy {
    let npc: NPC
    let npcId: String
    
    init(npc: NPC, characterId: String) {
        self.npc = npc
        self.npcId = characterId
    }
    
    var position: CGPoint {
        return npc.position
    }
    
    func freeze() {
        npc.pauseForDialogue()
    }
    
    func unfreeze() {
        npc.resumeFromDialogue()
    }
}
