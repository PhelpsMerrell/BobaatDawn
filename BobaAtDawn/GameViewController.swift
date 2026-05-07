//
//  GameViewController.swift
//  BobaAtDawn
//
//  Created by Phelps Merrell on 8/18/25.
//

import UIKit
import SpriteKit
import GameplayKit
import GameKit

class GameViewController: UIViewController {
    private var hasPresentedInitialScene = false

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Get the SKView first
        guard let skView = self.view as? SKView else {
            print("❌ ERROR: View is not an SKView")
            return
        }

        skView.ignoresSiblingOrder = true
        
        // Show debug info during development
        skView.showsFPS = true
        skView.showsNodeCount = true
        
        print("📱 GameViewController loaded with view bounds: \(skView.bounds.size)")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        presentInitialSceneIfNeeded()
    }

    private func presentInitialSceneIfNeeded() {
        guard !hasPresentedInitialScene else { return }
        guard let skView = view as? SKView else { return }

        let viewSize = skView.bounds.size
        guard viewSize.width > 0 && viewSize.height > 0 else {
            print("⏳ Waiting for SKView to finish layout before presenting TitleScene")
            return
        }

        let titleScene = SceneFactory.loadTitleScene(size: viewSize)
        skView.presentScene(titleScene)
        hasPresentedInitialScene = true

        print("🎬 Presented TitleScene with laid out size: \(viewSize)")
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
