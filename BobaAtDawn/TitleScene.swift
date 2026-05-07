//
//  TitleScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/19/25.
//

import SpriteKit
import UIKit

@objc(TitleScene)
class TitleScene: SKScene {

    private enum SessionChoice: String {
        case newGame = "new_game"
        case loadGame = "load_game"

        var lobbyTitle: String {
            switch self {
            case .newGame: return "New Game Lobby"
            case .loadGame: return "Load Game Lobby"
            }
        }
    }

    private enum SlotPickerPurpose {
        case newGame
        case loadGame

        var title: String {
            switch self {
            case .newGame: return "Choose a Slot"
            case .loadGame: return "Load Game"
            }
        }
    }

    private enum ScreenState {
        case home
        case slotPicker(SlotPickerPurpose)
        case hostLobby(SessionChoice)
        case guestLobby
    }

    // MARK: - Initializers
    override init(size: CGSize) {
        super.init(size: size)
        self.scaleMode = .aspectFill
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.scaleMode = .aspectFill
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    // MARK: - UI Elements
    private var titleLabel: SKLabelNode!
    private var subtitleLabel: SKLabelNode!
    private var startButton: SKSpriteNode!
    private var backgroundGradient: SKSpriteNode!
    private var hostButton: SKSpriteNode!
    private var joinButton: SKSpriteNode!
    private var multiplayerStatusLabel: SKLabelNode!
    private var auxiliaryActionButton: SKLabelNode!

    // "Erase Save Data" button — added programmatically because
    // GameScene.sks editing is fragile. Two-tap confirm to avoid
    // an accidental wipe.
    private var eraseSaveButton: SKLabelNode!
    private var eraseSaveArmed: Bool = false
    private var eraseSaveDisarmAction: SKAction?

    // MARK: - Animation Properties
    private var floatingBoba: [SKSpriteNode] = []
    private let numberOfBoba = 8
    private var currentScreenState: ScreenState = .home
    private var pendingSessionChoice: SessionChoice?
    private var hasStartedGameTransition = false
    private var buttonLayoutsCaptured = false
    private var startButtonLobbyPosition = CGPoint.zero
    private var hostButtonLobbyPosition = CGPoint.zero
    private var joinButtonLobbyPosition = CGPoint.zero
    private var centeredSecondaryButtonPosition = CGPoint.zero

    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        bindSceneNodes()
        captureButtonLayouts()
        configureSceneActions()
        setupAuxiliaryActionButton()
        applyConnectedLobbyStateIfNeeded()
        setupFloatingBoba()
        setupEraseSaveButton()
        setupInitialAnimations()

        MultiplayerService.shared.delegate = self

        // Authenticate with Game Center immediately on scene load.
        // This ensures the player is signed in BEFORE they tap Host/Join,
        // and also registers for invite notifications so invites work.
        if let vc = view.window?.rootViewController {
            MultiplayerService.shared.authenticate(presenting: vc)
        } else {
            // Window might not be ready yet in didMove — retry shortly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                if let vc = self?.view?.window?.rootViewController {
                    MultiplayerService.shared.authenticate(presenting: vc)
                }
            }
        }

        print("🎬 Title screen loaded")
    }

    private func bindSceneNodes() {
        backgroundGradient = requiredSceneNode(named: "background_gradient", as: SKSpriteNode.self)
        titleLabel = requiredSceneNode(named: "title_label", as: SKLabelNode.self)
        subtitleLabel = requiredSceneNode(named: "subtitle_label", as: SKLabelNode.self)
        startButton = requiredSceneNode(named: "startButton", as: SKSpriteNode.self)
        hostButton = requiredSceneNode(named: "hostButton", as: SKSpriteNode.self)
        joinButton = requiredSceneNode(named: "joinButton", as: SKSpriteNode.self)
        multiplayerStatusLabel = requiredSceneNode(named: "multiplayer_status_label", as: SKLabelNode.self)
    }

    private func captureButtonLayouts() {
        guard !buttonLayoutsCaptured else { return }
        startButtonLobbyPosition = startButton.position
        hostButtonLobbyPosition = hostButton.position
        joinButtonLobbyPosition = joinButton.position
        centeredSecondaryButtonPosition = CGPoint(
            x: 0,
            y: (startButton.position.y + hostButton.position.y) / 2.0
        )
        buttonLayoutsCaptured = true
    }

    private func slotPickerButtonPositions() -> [CGPoint] {
        let spacing = max(96.0, min(110.0, size.height * 0.1))
        let centerY = startButtonLobbyPosition.y - 20
        return [
            CGPoint(x: 0, y: centerY + spacing),
            CGPoint(x: 0, y: centerY),
            CGPoint(x: 0, y: centerY - spacing)
        ]
    }

    private func configureSceneActions() {
        let colorShift = SKAction.sequence([
            SKAction.colorize(with: SKColor(red: 0.3, green: 0.2, blue: 0.6, alpha: 1.0),
                              colorBlendFactor: 0.3, duration: 3.0),
            SKAction.colorize(with: SKColor(red: 0.2, green: 0.4, blue: 0.5, alpha: 1.0),
                              colorBlendFactor: 0.3, duration: 3.0)
        ])
        backgroundGradient.run(SKAction.repeatForever(colorShift))

        let breathe = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 2.0),
            SKAction.scale(to: 1.0, duration: 2.0)
        ])
        titleLabel.run(SKAction.repeatForever(breathe))

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 1.5),
            SKAction.scale(to: 1.0, duration: 1.5)
        ])
        startButton.run(SKAction.repeatForever(pulse))

        multiplayerStatusLabel.text = ""
    }

    private func applyConnectedLobbyStateIfNeeded() {
        if MultiplayerService.shared.isConnected {
            if MultiplayerService.shared.isHost {
                let selection = pendingSessionChoice ?? .loadGame
                currentScreenState = .hostLobby(selection)
                applyScreenState(statusOverride: "Friend connected. Start when you're ready.")
            } else {
                currentScreenState = .guestLobby
                applyScreenState(statusOverride: "Connected. Waiting for the host to start.")
            }
            return
        }

        currentScreenState = .home
        applyScreenState()
    }

    private func applyScreenState(statusOverride: String? = nil) {
        let previousStatus = multiplayerStatusLabel.text ?? ""

        switch currentScreenState {
        case .home:
            pendingSessionChoice = nil
            subtitleLabel.text = "A Cozy Brewing Adventure"
            configure(button: startButton, title: "New Game", position: startButtonLobbyPosition, hidden: false)
            configure(button: hostButton, title: "Load Game", position: centeredSecondaryButtonPosition, hidden: false)
            configure(button: joinButton, title: "Back", position: joinButtonLobbyPosition, hidden: true)
            configureAuxiliaryButton(title: "Back", hidden: true)
            multiplayerStatusLabel.text = statusOverride ?? ""

        case .slotPicker(let purpose):
            subtitleLabel.text = purpose.title
            let slots = SaveService.shared.loadSaveSlots()
            let positions = slotPickerButtonPositions()
            configure(button: startButton, title: slotButtonTitle(for: slots[0]), position: positions[0], hidden: false)
            configure(button: hostButton, title: slotButtonTitle(for: slots[1]), position: positions[1], hidden: false)
            configure(button: joinButton, title: slotButtonTitle(for: slots[2]), position: positions[2], hidden: false)
            configureAuxiliaryButton(title: "Back", hidden: false)
            multiplayerStatusLabel.text = statusOverride ?? "Tap a slot to open its lobby or delete it."

        case .hostLobby(let choice):
            pendingSessionChoice = choice
            subtitleLabel.text = "\(choice.lobbyTitle): \(SaveService.shared.currentSaveSlotSummary().name)"
            configure(button: startButton, title: "Start Game", position: startButtonLobbyPosition, hidden: false)
            configure(button: hostButton, title: "Invite Friend", position: hostButtonLobbyPosition, hidden: false)
            configure(button: joinButton, title: "Back", position: joinButtonLobbyPosition, hidden: false)
            configureAuxiliaryButton(title: "Back", hidden: true)
            let fallback = MultiplayerService.shared.isConnected
                ? "Friend connected. Start when you're ready."
                : "Invite a friend or start solo."
            multiplayerStatusLabel.text = statusOverride ?? (previousStatus.isEmpty ? fallback : previousStatus)

        case .guestLobby:
            subtitleLabel.text = "Waiting for Host"
            configure(button: startButton, title: "Start Game", position: startButtonLobbyPosition, hidden: true)
            configure(button: hostButton, title: "Invite Friend", position: hostButtonLobbyPosition, hidden: true)
            configure(button: joinButton, title: "Leave Lobby", position: centeredSecondaryButtonPosition, hidden: false)
            configureAuxiliaryButton(title: "Back", hidden: true)
            let fallback = "Connected. Waiting for the host to start."
            multiplayerStatusLabel.text = statusOverride ?? (previousStatus.isEmpty ? fallback : previousStatus)
        }
    }

    private func configure(button: SKSpriteNode, title: String, position: CGPoint, hidden: Bool) {
        button.position = position
        button.isHidden = hidden
        button.alpha = hidden ? 0 : 1
        setButtonTitle(button, title: title)
    }

    private func setButtonTitle(_ button: SKSpriteNode, title: String) {
        guard let buttonName = button.name,
              let label = button.childNode(withName: "\(buttonName)_label") as? SKLabelNode else { return }
        label.text = title
    }

    private func configureAuxiliaryButton(title: String, hidden: Bool) {
        guard auxiliaryActionButton != nil else { return }
        auxiliaryActionButton.text = title
        auxiliaryActionButton.isHidden = hidden
        auxiliaryActionButton.alpha = hidden ? 0 : 0.8
    }

    private func slotButtonTitle(for slot: SaveService.SaveSlotSummary) -> String {
        let baseName = slot.name.count > 18 ? String(slot.name.prefix(15)) + "..." : slot.name
        return "\(slot.index). \(baseName)"
    }

    // MARK: - Floating Boba Decoration
    private func setupFloatingBoba() {
        floatingBoba.forEach { $0.removeFromParent() }
        floatingBoba.removeAll()

        for i in 0..<numberOfBoba {
            let boba = createFloatingBoba(index: i)
            floatingBoba.append(boba)
            addChild(boba)
        }
    }

    private func createFloatingBoba(index: Int) -> SKSpriteNode {
        let colors = [
            SKColor.brown.withAlphaComponent(0.6),
            SKColor.orange.withAlphaComponent(0.5),
            SKColor.purple.withAlphaComponent(0.4),
            SKColor.green.withAlphaComponent(0.5)
        ]

        let boba = SKSpriteNode(color: colors[index % colors.count],
                                size: CGSize(width: 20, height: 20))

        let horizontalInset = max(120.0, size.width * 0.12)
        let verticalInset = max(160.0, size.height * 0.14)
        let randomX = CGFloat.random(in: (-size.width / 2 + horizontalInset)...(size.width / 2 - horizontalInset))
        let randomY = CGFloat.random(in: (-size.height / 2 + verticalInset)...(size.height / 2 - verticalInset))
        boba.position = CGPoint(x: randomX, y: randomY)
        boba.zPosition = 1

        let circle = SKShapeNode(circleOfRadius: 10)
        circle.fillColor = colors[index % colors.count]
        circle.strokeColor = SKColor.clear
        boba.addChild(circle)

        return boba
    }

    // MARK: - Initial Animations
    private func setupInitialAnimations() {
        for (index, boba) in floatingBoba.enumerated() {
            let delay = Double(index) * 0.3

            let float = SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.repeatForever(
                    SKAction.sequence([
                        SKAction.moveBy(x: CGFloat.random(in: -30...30),
                                        y: CGFloat.random(in: -20...20),
                                        duration: 4.0 + Double.random(in: -1...1)),
                        SKAction.moveBy(x: CGFloat.random(in: -30...30),
                                        y: CGFloat.random(in: -20...20),
                                        duration: 4.0 + Double.random(in: -1...1))
                    ])
                )
            ])

            let rotate = SKAction.repeatForever(
                SKAction.rotate(byAngle: .pi * 2, duration: 8.0 + Double.random(in: -2...2))
            )

            boba.run(float)
            boba.run(rotate)
        }

        titleLabel.alpha = 0
        titleLabel.setScale(0.5)
        subtitleLabel.alpha = 0
        subtitleLabel.setScale(0.8)

        let titleEntrance = SKAction.group([
            SKAction.fadeIn(withDuration: 1.0),
            SKAction.scale(to: 1.0, duration: 1.0)
        ])
        titleLabel.run(titleEntrance)

        let subtitleEntrance = SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.9),
                SKAction.scale(to: 1.0, duration: 0.9)
            ])
        ])
        subtitleLabel.run(subtitleEntrance)

        startButton.alpha = 0
        startButton.setScale(0.8)
        hostButton.alpha = 0
        joinButton.alpha = 0

        let buttonEntrance = SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.8),
                SKAction.scale(to: 1.0, duration: 0.8)
            ])
        ])
        if !startButton.isHidden {
            startButton.run(buttonEntrance)
        }

        let multiplayerFadeIn = SKAction.sequence([
            SKAction.wait(forDuration: 0.8),
            SKAction.fadeIn(withDuration: 0.5)
        ])
        if !hostButton.isHidden {
            hostButton.run(multiplayerFadeIn)
        }
        if !joinButton.isHidden {
            joinButton.run(multiplayerFadeIn)
        }
    }

    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        let triggerNode = touchedNode.firstNamedAncestor(matching: ["startButton", "hostButton", "joinButton", "erase_save_button", "title_aux_button"])

        if triggerNode?.name == "startButton" {
            handleStartButtonTapped()
        } else if triggerNode?.name == "hostButton" {
            handleHostTapped()
        } else if triggerNode?.name == "joinButton" {
            handleJoinTapped()
        } else if triggerNode?.name == "erase_save_button" {
            handleEraseSaveTapped()
        } else if triggerNode?.name == "title_aux_button" {
            handleAuxiliaryTapped()
        }
    }

    private func handleStartButtonTapped() {
        runButtonPress(on: startButton) {
            switch self.currentScreenState {
            case .home:
                self.beginNewGameFlow()
            case .slotPicker:
                self.presentSlotActionMenu(for: 1)
            case .hostLobby:
                self.startSelectedSession()
            case .guestLobby:
                break
            }
        }
    }

    private func transitionToGame() {
        guard !hasStartedGameTransition else { return }
        hasStartedGameTransition = true
        print("🚀 Transitioning to game scene...")

        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let scaleDown = SKAction.scale(to: 0.8, duration: 0.5)
        let exitAnimation = SKAction.group([fadeOut, scaleDown])

        run(exitAnimation) {
            let gameScene = SceneFactory.loadGameScene(size: self.size)
            let transition = SKTransition.fade(withDuration: 0.5)
            self.view?.presentScene(gameScene, transition: transition)
        }
    }

    // MARK: - Multiplayer Actions
    private func handleHostTapped() {
        switch currentScreenState {
        case .home:
            runButtonPress(on: hostButton) {
                self.enterSlotPicker(.loadGame)
            }
        case .slotPicker:
            runButtonPress(on: hostButton) {
                self.presentSlotActionMenu(for: 2)
            }
        case .hostLobby:
            runButtonPress(on: hostButton) {
                self.inviteFriendFromLobby()
            }
        case .guestLobby:
            break
        }
    }

    private func handleJoinTapped() {
        runButtonPress(on: joinButton) {
            switch self.currentScreenState {
            case .slotPicker:
                self.presentSlotActionMenu(for: 3)
            case .hostLobby:
                self.leaveHostLobby()
            case .guestLobby:
                self.leaveGuestLobby()
            case .home:
                break
            }
        }
    }

    private func handleAuxiliaryTapped() {
        guard case .slotPicker = currentScreenState else { return }
        let pressDown = SKAction.scale(to: 0.95, duration: 0.08)
        let pressUp = SKAction.scale(to: 1.0, duration: 0.08)
        auxiliaryActionButton.run(SKAction.sequence([pressDown, pressUp])) {
            self.currentScreenState = .home
            self.applyScreenState()
        }
    }

    private func runButtonPress(on button: SKSpriteNode, completion: @escaping () -> Void) {
        let pressDown = SKAction.scale(to: 0.95, duration: 0.1)
        let pressUp = SKAction.scale(to: 1.0, duration: 0.1)
        let buttonPress = SKAction.sequence([pressDown, pressUp])
        button.run(buttonPress, completion: completion)
    }

    private func beginNewGameFlow() {
        enterSlotPicker(.newGame, statusOverride: "Choose a slot to open its lobby or delete it.")
    }

    private func enterSlotPicker(_ purpose: SlotPickerPurpose, statusOverride: String? = nil) {
        hasStartedGameTransition = false
        currentScreenState = .slotPicker(purpose)
        applyScreenState(statusOverride: statusOverride)
    }

    private func enterHostLobby(_ choice: SessionChoice, statusOverride: String? = nil) {
        if MultiplayerService.shared.isConnected && !MultiplayerService.shared.isHost {
            MultiplayerService.shared.disconnect()
        }
        hasStartedGameTransition = false
        currentScreenState = .hostLobby(choice)
        let fallback = choice == .newGame
            ? "Start fresh or invite a friend."
            : "Load your world or invite a friend."
        applyScreenState(statusOverride: statusOverride ?? fallback)
    }

    private func presentSlotActionMenu(for slotIndex: Int) {
        guard case let .slotPicker(purpose) = currentScreenState,
              let rootViewController = view?.window?.rootViewController else { return }

        let slot = SaveService.shared.loadSaveSlots()[max(0, min(slotIndex - 1, 2))]
        let description: String
        if slot.isEmpty {
            description = "This slot is empty."
        } else if let lastSaved = slot.lastSaved {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            description = "Day \(slot.dayCount). Last saved \(formatter.string(from: lastSaved))."
        } else {
            description = "Day \(slot.dayCount)."
        }

        let alert = UIAlertController(title: slot.name, message: description, preferredStyle: .alert)
        let choice = sessionChoice(for: slot, purpose: purpose)
        alert.addAction(UIAlertAction(title: "Open Lobby", style: .default) { [weak self] _ in
            self?.openSlotLobby(slot: slot, choice: choice)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.presentDeleteSlotConfirmation(for: slot)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        rootViewController.present(alert, animated: true)
    }

    private func sessionChoice(for slot: SaveService.SaveSlotSummary, purpose: SlotPickerPurpose) -> SessionChoice {
        switch purpose {
        case .newGame:
            return .newGame
        case .loadGame:
            return slot.isEmpty ? .newGame : .loadGame
        }
    }

    private func openSlotLobby(slot: SaveService.SaveSlotSummary, choice: SessionChoice) {
        let activeSlot = SaveService.shared.activateSaveSlot(index: slot.index)
        let status: String
        switch choice {
        case .newGame:
            status = "Starting fresh in \(activeSlot.name). Invite a friend or start solo."
        case .loadGame:
            status = "Loaded \(activeSlot.name). Invite a friend or start solo."
        }
        enterHostLobby(choice, statusOverride: status)
    }

    private func presentDeleteSlotConfirmation(for slot: SaveService.SaveSlotSummary) {
        guard let rootViewController = view?.window?.rootViewController else { return }
        let message = slot.isEmpty
            ? "Delete this slot and restore its default empty state?"
            : "Delete this slot and erase its saved progress?"
        let alert = UIAlertController(
            title: "Delete \(slot.name)?",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            let cleared = SaveService.shared.clearSaveSlot(index: slot.index)
            if let self, case .slotPicker = self.currentScreenState {
                self.applyScreenState(statusOverride: "Deleted \(cleared.name).")
            } else {
                self?.applyScreenState(statusOverride: "Deleted \(cleared.name).")
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        rootViewController.present(alert, animated: true)
    }

    private func inviteFriendFromLobby() {
        guard MultiplayerService.shared.isAuthenticated else {
            multiplayerStatusLabel.text = "Signing into Game Center..."
            if let vc = view?.window?.rootViewController {
                MultiplayerService.shared.authenticate(presenting: vc)
            }
            return
        }

        guard !MultiplayerService.shared.isConnected else {
            multiplayerStatusLabel.text = "Friend already connected."
            return
        }

        multiplayerStatusLabel.text = "Choose your friend in Game Center. Apple handles the invite from there."
        MultiplayerService.shared.inviteFriend()
    }

    private func startSelectedSession() {
        guard case let .hostLobby(choice) = currentScreenState else { return }

        if choice == .newGame {
            SaveService.shared.resetActiveSaveSlotForNewGame()
        } else {
            SaveService.shared.prepareActiveSlotForLaunch(startFreshIfEmpty: true)
        }

        if MultiplayerService.shared.isConnected {
            multiplayerStatusLabel.text = "Starting game..."
            MultiplayerService.shared.send(
                type: .lobbyStart,
                payload: LobbyStartMessage(
                    sessionType: choice.rawValue,
                    slotIndex: SaveService.shared.currentSaveSlotIndex
                )
            )
        } else {
            MultiplayerService.shared.disconnect()
        }

        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.15),
            SKAction.run { [weak self] in
                self?.transitionToGame()
            }
        ]))
    }

    private func leaveHostLobby() {
        MultiplayerService.shared.disconnect()
        currentScreenState = .home
        applyScreenState()
    }

    private func leaveGuestLobby() {
        MultiplayerService.shared.disconnect()
        currentScreenState = .home
        applyScreenState(statusOverride: "Left the lobby.")
    }

    // MARK: - Erase Save Data

    /// Inject a small "Erase Save Data" pill at the bottom of the title
    /// scene. Hidden in plain sight — it's small and dim until tapped
    /// once, at which point it changes to a clearly destructive
    /// "Tap again to confirm" state.
    private func setupEraseSaveButton() {
        let button = SKLabelNode(fontNamed: "Helvetica")
        button.text = "Erase Save Data"
        button.fontSize = 14
        button.fontColor = SKColor.white.withAlphaComponent(0.45)
        button.horizontalAlignmentMode = .center
        button.verticalAlignmentMode = .center
        button.name = "erase_save_button"

        // Park it just above the bottom edge.
        let yOffset = -size.height / 2 + 60
        button.position = CGPoint(x: 0, y: yOffset)
        button.zPosition = 50
        button.alpha = 0

        addChild(button)
        eraseSaveButton = button

        // Fade in alongside the other buttons.
        let fadeIn = SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.fadeAlpha(to: 0.55, duration: 0.6)
        ])
        button.run(fadeIn)
    }

    private func setupAuxiliaryActionButton() {
        let button = SKLabelNode(fontNamed: "Helvetica-Bold")
        button.text = "Back"
        button.fontSize = 16
        button.fontColor = SKColor.white.withAlphaComponent(0.8)
        button.horizontalAlignmentMode = .center
        button.verticalAlignmentMode = .center
        button.name = "title_aux_button"
        button.position = CGPoint(x: 0, y: -size.height / 2 + 94)
        button.zPosition = 55
        button.isHidden = true
        button.alpha = 0
        addChild(button)
        auxiliaryActionButton = button
    }

    private func handleEraseSaveTapped() {
        if !eraseSaveArmed {
            armEraseSaveButton()
            return
        }
        confirmEraseSave()
    }

    private func armEraseSaveButton() {
        eraseSaveArmed = true
        eraseSaveButton.text = "Tap again to confirm — erases everything"
        eraseSaveButton.fontColor = SKColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
        eraseSaveButton.alpha = 1.0

        // Pulse to draw the eye and signal "this is dangerous".
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 0.4),
            SKAction.scale(to: 1.0, duration: 0.4)
        ]))
        eraseSaveButton.run(pulse, withKey: "erase_pulse")

        // Auto-disarm after a few seconds if they don't confirm — a
        // stray double-tap shouldn't ever wipe their save by accident.
        let disarm = SKAction.sequence([
            SKAction.wait(forDuration: 4.0),
            SKAction.run { [weak self] in self?.disarmEraseSaveButton() }
        ])
        eraseSaveDisarmAction = disarm
        run(disarm, withKey: "erase_disarm")
    }

    private func disarmEraseSaveButton() {
        eraseSaveArmed = false
        eraseSaveButton.removeAction(forKey: "erase_pulse")
        eraseSaveButton.setScale(1.0)
        eraseSaveButton.text = "Erase Save Data"
        eraseSaveButton.fontColor = SKColor.white.withAlphaComponent(0.45)
        eraseSaveButton.alpha = 0.55
        removeAction(forKey: "erase_disarm")
    }

    private func confirmEraseSave() {
        // Cancel any in-flight disarm timer.
        removeAction(forKey: "erase_disarm")
        eraseSaveButton.removeAction(forKey: "erase_pulse")
        eraseSaveButton.setScale(1.0)

        SaveService.shared.clearAllSaveData()
        currentScreenState = .home
        applyScreenState(statusOverride: "Save data erased.")
        if MultiplayerService.shared.isConnected {
            MultiplayerService.shared.disconnect()
        }

        // Visual confirmation.
        eraseSaveButton.text = "Save data erased."
        eraseSaveButton.fontColor = SKColor(red: 0.6, green: 0.95, blue: 0.6, alpha: 1.0)
        eraseSaveArmed = false

        // Brief celebration pulse, then fade back to the dim default.
        eraseSaveButton.run(SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 0.18),
            SKAction.scale(to: 1.0, duration: 0.18),
            SKAction.wait(forDuration: 1.6),
            SKAction.run { [weak self] in self?.disarmEraseSaveButton() }
        ]))

        Log.info(.save, "Save data erased from title screen — fresh world ready")
    }
}

// MARK: - MultiplayerServiceDelegate

extension TitleScene: MultiplayerServiceDelegate {
    func multiplayerDidConnect(isHost: Bool) {
        hasStartedGameTransition = false

        if isHost {
            let selection = pendingSessionChoice ?? .loadGame
            currentScreenState = .hostLobby(selection)
            applyScreenState(statusOverride: "Friend connected. Start when you're ready.")
        } else {
            currentScreenState = .guestLobby
            applyScreenState(statusOverride: "Connected. Waiting for the host to start.")
        }
    }

    func multiplayerDidDisconnect() {
        hasStartedGameTransition = false

        switch currentScreenState {
        case .home:
            if (multiplayerStatusLabel.text ?? "").isEmpty {
                multiplayerStatusLabel.text = "Disconnected."
            }
        case .slotPicker:
            applyScreenState(statusOverride: "Disconnected.")
        case .hostLobby:
            applyScreenState(statusOverride: "Friend disconnected. Invite again or start solo.")
        case .guestLobby:
            currentScreenState = .home
            applyScreenState(statusOverride: "Lobby closed.")
        }
    }

    func multiplayerDidReceive(_ envelope: NetworkEnvelope) {
        switch envelope.type {
        case .lobbyStart:
            guard !MultiplayerService.shared.isHost else { return }
            if let startMessage = try? envelope.decode(LobbyStartMessage.self) {
                SaveService.shared.activateSaveSlot(index: startMessage.slotIndex)
                let startFresh = startMessage.sessionType == SessionChoice.newGame.rawValue
                SaveService.shared.prepareActiveSlotForLaunch(startFreshIfEmpty: startFresh)
            }
            multiplayerStatusLabel.text = "Starting game..."
            transitionToGame()
        default:
            break
        }
    }

    func multiplayerDidFail(error: String) {
        multiplayerStatusLabel.text = error
    }
}
