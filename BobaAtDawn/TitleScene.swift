//
//  TitleScene.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/19/25.
//

import SpriteKit

class TitleScene: SKScene {
    
    // MARK: - UI Elements
    private var titleLabel: SKLabelNode!
    private var startButton: SKSpriteNode!
    private var startButtonLabel: SKLabelNode!
    private var backgroundGradient: SKSpriteNode!
    
    // MARK: - Animation Properties
    private var floatingBoba: [SKSpriteNode] = []
    private let numberOfBoba = 8
    
    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        setupBackground()
        setupTitle()
        setupStartButton()
        setupFloatingBoba()
        setupInitialAnimations()
        
        print("🎬 Title screen loaded")
    }
    
    // MARK: - Background Setup
    private func setupBackground() {
        // Create gradient background
        backgroundGradient = SKSpriteNode(color: SKColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0), 
                                        size: size)
        backgroundGradient.position = CGPoint(x: size.width/2, y: size.height/2)
        backgroundGradient.zPosition = -10
        addChild(backgroundGradient)
        
        // Add subtle color animation
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
        // Main title
        titleLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        titleLabel.text = "Boba at Dawn"
        titleLabel.fontSize = 48
        titleLabel.fontColor = SKColor.white
        titleLabel.position = CGPoint(x: size.width/2, y: size.height * 0.7)
        titleLabel.zPosition = 10
        addChild(titleLabel)
        
        // Subtitle
        let subtitleLabel = SKLabelNode(fontNamed: "Helvetica-Light")
        subtitleLabel.text = "A Cozy Brewing Adventure"
        subtitleLabel.fontSize = 20
        subtitleLabel.fontColor = SKColor.lightGray
        subtitleLabel.position = CGPoint(x: size.width/2, y: size.height * 0.65)
        subtitleLabel.zPosition = 10
        addChild(subtitleLabel)
        
        // Title breathing animation
        let breathe = SKAction.sequence([
            SKAction.scale(to: 1.05, duration: 2.0),
            SKAction.scale(to: 1.0, duration: 2.0)
        ])
        titleLabel.run(SKAction.repeatForever(breathe))
    }
    
    // MARK: - Start Button Setup
    private func setupStartButton() {
        // Button background
        startButton = SKSpriteNode(color: SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.9), 
                                  size: CGSize(width: 200, height: 60))
        startButton.position = CGPoint(x: size.width/2, y: size.height * 0.4)
        startButton.zPosition = 5
        startButton.name = "startButton"
        
        // Add rounded corners effect with border
        let border = SKShapeNode(rect: CGRect(x: -100, y: -30, width: 200, height: 60), 
                                cornerRadius: 10)
        border.fillColor = SKColor.clear
        border.strokeColor = SKColor.white.withAlphaComponent(0.7)
        border.lineWidth = 2
        startButton.addChild(border)
        
        addChild(startButton)
        
        // Button text
        startButtonLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        startButtonLabel.text = "Start Brewing"
        startButtonLabel.fontSize = 24
        startButtonLabel.fontColor = SKColor.white
        startButtonLabel.position = CGPoint(x: 0, y: -8) // Vertically center text
        startButtonLabel.zPosition = 1
        startButton.addChild(startButtonLabel)
        
        // Button hover/pulse animation
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
        // Create simple colored circle for now (replace with your boba art later)
        let colors = [
            SKColor.brown.withAlphaComponent(0.6),
            SKColor.orange.withAlphaComponent(0.5),
            SKColor.purple.withAlphaComponent(0.4),
            SKColor.green.withAlphaComponent(0.5)
        ]
        
        let boba = SKSpriteNode(color: colors[index % colors.count], 
                               size: CGSize(width: 20, height: 20))
        
        // Random starting position
        let randomX = CGFloat.random(in: 50...(size.width - 50))
        let randomY = CGFloat.random(in: 100...(size.height - 100))
        boba.position = CGPoint(x: randomX, y: randomY)
        boba.zPosition = 1
        
        // Make it circular
        let circle = SKShapeNode(circleOfRadius: 10)
        circle.fillColor = colors[index % colors.count]
        circle.strokeColor = SKColor.clear
        boba.addChild(circle)
        
        return boba
    }
    
    // MARK: - Initial Animations
    private func setupInitialAnimations() {
        // Animate floating boba
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
        
        // Title entrance animation
        titleLabel.alpha = 0
        titleLabel.setScale(0.5)
        
        let titleEntrance = SKAction.group([
            SKAction.fadeIn(withDuration: 1.0),
            SKAction.scale(to: 1.0, duration: 1.0)
        ])
        titleLabel.run(titleEntrance)
        
        // Button entrance animation (delayed)
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
        
        // Check if start button was touched
        if touchedNode.name == "startButton" || touchedNode.parent?.name == "startButton" {
            handleStartButtonTapped()
        }
    }
    
    private func handleStartButtonTapped() {
        print("🎯 Start button tapped!")
        
        // Button press animation
        let pressDown = SKAction.scale(to: 0.95, duration: 0.1)
        let pressUp = SKAction.scale(to: 1.0, duration: 0.1)
        let buttonPress = SKAction.sequence([pressDown, pressUp])
        
        startButton.run(buttonPress) {
            self.transitionToGame()
        }
    }
    
    private func transitionToGame() {
        print("🚀 Transitioning to game scene...")
        
        // Create transition effect
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let scaleDown = SKAction.scale(to: 0.8, duration: 0.5)
        let exitAnimation = SKAction.group([fadeOut, scaleDown])
        
        run(exitAnimation) {
            // Create and transition to game scene
            let gameScene = GameScene()
            gameScene.scaleMode = .aspectFill
            gameScene.size = self.size
            
            let transition = SKTransition.fade(withDuration: 0.5)
            self.view?.presentScene(gameScene, transition: transition)
        }
    }
}
