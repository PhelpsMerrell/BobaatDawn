//
//  MultiplayerService.swift
//  BobaAtDawn
//
//  Wraps GameKit's GKMatch for real-time 2-player multiplayer.
//  Host drives time, NPC state, saves. Guest sends commands, receives state.
//

import GameKit
import Foundation

// MARK: - Multiplayer Delegate

protocol MultiplayerServiceDelegate: AnyObject {
    func multiplayerDidConnect(isHost: Bool)
    func multiplayerDidDisconnect()
    func multiplayerDidReceive(_ envelope: NetworkEnvelope)
    func multiplayerDidFail(error: String)
}

// MARK: - Multiplayer Service

final class MultiplayerService: NSObject {

    static let shared = MultiplayerService()

    weak var delegate: MultiplayerServiceDelegate?

    // MARK: - State
    private(set) var isAuthenticated = false
    private(set) var isConnected = false
    private(set) var isHost = false
    var isGuest: Bool { isConnected && !isHost }
    var isSolo: Bool { !isConnected }

    private var currentMatch: GKMatch?
    private var remotePlayer: GKPlayer?
    private weak var presentingViewController: UIViewController?

    // Position send throttle
    private var lastPositionSendTime: TimeInterval = 0
    private let positionSendInterval: TimeInterval = 1.0 / 20.0

    private override init() { super.init() }

    // MARK: - 1. Authentication

    func authenticate(presenting viewController: UIViewController) {
        self.presentingViewController = viewController

        let localPlayer = GKLocalPlayer.local
        localPlayer.authenticateHandler = { [weak self] gcAuthVC, error in
            guard let self else { return }

            if let authVC = gcAuthVC {
                viewController.present(authVC, animated: true)
                return
            }

            if let error {
                Log.error(.network, "Game Center auth failed: \(error.localizedDescription)")
                self.delegate?.multiplayerDidFail(error: "Game Center sign-in failed.")
                return
            }

            self.isAuthenticated = localPlayer.isAuthenticated
            if self.isAuthenticated {
                Log.info(.network, "Game Center authenticated: \(localPlayer.displayName)")
                GKLocalPlayer.local.register(self)
            }
        }
    }

    // MARK: - 2. Host a Game

    func hostGame() {
        guard isAuthenticated else {
            delegate?.multiplayerDidFail(error: "Not signed into Game Center.")
            return
        }
        guard let vc = presentingViewController else {
            delegate?.multiplayerDidFail(error: "No view controller to present matchmaker.")
            return
        }

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2

        guard let matchmakerVC = GKMatchmakerViewController(matchRequest: request) else {
            delegate?.multiplayerDidFail(error: "Could not create matchmaker.")
            return
        }
        matchmakerVC.matchmakerDelegate = self
        vc.present(matchmakerVC, animated: true)
        Log.info(.network, "Hosting game — waiting for guest…")
    }

    // MARK: - 3. Join a Game

    func joinGame() {
        guard isAuthenticated else {
            delegate?.multiplayerDidFail(error: "Not signed into Game Center.")
            return
        }
        guard let vc = presentingViewController else {
            delegate?.multiplayerDidFail(error: "No view controller to present matchmaker.")
            return
        }

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2

        guard let matchmakerVC = GKMatchmakerViewController(matchRequest: request) else {
            delegate?.multiplayerDidFail(error: "Could not create matchmaker.")
            return
        }
        matchmakerVC.matchmakerDelegate = self
        vc.present(matchmakerVC, animated: true)
        Log.info(.network, "Joining game — looking for host…")
    }

    // MARK: - 4. Disconnect

    func disconnect() {
        currentMatch?.disconnect()
        currentMatch?.delegate = nil
        currentMatch = nil
        remotePlayer = nil
        isConnected = false
        isHost = false
        Log.info(.network, "Disconnected from match")
    }

    // MARK: - 5. Send Messages

    func send(_ envelope: NetworkEnvelope) {
        guard let match = currentMatch else { return }

        do {
            let data = try envelope.encoded()
            let mode: GKMatch.SendDataMode = envelope.type.isReliable ? .reliable : .unreliable
            try match.sendData(toAllPlayers: data, with: mode)
        } catch {
            Log.error(.network, "Failed to send \(envelope.type.rawValue): \(error.localizedDescription)")
        }
    }

    func send<T: Encodable>(type: MessageType, payload: T) {
        do {
            let envelope = try NetworkEnvelope.make(type: type, payload: payload, isHost: isHost)
            send(envelope)
        } catch {
            Log.error(.network, "Failed to encode \(type.rawValue): \(error.localizedDescription)")
        }
    }

    // MARK: - 6. Throttled Position Send

    func sendPositionIfNeeded(position: CGPoint, isMoving: Bool,
                               animationDirection: String?, isCarrying: Bool,
                               carriedItemType: String?, sceneType: String = "shop") {
        let now = CACurrentMediaTime()
        guard now - lastPositionSendTime >= positionSendInterval else { return }
        lastPositionSendTime = now

        let msg = PlayerPositionMessage(
            position: CodablePoint(position),
            isMoving: isMoving,
            animationDirection: animationDirection,
            isCarrying: isCarrying,
            carriedItemType: carriedItemType,
            sceneType: sceneType
        )
        send(type: .playerPosition, payload: msg)
    }

    // MARK: - Helpers

    private func assignRoles(match: GKMatch) {
        guard let remote = match.players.first else { return }
        remotePlayer = remote

        let localID = GKLocalPlayer.local.teamPlayerID
        let remoteID = remote.teamPlayerID
        isHost = localID < remoteID

        Log.info(.network, "Role assigned: \(isHost ? "HOST" : "GUEST")")
    }

    private func handleMatchReady(_ match: GKMatch) {
        currentMatch = match
        match.delegate = self
        isConnected = true

        assignRoles(match: match)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.multiplayerDidConnect(isHost: self.isHost)
        }
    }
}

// MARK: - GKMatchDelegate

extension MultiplayerService: GKMatchDelegate {

    func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        do {
            let envelope = try NetworkEnvelope.from(data)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.multiplayerDidReceive(envelope)
            }
        } catch {
            Log.error(.network, "Failed to decode message: \(error.localizedDescription)")
        }
    }

    func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        switch state {
        case .connected:
            Log.info(.network, "\(player.displayName) connected")
            if match.expectedPlayerCount == 0 {
                handleMatchReady(match)
            }
        case .disconnected:
            Log.info(.network, "\(player.displayName) disconnected")
            isConnected = false
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.multiplayerDidDisconnect()
            }
        default:
            break
        }
    }

    func match(_ match: GKMatch, didFailWithError error: Error?) {
        Log.error(.network, "Match failed: \(error?.localizedDescription ?? "unknown")")
        disconnect()
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.multiplayerDidFail(error: "Connection lost.")
        }
    }
}

// MARK: - GKMatchmakerViewControllerDelegate

extension MultiplayerService: GKMatchmakerViewControllerDelegate {

    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        viewController.dismiss(animated: true)
        Log.info(.network, "Matchmaker cancelled")
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        viewController.dismiss(animated: true)
        Log.error(.network, "Matchmaker failed: \(error.localizedDescription)")
        delegate?.multiplayerDidFail(error: "Could not find a match.")
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        viewController.dismiss(animated: true)
        Log.info(.network, "Match found with \(match.players.count) player(s)")

        if match.expectedPlayerCount == 0 {
            handleMatchReady(match)
        } else {
            currentMatch = match
            match.delegate = self
        }
    }
}

// MARK: - GKLocalPlayerListener (Invite handling)

extension MultiplayerService: GKLocalPlayerListener {

    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        guard let vc = presentingViewController else { return }
        guard let matchmakerVC = GKMatchmakerViewController(invite: invite) else { return }
        matchmakerVC.matchmakerDelegate = self
        vc.present(matchmakerVC, animated: true)
        isHost = false
        Log.info(.network, "Accepted invite from \(invite.sender.displayName)")
    }
}
