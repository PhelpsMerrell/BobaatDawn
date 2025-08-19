//
//  GameViewController.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create our game scene directly
        let scene = GameScene()
        
        // Set the scale mode to scale to fit the window
        scene.scaleMode = .aspectFill
        
        // Get the SKView and present the scene
        if let view = self.view as? SKView {
            // Set scene size to match view
            scene.size = view.bounds.size
            
            view.presentScene(scene)
            
            view.ignoresSiblingOrder = true
            
            // Show debug info during development
            view.showsFPS = true
            view.showsNodeCount = true
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
