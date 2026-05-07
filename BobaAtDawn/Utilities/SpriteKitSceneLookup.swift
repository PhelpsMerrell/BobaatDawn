//
//  SpriteKitSceneLookup.swift
//  BobaAtDawn
//
//  Shared helpers for loading named nodes from .sks scenes.
//

import SpriteKit

extension SKNode {
    func sceneNode<T: SKNode>(named name: String, as type: T.Type = T.self) -> T? {
        childNode(withName: "//\(name)") as? T
    }

    func requiredSceneNode<T: SKNode>(named name: String, as type: T.Type = T.self) -> T {
        guard let node = sceneNode(named: name, as: type) else {
            fatalError("Missing required scene node named '\(name)' of type \(T.self)")
        }
        return node
    }

    func namedChild<T: SKNode>(_ name: String, as type: T.Type = T.self) -> T? {
        childNode(withName: name) as? T
    }

    func firstNamedAncestor(matching names: Set<String>) -> SKNode? {
        var current: SKNode? = self
        while let node = current {
            if let name = node.name, names.contains(name) {
                return node
            }
            current = node.parent
        }
        return nil
    }

    func positionInSceneCoordinates() -> CGPoint {
        guard let parent else { return position }
        if let scene {
            return parent.convert(position, to: scene)
        }

        // If the node is not attached to an SKScene yet, walk up to the
        // highest available ancestor so nested editor nodes still resolve to a
        // stable world-space position during setup.
        var root: SKNode = parent
        while let nextParent = root.parent {
            root = nextParent
        }
        return parent.convert(position, to: root)
    }
}
