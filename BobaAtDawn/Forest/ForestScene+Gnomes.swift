//
//  ForestScene+Gnomes.swift
//  BobaAtDawn
//
//  Forest-side hooks for the gnome simulation. Gnomes pass through the
//  forest while commuting between the oak and the cave; this extension
//  drives spawning + tick-driven gnome conversations in forest rooms.
//
//  The bulk of the gnome logic lives in GnomeManager. Here we just wire
//  up the callbacks the manager needs (registerForestScene + spawn on
//  room change) and run the conversation tick.
//

import SpriteKit

extension ForestScene {

    /// Called from setupCurrentRoom (we add a hook there that calls
    /// this), and on initial scene load. Spawns transit gnomes for the
    /// current forest room.
    func refreshForestGnomeSpawns() {
        GnomeManager.shared.registerForestScene(self)
        GnomeManager.shared.spawnVisibleGnomes(inForestRoom: currentRoom, scene: self)
        // Cart procession may pass through this room — spawn visual if
        // the cart is logically here right now.
        GnomeManager.shared.spawnVisibleCartIfPresent(
            inForestRoom: currentRoom, scene: self
        )
    }

    /// Called every frame from updateSpecificContent. Drives ambient
    /// gnome chatter + applies any deferred wander targets on the
    /// visible gnome nodes.
    func tickForestGnomeConversation() {
        let agents = GnomeManager.shared.agents.filter { $0.sceneNode != nil }
        GnomeConversationService.shared.tick(in: self, agents: agents)
    }

    /// Network-message handler for gnome-related envelopes received
    /// while the player is in the forest. Returns true if the envelope
    /// was a gnome message and was handled, so the caller can short-
    /// circuit the rest of its switch.
    @discardableResult
    func handleForestGnomeNetworkMessage(_ envelope: NetworkEnvelope) -> Bool {
        switch envelope.type {

        case .gnomeStateSync:
            guard let msg = try? envelope.decode(GnomeStateSyncMessage.self) else { return true }
            GnomeManager.shared.applyRemoteState(msg)
            return true

        case .gnomeRosterRefresh:
            guard let msg = try? envelope.decode(GnomeRosterRefreshMessage.self) else { return true }
            GnomeManager.shared.applyRemoteRosterRefresh(msg)
            return true

        case .treasuryUpdate:
            guard let msg = try? envelope.decode(TreasuryUpdateMessage.self) else { return true }
            GnomeManager.shared.applyRemoteTreasury(newCount: msg.newCount, didReset: msg.didReset)
            return true

        case .gnomeConversationLine:
            guard let msg = try? envelope.decode(GnomeConversationLineMessage.self) else { return true }
            GnomeConversationService.shared.handleRemoteLine(msg, in: self)
            return true

        case .gnomeConversationEnded:
            guard let msg = try? envelope.decode(GnomeConversationEndedMessage.self) else { return true }
            GnomeConversationService.shared.handleRemoteEnd(msg)
            return true

        default:
            return false
        }
    }
}
