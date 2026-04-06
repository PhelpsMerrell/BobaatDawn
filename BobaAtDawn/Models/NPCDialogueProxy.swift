//
//  NPCDialogueProxy.swift
//  BobaAtDawn
//
//  DEPRECATED: This file is no longer needed.
//  BaseNPC now conforms to DialoguePresenter directly, eliminating the
//  need for a proxy bridge between shop NPCs and the dialogue system.
//
//  Safe to delete from Xcode. Kept temporarily so existing references
//  don't cause build failures during migration.
//

import SpriteKit

/// DEPRECATED — use BaseNPC's DialoguePresenter conformance instead.
@available(*, deprecated, message: "BaseNPC conforms to DialoguePresenter directly")
class NPCDialogueProxy {
    let npc: ShopNPC
    let npcId: String
    
    init(npc: ShopNPC, characterId: String) {
        self.npc = npc
        self.npcId = characterId
    }
    
    var position: CGPoint { npc.position }
    func freeze() { npc.freeze() }
    func unfreeze() { npc.unfreeze() }
}
