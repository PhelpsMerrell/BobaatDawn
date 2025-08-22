//
//  AnimationService Usage Examples
//  BobaAtDawn
//
//  Demonstrates how to replace scattered animations with centralized AnimationService
//

import SpriteKit

// MARK: - Before and After Examples

// BEFORE: Scattered animation code in GameScene.swift
/*
let pulseAction = SKAction.sequence([
    SKAction.scale(to: 1.05, duration: 0.1),
    SKAction.scale(to: 1.0, duration: 0.1)
])
stationNode.run(pulseAction)
*/

// AFTER: Using AnimationService
/*
let pulseAction = animationService.stationInteractionPulse(stationNode)
animationService.run(pulseAction, on: stationNode, withKey: "stationInteraction", completion: nil)
*/


// BEFORE: Character floating animation in Character.swift
/*
let floatAction = SKAction.repeatForever(
    SKAction.sequence([
        SKAction.moveBy(x: 0, y: GameConfig.Character.floatDistance, duration: GameConfig.Character.floatDuration),
        SKAction.moveBy(x: 0, y: -GameConfig.Character.floatDistance, duration: GameConfig.Character.floatDuration)
    ])
)
item.run(floatAction, withKey: "floating")
*/

// AFTER: Using AnimationService
/*
let floatAction = animationService.carriedItemFloat(item)
animationService.run(floatAction, on: item, withKey: "carriedFloat", completion: nil)
*/


// BEFORE: NPC happy animation in NPC.swift
/*
let shimmer = SKAction.repeatForever(
    SKAction.sequence([
        SKAction.scale(to: 1.15, duration: 0.25),
        SKAction.scale(to: 1.0, duration: 0.25)
    ])
)
npc.run(shimmer, withKey: "happy_shimmer")

let shake = SKAction.repeatForever(
    SKAction.sequence([
        SKAction.moveBy(x: -3, y: 0, duration: 0.1),
        SKAction.moveBy(x: 6, y: 0, duration: 0.1),
        SKAction.moveBy(x: -6, y: 0, duration: 0.1),
        SKAction.moveBy(x: 3, y: 0, duration: 0.1)
    ])
)
npc.run(shake, withKey: "happy_shake")
*/

// AFTER: Using AnimationService
/*
let happyAnimations = animationService.npcHappyCelebration(npc)
for (index, action) in happyAnimations.enumerated() {
    animationService.run(action, on: npc, withKey: "npcHappy_\(index)", completion: nil)
}
*/


// MARK: - Usage Examples in Different Contexts

class AnimationServiceUsageExamples {
    private let animationService: AnimationService
    
    init(animationService: AnimationService) {
        self.animationService = animationService
    }
    
    // EXAMPLE 1: Simple pulse on station interaction
    func demonstrateStationPulse(station: SKNode) {
        let pulseAction = animationService.stationInteractionPulse(station)
        animationService.run(pulseAction, on: station, withKey: "stationInteraction", completion: nil)
    }
    
    // EXAMPLE 2: Custom animation with configuration
    func demonstrateCustomPulse(node: SKNode) {
        let config = AnimationConfig(
            duration: 0.5,
            easing: .easeInOut,
            repeatCount: 3,
            autoreverses: true
        )
        
        let pulseAction = animationService.pulse(node, scale: 1.3, config: config)
        animationService.run(pulseAction, on: node, withKey: "custom_pulse") {
            print("Custom pulse animation completed!")
        }
    }
    
    // EXAMPLE 3: Sequence of animations
    func demonstrateAnimationSequence(node: SKNode) {
        let fadeOut = animationService.fade(node, to: 0.0, config: AnimationConfig(duration: 0.3))
        let scaleUp = animationService.scale(node, to: 1.5, config: AnimationConfig(duration: 0.3))
        let fadeIn = animationService.fade(node, to: 1.0, config: AnimationConfig(duration: 0.3))
        
        let sequenceAction = animationService.sequence([fadeOut, scaleUp, fadeIn]) {
            print("Animation sequence completed!")
        }
        
        animationService.run(sequenceAction, on: node, withKey: "demo_sequence", completion: nil)
    }
    
    // EXAMPLE 4: Parallel animations
    func demonstrateParallelAnimations(node: SKNode) {
        let pulse = animationService.pulse(node, scale: 1.2, config: AnimationConfig(duration: 0.4))
        let float = animationService.float(node, distance: 10, config: AnimationConfig(duration: 0.4))
        
        let parallelAction = animationService.parallel([pulse, float])
        animationService.run(parallelAction, on: node, withKey: "parallel_demo", completion: nil)
    }
    
    // EXAMPLE 5: Entrance animation for new NPCs
    func demonstrateNPCEntrance(npc: SKNode) {
        let entranceAction = animationService.npcEntrance(npc)
        animationService.run(entranceAction, on: npc, withKey: "entrance") {
            print("NPC has fully entered the scene!")
        }
    }
    
    // EXAMPLE 6: Managing animations
    func demonstrateAnimationManagement(node: SKNode) {
        // Start floating
        let floatAction = animationService.carriedItemFloat(node)
        animationService.run(floatAction, on: node, withKey: "carriedFloat", completion: nil)
        
        // Check if animation is running
        if animationService.hasAnimation(node, withKey: "carriedFloat") {
            print("Node is currently floating")
        }
        
        // Stop specific animation after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.animationService.stopAnimation(node, withKey: "carriedFloat")
            print("Stopped floating animation")
        }
    }
    
    // EXAMPLE 7: Forest transition effect
    func demonstrateForestTransition(sceneNode: SKNode) {
        // Fade out current scene
        let fadeOutAction = animationService.forestRoomTransition(sceneNode, fadeOut: true) {
            print("Scene faded out, switching rooms...")
            
            // After transition logic here...
            
            // Fade back in
            let fadeInAction = self.animationService.forestRoomTransition(sceneNode, fadeOut: false) {
                print("Scene transition complete!")
            }
            
            self.animationService.run(fadeInAction, on: sceneNode, withKey: "fade_in", completion: nil)
        }
        
        animationService.run(fadeOutAction, on: sceneNode, withKey: "fade_out", completion: nil)
    }
}

// MARK: - Configuration Examples

/*
 // Basic configuration
 let quickConfig = AnimationConfig(duration: 0.15, easing: .easeOut)
 
 // Repeating animation
 let loopingConfig = AnimationConfig(
     duration: 1.0,
     easing: .easeInOut,
     repeatCount: -1,  // Forever
     autoreverses: true
 )
 
 // Finite repeats
 let bounceConfig = AnimationConfig(
     duration: 0.2,
     easing: .easeOut,
     repeatCount: 3,
     autoreverses: true
 )
*/

// MARK: - Benefits of AnimationService

/*
 ✅ CONSISTENCY: All animations use the same timing and easing from GameConfig
 ✅ REUSABILITY: Common patterns like pulse, float, shimmer are predefined
 ✅ MAINTAINABILITY: Animation logic is centralized in one service
 ✅ CONFIGURATION-DRIVEN: Easy to adjust timing globally through ConfigurationService
 ✅ CLEAN INTERFACES: Simple method calls replace complex SKAction sequences
 ✅ TESTING: Animation logic can be unit tested in isolation
 ✅ PERFORMANCE: Consistent timing reduces frame drops from inconsistent animations
*/
