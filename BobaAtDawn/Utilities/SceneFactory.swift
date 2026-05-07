//
//  SceneFactory.swift
//  BobaAtDawn
//
//  Centralized .sks scene loading for editor-first workflows.
//

import SpriteKit

enum SceneFactory {
    static func loadGameScene(size: CGSize) -> GameScene {
        loadScene(named: "GameScene", as: GameScene.self, size: size)
    }

    static func loadForestScene(size: CGSize) -> ForestScene {
        loadScene(named: "ForestScene", as: ForestScene.self, size: size)
    }

    static func loadTitleScene(size: CGSize) -> TitleScene {
        loadScene(named: "TitleScene", as: TitleScene.self, size: size)
    }

    static func loadBigOakTreeScene(size: CGSize) -> BigOakTreeScene {
        loadScene(named: "BigOakTreeScene", as: BigOakTreeScene.self, size: size)
    }

    static func loadCaveScene(size: CGSize) -> CaveScene {
        loadScene(named: "CaveScene", as: CaveScene.self, size: size)
    }

    static func loadHouseScene(size: CGSize) -> HouseScene {
        loadScene(named: "HouseScene", as: HouseScene.self, size: size)
    }

    static func loadScene<T: SKScene>(named name: String, as type: T.Type, size: CGSize) -> T {
        guard let scene = SKScene(fileNamed: name) as? T else {
            fatalError("Failed to load \(name).sks as \(T.self)")
        }
        scene.size = size
        scene.scaleMode = .aspectFill
        return scene
    }
}
