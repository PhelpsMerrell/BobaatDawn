//
//  TitleScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/19/25.
//

import SpriteKit

class TitleScene: SKScene {
    
    // MARK: - Initializers
    override init(size: CGSize) {
        super.init(size: size)
        self.scaleMode = .aspectFill
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.scaleMode = .aspectFill
    }
    
    // MARK: - UI Elements
    private var titleLabel: SKLabelNode!
    private var startButton: SKSpriteNode!
    private var startButtonLabel: SKLabelNode!
    private var backgroundGradient: SKSpriteNode!
    private var hostButton: SKSpriteNode!
    private var joinButton: SKSpriteNode!
    private var multiplayerStatusLabel: SKLabelNode!
    
    // MARK: - Animation Properties
    private var floatingBoba: [SKSpriteNode] = []
    private let numberOfBoba = 8
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupBackground()
        setupTitle()
        setupStartButton()
        setupMultiplayerButtons()
        setupFloatingBoba()
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
        
        print("\u{1F3AC} Title screen loaded")
    }
    
    // MARK: - Background Setup
    private func setupBackground() {
        backgroundGradient = SKSpriteNode(color: SKColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0),
                                        size: size)
        backgroundGradient.position = CGPoint(x: size.width/2, y: size.height/2)
        backgroundGradient.zPosition = -10
        addChild(backgroundGradient)
        
        let colorShift = SKAction.sequence([
            SKAction.colorize(with: SKColor(red: 0.3, green: 0.2, blue: 0.6, alpha: 1.0),
                            colorBlendFactor: 0.3, duration: 3.0),
            SKAction.colorize(with: SKColor(red: 0.2, green: 0.4, blue: 0.5, alpha: 1.0),
                            colorBlendFactor: 0.3, duration: 3.0)
        ])
        backgroundGradient.run(SKAction.repeatForever(colorShift))
    }
    
    // MARK: - Title Setup
    private func setupTitle() {
        titleLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        titleLabel.text = "Boba at Dawn"
        titleLabel.fontSize = 48
        titleLabel.fontColor = SKColor.white
        titleLabel.position = CGPoint(x: size.width/2, y: size.height * 0.7)
        titleLabel.zPosition = 10
        addChild(titleLabel)
        
        let subtitleLabel = SKLabelNode(fontNamed: "Helvetica-Light")
        subtitleLabel.text = "A Cozy Brewing Adventure"
        subtitleLabel.fontSize = 20
        subtitleLabel.fontColor = SKColor.lightGray
        subtitleLabel.position = CGPoint(x: size.width/2, y: size.height * 0.65)
        subtitleLabel.zPosition = 10
        addChild(subtitleLabel)
        
        let breathe = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 2.0),
            SKAction.scale(to: 1.0, duration: 2.0)
        ])
        titleLabel.run(SKAction.repeatForever(breathe))
    }
    
    // MARK: - Start Button Setup
    private func setupStartButton() {
        startButton = SKSpriteNode(color: SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.9),
                                  size: CGSize(width: 200, height: 60))
        startButton.position = CGPoint(x: size.width/2, y: size.height * 0.4)
        startButton.zPosition = 5
        startButton.name = "startButton"
        
        let border = SKShapeNode(rect: CGRect(x: -100, y: -30, width: 200, height: 60),
                                cornerRadius: 10)
        border.fillColor = SKColor.clear
        border.strokeColor = SKColor.white.withAlphaComponent(0.7)
        border.lineWidth = 2
        startButton.addChild(border)
        
        addChild(startButton)
        
        startButtonLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        startButtonLabel.text = "Start Brewing"
        startButtonLabel.fontSize = 24
        startButtonLabel.fontColor = SKColor.white
        startButtonLabel.position = CGPoint(x: 0, y: -8)
        startButtonLabel.zPosition = 1
        startButton.addChild(startButtonLabel)
        
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.1, duration: 1.5),
            SKAction.scale(to: 1.0, duration: 1.5)
        ])
        startButton.run(SKAction.repeatForever(pulse))
    }
    
    // MARK: - Floating Boba Decoration
    private func setupFloatingBoba() {
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
        
        let randomX = CGFloat.random(in: 50...(size.width - 50))
        let randomY = CGFloat.random(in: 100...(size.height - 100))
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
        
        let titleEntrance = SKAction.group([
            SKAction.fadeIn(withDuration: 1.0),
            SKAction.scale(to: 1.0, duration: 1.0)
        ])
        titleLabel.run(titleEntrance)
        
        startButton.alpha = 0
        startButton.setScale(0.8)
        
        let buttonEntrance = SKAction.sequence([
            SKAction.wait(forDuration: 0.5),
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.8),
                SKAction.scale(to: 1.0, duration: 0.8)
            ])
        ])
        startButton.run(buttonEntrance)
    }
    
    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        if touchedNode.name == "startButton" || touchedNode.parent?.name == "startButton" {
            handleStartButtonTapped()
        } else if touchedNode.name == "hostButton" || touchedNode.parent?.name == "hostButton" {
            handleHostTapped()
        } else if touchedNode.name == "joinButton" || touchedNode.parent?.name == "joinButton" {
            handleJoinTapped()
        }
    }
    
    private func handleStartButtonTapped() {
        print("\u{1F3AF} Start button tapped!")
        
        let pressDown = SKAction.scale(to: 0.95, duration: 0.1)
        let pressUp = SKAction.scale(to: 1.0, duration: 0.1)
        let buttonPress = SKAction.sequence([pressDown, pressUp])
        
        startButton.run(buttonPress) {
            self.transitionToGame()
        }
    }
    
    private func transitionToGame() {
        print("\u{1F680} Transitioning to game scene...")
        
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let scaleDown = SKAction.scale(to: 0.8, duration: 0.5)
        let exitAnimation = SKAction.group([fadeOut, scaleDown])
        
        run(exitAnimation) {
            let gameScene = GameScene(size: self.size)
            gameScene.scaleMode = .aspectFill
            
            let transition = SKTransition.fade(withDuration: 0.5)
            self.view?.presentScene(gameScene, transition: transition)
        }
    }
    
    // MARK: - Multiplayer Buttons
    
    private func setupMultiplayerButtons() {
        let buttonWidth: CGFloat = 140
        let buttonHeight: CGFloat = 50
        let buttonY = size.height * 0.28
        let gap: CGFloat = 20
        
        hostButton = SKSpriteNode(color: SKColor(red: 0.3, green: 0.6, blue: 0.4, alpha: 0.9),
                                  size: CGSize(width: buttonWidth, height: buttonHeight))
        hostButton.position = CGPoint(x: size.width/2 - buttonWidth/2 - gap/2, y: buttonY)
        hostButton.zPosition = 5
        hostButton.name = "hostButton"
        hostButton.alpha = 0
        addChild(hostButton)
        
        let hostLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        hostLabel.text = "Host Game"
        hostLabel.fontSize = 18
        hostLabel.fontColor = .white
        hostLabel.position = CGPoint(x: 0, y: -6)
        hostLabel.zPosition = 1
        hostButton.addChild(hostLabel)
        
        joinButton = SKSpriteNode(color: SKColor(red: 0.4, green: 0.4, blue: 0.7, alpha: 0.9),
                                  size: CGSize(width: buttonWidth, height: buttonHeight))
        joinButton.position = CGPoint(x: size.width/2 + buttonWidth/2 + gap/2, y: buttonY)
        joinButton.zPosition = 5
        joinButton.name = "joinButton"
        joinButton.alpha = 0
        addChild(joinButton)
        
        let joinLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        joinLabel.text = "Join Game"
        joinLabel.fontSize = 18
        joinLabel.fontColor = .white
        joinLabel.position = CGPoint(x: 0, y: -6)
        joinLabel.zPosition = 1
        joinButton.addChild(joinLabel)
        
        multiplayerStatusLabel = SKLabelNode(fontNamed: "Helvetica-Light")
        multiplayerStatusLabel.text = ""
        multiplayerStatusLabel.fontSize = 14
        multiplayerStatusLabel.fontColor = .lightGray
        multiplayerStatusLabel.position = CGPoint(x: size.width/2, y: buttonY - 40)
        multiplayerStatusLabel.zPosition = 10
        addChild(multiplayerStatusLabel)
        
        let fadeIn = SKAction.sequence([
            SKAction.wait(forDuration: 0.8),
            SKAction.fadeIn(withDuration: 0.5)
        ])
        hostButton.run(fadeIn)
        joinButton.run(fadeIn)
    }
    
    // MARK: - Multiplayer Actions
    
    private func handleHostTapped() {
        guard MultiplayerService.shared.isAuthenticated else {
            multiplayerStatusLabel.text = "Signing into Game Center..."
            // Retry auth if it hasn't completed yet
            if let vc = view?.window?.rootViewController {
                MultiplayerService.shared.authenticate(presenting: vc)
            }
            return
        }
        multiplayerStatusLabel.text = "Waiting for player..."
        MultiplayerService.shared.hostGame()
    }
    
    private func handleJoinTapped() {
        guard MultiplayerService.shared.isAuthenticated else {
            multiplayerStatusLabel.text = "Signing into Game Center..."
            if let vc = view?.window?.rootViewController {
                MultiplayerService.shared.authenticate(presenting: vc)
            }
            return
        }
        multiplayerStatusLabel.text = "Looking for game..."
        MultiplayerService.shared.joinGame()
    }
}

// MARK: - MultiplayerServiceDelegate

extension TitleScene: MultiplayerServiceDelegate {
    func multiplayerDidConnect(isHost: Bool) {
        let role = isHost ? "HOST" : "GUEST"
        multiplayerStatusLabel.text = "Connected as \(role)! Starting..."
        run(SKAction.wait(forDuration: 0.8)) {
            self.transitionToGame()
        }
    }
    
    func multiplayerDidDisconnect() {
        multiplayerStatusLabel.text = "Disconnected."
    }
    
    func multiplayerDidReceive(_ envelope: NetworkEnvelope) { }
    
    func multiplayerDidFail(error: String) {
        multiplayerStatusLabel.text = error
    }
}
