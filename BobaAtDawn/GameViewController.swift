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
        
        // Get the SKView first
        guard let skView = self.view as? SKView else {
            print("❌ ERROR: View is not an SKView")
            return
        }
        
        // START WITH TITLE SCENE instead of going directly to game - FIXED: Pass size parameter
        let titleScene = TitleScene(size: skView.bounds.size)
        
        // Set the scale mode to scale to fit the window
        titleScene.scaleMode = .aspectFill
        
        // Present the title scene
        skView.presentScene(titleScene)
        
        skView.ignoresSiblingOrder = true
        
        // Show debug info during development
        skView.showsFPS = true
        skView.showsNodeCount = true
        
        print("📱 GameViewController loaded with view bounds: \(skView.bounds.size)")
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
