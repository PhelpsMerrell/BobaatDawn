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
        
        // START WITH TITLE SCREEN instead of going directly to game
        let titleScene = TitleScene()
        
        // Set the scale mode to scale to fit the window
        titleScene.scaleMode = .aspectFill
        
        // Get the SKView and present the title scene
        if let view = self.view as? SKView {
            // Set scene size to match view
            titleScene.size = view.bounds.size
            
            view.presentScene(titleScene)
            
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
