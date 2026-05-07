import Foundation
import SpriteKit

private let worldWidth: CGFloat = 2000
private let worldHeight: CGFloat = 1500
private let cellSize: CGFloat = 60
private let gridOrigin = CGPoint(x: -990, y: -750)

private func grid(_ x: Int, _ y: Int) -> CGPoint {
    CGPoint(
        x: gridOrigin.x + CGFloat(x) * cellSize + cellSize / 2,
        y: gridOrigin.y + CGFloat(y) * cellSize + cellSize / 2
    )
}

private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}

private extension SKNode {
    func attach(to parent: SKNode) -> Self {
        parent.addChild(self)
        return self
    }
}

private func makeLabel(
    name: String,
    text: String,
    fontSize: CGFloat,
    position: CGPoint,
    z: CGFloat = 0,
    alpha: CGFloat = 1.0,
    fontName: String = "Arial",
    fontColor: SKColor = .white
) -> SKLabelNode {
    let label = SKLabelNode(text: text)
    label.name = name
    label.fontName = fontName
    label.fontSize = fontSize
    label.fontColor = fontColor
    label.horizontalAlignmentMode = .center
    label.verticalAlignmentMode = .center
    label.position = position
    label.zPosition = z
    label.alpha = alpha
    return label
}

private func makeSprite(
    name: String,
    color: SKColor,
    size: CGSize,
    position: CGPoint,
    z: CGFloat = 0,
    alpha: CGFloat = 1.0
) -> SKSpriteNode {
    let sprite = SKSpriteNode(color: color, size: size)
    sprite.name = name
    sprite.position = position
    sprite.zPosition = z
    sprite.alpha = alpha
    return sprite
}

private func makeAnchor(name: String, position: CGPoint) -> SKNode {
    let node = SKNode()
    node.name = name
    node.position = position
    return node
}

private enum ArchiveKeys {
    static let objectType = "editorObjectType"
    static let rotationState = "editorRotationState"
    static let shapeName = "editorShapeName"
    static let stationType = "editorStationType"
    static let stationIsActive = "editorStationIsActive"
    static let storageType = "editorStorageType"
    static let saveButtonType = "editorSaveButtonType"
    static let drinkCreatorComplete = "editorDrinkCreatorIsComplete"
    static let powerBreakerTripped = "editorPowerBreakerTripped"
    static let windowPhase = "editorWindowPhase"
}

@objc(GameScene)
final class GameScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }
}

@objc(ForestScene)
final class ForestScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }
}

@objc(BigOakTreeScene)
final class BigOakTreeScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }
}

@objc(CaveScene)
final class CaveScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }
}

@objc(HouseScene)
final class HouseScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }
}

@objc(TitleScene)
final class TitleScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }
}

@objc(RotatableObject)
class RotatableObject: SKSpriteNode {
    private let archivedObjectType: String
    private let archivedShapeName: String

    init(objectType: String, color: SKColor, shape: String, size: CGSize = CGSize(width: 60, height: 60)) {
        self.archivedObjectType = objectType
        self.archivedShapeName = shape
        super.init(texture: nil, color: color, size: size)
        setupVisualShape(shape)
    }

    required init?(coder: NSCoder) {
        fatalError("Not supported in generator")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(archivedObjectType, forKey: ArchiveKeys.objectType)
        coder.encode(0, forKey: ArchiveKeys.rotationState)
        coder.encode(archivedShapeName, forKey: ArchiveKeys.shapeName)
    }

    private func setupVisualShape(_ shape: String) {
        switch shape {
        case "arrow":
            makeSprite(name: "direction_indicator", color: .white, size: CGSize(width: 8, height: 20), position: point(0, 15), z: 1, alpha: 0.6).attach(to: self)

        case "L":
            makeSprite(name: "L_vertical", color: .white, size: CGSize(width: 6, height: 30), position: point(-10, 5), z: 1, alpha: 0.6).attach(to: self)
            makeSprite(name: "L_horizontal", color: .white, size: CGSize(width: 20, height: 6), position: point(0, -10), z: 1, alpha: 0.6).attach(to: self)

        case "triangle":
            makeSprite(name: "triangle_indicator", color: .white, size: CGSize(width: 20, height: 20), position: point(0, 8), z: 1, alpha: 0.6).attach(to: self)

        case "station":
            makeSprite(name: "station_center", color: .white, size: CGSize(width: 12, height: 12), position: .zero, z: 1, alpha: 0.8).attach(to: self)
            [
                point(-25, 25), point(25, 25),
                point(-25, -25), point(25, -25),
            ].enumerated().forEach { index, corner in
                makeSprite(name: "station_corner_\(index)", color: .white, size: CGSize(width: 6, height: 6), position: corner, z: 1, alpha: 0.5).attach(to: self)
            }

        case "table":
            makeSprite(name: "table_center", color: .white, size: CGSize(width: 12, height: 12), position: .zero, z: 1, alpha: 0.6).attach(to: self)
            [
                point(-18, 18), point(18, 18),
                point(-18, -18), point(18, -18),
            ].enumerated().forEach { index, corner in
                makeSprite(name: "table_corner_\(index)", color: .white, size: CGSize(width: 6, height: 6), position: corner, z: 1, alpha: 0.45).attach(to: self)
            }

        case "drink":
            makeSprite(name: "drink_lid", color: .white, size: CGSize(width: 16, height: 4), position: point(0, 12), z: 1, alpha: 0.6).attach(to: self)
            makeSprite(name: "drink_straw", color: .white, size: CGSize(width: 2, height: 20), position: point(6, 8), z: 1, alpha: 0.6).attach(to: self)

        default:
            break
        }
    }
}

@objc(IngredientStation)
final class IngredientStation: RotatableObject {
    private let archivedStationType: String

    private static let editorAssetNames: [String: String] = [
        "ice": "scene_station_ice",
    ]

    init(type: String) {
        self.archivedStationType = type
        let color: SKColor
        switch type {
        case "ice":
            color = .cyan
        case "boba":
            color = .black
        case "foam":
            color = SKColor(red: 1.0, green: 0.9, blue: 0.7, alpha: 1.0)
        case "tea":
            color = SKColor(red: 0.6, green: 0.3, blue: 0.1, alpha: 1.0)
        case "lid":
            color = SKColor(red: 0.85, green: 0.85, blue: 0.92, alpha: 1.0)
        case "trash":
            color = SKColor(red: 0.35, green: 0.15, blue: 0.15, alpha: 1.0)
        default:
            color = .gray
        }

        super.init(objectType: "station", color: color, shape: "station", size: CGSize(width: 80, height: 80))
        name = "ingredient_station_\(type)"
        alpha = 0.3

        if let textureName = Self.editorAssetNames[type] {
            let texture = SKTexture(imageNamed: textureName)
            texture.filteringMode = .nearest
            children
                .filter { $0.name?.hasPrefix("station_") == true || $0.name?.hasPrefix("shape_") == true }
                .forEach { $0.removeFromParent() }
            self.texture = texture
            self.color = .white
            self.colorBlendFactor = 0.0
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Not supported in generator")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(archivedStationType, forKey: ArchiveKeys.stationType)
        coder.encode(false, forKey: ArchiveKeys.stationIsActive)
    }
}

@objc(StorageContainer)
final class StorageContainer: RotatableObject {
    private let archivedStorageType: String

    init(type: String) {
        self.archivedStorageType = type

        let color: SKColor
        let labelText: String
        switch type.lowercased() {
        case "fridge":
            color = SKColor(red: 0.75, green: 0.85, blue: 0.90, alpha: 1.0)
            labelText = "FRIDGE"
        default:
            color = SKColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0)
            labelText = "PANTRY"
        }

        super.init(objectType: "furniture", color: color, shape: "rectangle", size: CGSize(width: 80, height: 80))
        name = type

        makeLabel(name: "storage_label",
                  text: labelText,
                  fontSize: 11,
                  position: .zero,
                  z: 2,
                  fontName: "Helvetica-Bold").attach(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("Not supported in generator")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(archivedStorageType.lowercased(), forKey: ArchiveKeys.storageType)
    }
}

@objc(SaveSystemButton)
final class SaveSystemButton: RotatableObject {
    private let archivedButtonType: String

    init(type: String, emoji: String) {
        self.archivedButtonType = type
        super.init(objectType: "furniture", color: SKColor.systemBlue.withAlphaComponent(0.3), shape: "button", size: CGSize(width: 60, height: 60))
        name = type
        makeLabel(name: "emoji_label", text: emoji, fontSize: 32, position: .zero, z: 1).attach(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("Not supported in generator")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(archivedButtonType == "save_journal" ? "saveJournal" : archivedButtonType == "clear_data_button" ? "clearData" : "npcStatus",
                     forKey: ArchiveKeys.saveButtonType)
    }
}

@objc(DrinkCreator)
final class DrinkCreator: SKNode {
    override init() {
        super.init()
        name = "drink_creator"
        let display = RotatableObject(objectType: "completedDrink", color: .clear, shape: "drink", size: CGSize(width: 40, height: 60))
        display.name = "drink_display"
        addChild(display)
    }

    required init?(coder: NSCoder) {
        fatalError("Not supported in generator")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(false, forKey: ArchiveKeys.drinkCreatorComplete)
    }
}

@objc(PowerBreaker)
final class PowerBreaker: SKSpriteNode {
    override init(texture: SKTexture?, color: SKColor, size: CGSize) {
        super.init(texture: texture, color: color, size: size)
    }

    convenience init() {
        self.init(texture: nil, color: .clear, size: CGSize(width: 80, height: 120))
        name = "power_breaker"

        makeSprite(name: "breaker_panel",
                   color: SKColor(red: 0.2, green: 0.4, blue: 0.2, alpha: 1.0),
                   size: CGSize(width: 60, height: 100),
                   position: .zero,
                   z: 0).attach(to: self)
        makeSprite(name: "breaker_switch_handle", color: .white, size: CGSize(width: 40, height: 20), position: point(0, 10), z: 1).attach(to: self)
        makeSprite(name: "breaker_status_light", color: .green, size: CGSize(width: 15, height: 15), position: point(0, 30), z: 1).attach(to: self)
        makeLabel(name: "breaker_main_label", text: "TIME", fontSize: 10, position: point(0, -45), z: 1).attach(to: self)
        makeLabel(name: "breaker_status_label", text: "FLOWING", fontSize: 8, position: point(0, -58), z: 1, fontColor: .green).attach(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("Not supported in generator")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(false, forKey: ArchiveKeys.powerBreakerTripped)
    }
}

@objc(Window)
final class Window: SKSpriteNode {
    override init(texture: SKTexture?, color: SKColor, size: CGSize) {
        super.init(texture: texture, color: color, size: size)
    }

    convenience init() {
        self.init(texture: nil, color: SKColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 1.0), size: CGSize(width: 80, height: 80))
        name = "time_window"
        makeSprite(name: "window_border",
                   color: SKColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0),
                   size: CGSize(width: 84, height: 84),
                   position: .zero,
                   z: -1).attach(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("Not supported in generator")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode("day", forKey: ArchiveKeys.windowPhase)
    }
}

private func registerClassNames() {
    NSKeyedArchiver.setClassName("GameScene", for: GameScene.self)
    NSKeyedArchiver.setClassName("ForestScene", for: ForestScene.self)
    NSKeyedArchiver.setClassName("BigOakTreeScene", for: BigOakTreeScene.self)
    NSKeyedArchiver.setClassName("CaveScene", for: CaveScene.self)
    NSKeyedArchiver.setClassName("HouseScene", for: HouseScene.self)
    NSKeyedArchiver.setClassName("TitleScene", for: TitleScene.self)
    NSKeyedArchiver.setClassName("RotatableObject", for: RotatableObject.self)
    NSKeyedArchiver.setClassName("IngredientStation", for: IngredientStation.self)
    NSKeyedArchiver.setClassName("StorageContainer", for: StorageContainer.self)
    NSKeyedArchiver.setClassName("SaveSystemButton", for: SaveSystemButton.self)
    NSKeyedArchiver.setClassName("DrinkCreator", for: DrinkCreator.self)
    NSKeyedArchiver.setClassName("PowerBreaker", for: PowerBreaker.self)
    NSKeyedArchiver.setClassName("Window", for: Window.self)
}

private func writeScene(_ scene: SKScene, to url: URL) throws {
    let data = try NSKeyedArchiver.archivedData(withRootObject: scene, requiringSecureCoding: false)
    try data.write(to: url)
}

private func repairGeneratedScenes(at urls: [URL]) throws {
    let scriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Tools")
        .appendingPathComponent("RepairSpriteKitSceneEditorMetadata.py")

    guard FileManager.default.fileExists(atPath: scriptURL.path) else {
        throw NSError(
            domain: "GenerateEditorScenes",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing repair script at \(scriptURL.path)"]
        )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [scriptURL.path] + urls.map(\.path)

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "GenerateEditorScenes",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Scene repair failed" : output]
        )
    }

    if !output.isEmpty {
        print(output)
    }
}

private func addButtonBackground(_ node: SKSpriteNode, title: String, fontSize: CGFloat) {
    let border = SKShapeNode(rect: CGRect(x: -node.size.width / 2, y: -node.size.height / 2, width: node.size.width, height: node.size.height),
                             cornerRadius: 10)
    border.fillColor = .clear
    border.strokeColor = SKColor.white.withAlphaComponent(0.7)
    border.lineWidth = 2
    border.name = "\(node.name ?? "button")_border"
    node.addChild(border)

    let label = makeLabel(name: "\(node.name ?? "button")_label",
                          text: title,
                          fontSize: fontSize,
                          position: point(0, -8),
                          z: 1,
                          fontName: "Helvetica-Bold")
    node.addChild(label)
}

private func buildTitleScene() -> TitleScene {
    let scene = TitleScene(size: CGSize(width: 1000, height: 1600))

    makeSprite(name: "background_gradient",
               color: SKColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1.0),
               size: CGSize(width: 1800, height: 2800),
               position: .zero,
               z: -10).attach(to: scene)

    makeLabel(name: "title_label",
              text: "Boba at Dawn",
              fontSize: 48,
              position: point(0, 280),
              z: 10,
              fontName: "Helvetica-Bold").attach(to: scene)

    makeLabel(name: "subtitle_label",
              text: "A Cozy Brewing Adventure",
              fontSize: 20,
              position: point(0, 210),
              z: 10,
              fontName: "Helvetica-Light",
              fontColor: .lightGray).attach(to: scene)

    let startButton = makeSprite(name: "startButton",
                                 color: SKColor(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.9),
                                 size: CGSize(width: 220, height: 64),
                                 position: point(0, -20),
                                 z: 5)
    addButtonBackground(startButton, title: "Start Brewing", fontSize: 24)
    scene.addChild(startButton)

    let hostButton = makeSprite(name: "hostButton",
                                color: SKColor(red: 0.3, green: 0.6, blue: 0.4, alpha: 0.9),
                                size: CGSize(width: 150, height: 54),
                                position: point(-95, -170),
                                z: 5)
    addButtonBackground(hostButton, title: "Host Game", fontSize: 18)
    scene.addChild(hostButton)

    let joinButton = makeSprite(name: "joinButton",
                                color: SKColor(red: 0.4, green: 0.4, blue: 0.7, alpha: 0.9),
                                size: CGSize(width: 150, height: 54),
                                position: point(95, -170),
                                z: 5)
    addButtonBackground(joinButton, title: "Join Game", fontSize: 18)
    scene.addChild(joinButton)

    makeLabel(name: "multiplayer_status_label",
              text: "",
              fontSize: 14,
              position: point(0, -230),
              z: 10,
              fontName: "Helvetica-Light",
              fontColor: .lightGray).attach(to: scene)

    return scene
}

private func buildGameScene() -> GameScene {
    let scene = GameScene(size: CGSize(width: worldWidth, height: worldHeight))

    makeAnchor(name: "character_spawn", position: grid(16, 12)).attach(to: scene)
    makeSprite(name: "shop_floor",
               color: SKColor(red: 0.8, green: 0.7, blue: 0.6, alpha: 1.0),
               size: CGSize(width: worldWidth, height: worldHeight),
               position: .zero,
               z: -10).attach(to: scene)
    makeSprite(name: "shop_floor_bounds",
               color: SKColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 0.6),
               size: CGSize(width: 840, height: 660),
               position: grid(16, 13),
               z: -4).attach(to: scene)

    makeSprite(name: "wall_top", color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: worldWidth, height: 40), position: point(0, 730), z: -3).attach(to: scene)
    makeSprite(name: "wall_bottom", color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: worldWidth, height: 40), position: point(0, -730), z: -3).attach(to: scene)
    makeSprite(name: "wall_left", color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: 40, height: worldHeight), position: point(-980, 0), z: -3).attach(to: scene)
    makeSprite(name: "wall_right", color: SKColor(red: 0.5, green: 0.3, blue: 0.2, alpha: 1.0), size: CGSize(width: 40, height: worldHeight), position: point(980, 0), z: -3).attach(to: scene)

    makeLabel(name: "front_door", text: "🚪", fontSize: 80, position: grid(1, 12), z: 5).attach(to: scene)

    let stations: [(String, Int)] = [
        ("ice", 12),
        ("tea", 14),
        ("boba", 16),
        ("foam", 18),
        ("lid", 20),
        ("trash", 22),
    ]
    for (type, column) in stations {
        let station = IngredientStation(type: type)
        station.position = grid(column, 17)
        station.zPosition = 2
        scene.addChild(station)
    }

    let drinkCreator = DrinkCreator()
    drinkCreator.position = grid(16, 14)
    drinkCreator.zPosition = 3
    scene.addChild(drinkCreator)

    let placedObjects: [(String, String, String, CGPoint)] = [
        ("furniture_arrow", "furniture", "arrow", grid(25, 10)),
        ("furniture_l_shape", "furniture", "L", grid(25, 12)),
        ("furniture_triangle", "drink", "triangle", grid(25, 14)),
        ("furniture_rectangle", "furniture", "rectangle", grid(25, 16)),
    ]

    let objectColors: [String: SKColor] = [
        "arrow": .red,
        "L": .blue,
        "triangle": .green,
        "rectangle": .orange,
    ]

    for (name, type, shape, position) in placedObjects {
        let object = RotatableObject(objectType: type, color: objectColors[shape] ?? .white, shape: shape)
        object.name = name
        object.position = position
        object.zPosition = 1
        scene.addChild(object)
    }

    let tablePositions = [
        grid(12, 8), grid(14, 8), grid(16, 8),
        grid(18, 8), grid(12, 6), grid(14, 6),
        grid(16, 6), grid(18, 6), grid(20, 6),
    ]
    for (index, position) in tablePositions.enumerated() {
        let table = RotatableObject(objectType: "furniture",
                                    color: SKColor(red: 0.4, green: 0.2, blue: 0.1, alpha: 1.0),
                                    shape: "table")
        table.name = "table_\(index + 1)"
        table.position = position
        table.zPosition = 2
        scene.addChild(table)
    }

    let storageContainers: [(String, CGPoint)] = [
        ("Pantry", grid(8, 15)),
        ("Fridge", grid(8, 13)),
    ]
    for (name, position) in storageContainers {
        let container = StorageContainer(type: name)
        container.position = position
        container.zPosition = 2
        scene.addChild(container)
    }

    let breaker = PowerBreaker()
    breaker.position = grid(3, 20)
    breaker.zPosition = 6
    scene.addChild(breaker)

    let window = Window()
    window.position = grid(3, 18)
    window.zPosition = 6
    scene.addChild(window)

    makeLabel(name: "time_label",
              text: "DAY",
              fontSize: 24,
              position: grid(3, 18),
              z: 7,
              fontName: "Arial-Bold",
              fontColor: .black).attach(to: scene)
    makeAnchor(name: "time_control_anchor", position: point(grid(3, 18).x + 80, grid(3, 18).y)).attach(to: scene)

    let saveButtons: [(String, String, CGPoint)] = [
        ("save_journal", "📔", grid(2, 7)),
        ("clear_data_button", "🗑️", grid(4, 7)),
        ("npc_status_tracker", "📈", grid(6, 7)),
    ]
    for (name, emoji, position) in saveButtons {
        let button = SaveSystemButton(type: name, emoji: emoji)
        button.position = position
        button.zPosition = 6
        scene.addChild(button)
    }

    return scene
}

private func buildForestRoom(number: Int, emoji: String) -> SKNode {
    let room = SKNode()
    room.name = "forest_room_\(number)"

    makeLabel(name: "room_identifier", text: emoji, fontSize: 120, position: grid(16, 12), z: 5).attach(to: room)
    makeLabel(name: "left_hint", text: "", fontSize: 40, position: grid(3, 12), z: 3, alpha: 0.3).attach(to: room)
    makeLabel(name: "right_hint", text: "", fontSize: 40, position: grid(29, 12), z: 3, alpha: 0.3).attach(to: room)

    let housePositions = [
        grid(8, 16), grid(24, 16),
        grid(8, 8), grid(24, 8),
    ]
    for (index, position) in housePositions.enumerated() {
        makeLabel(name: "house_\(index + 1)", text: "🏠", fontSize: 35, position: position, z: 3, alpha: 0.7).attach(to: room)
    }

    if number == 1 {
        makeLabel(name: "back_door", text: "🚪", fontSize: 80, position: grid(16, 20), z: 10).attach(to: room)
    }

    if number == 2 {
        makeLabel(name: "cave_entrance", text: "🕳️", fontSize: 100, position: grid(16, 18), z: 10).attach(to: room)
    }

    if number == 4 {
        makeLabel(name: "oak_tree_entrance", text: "🌳", fontSize: 100, position: grid(16, 18), z: 10).attach(to: room)
    }

    if number == 3 || number == 4 {
        let portal = makeLabel(name: "portal", text: "🌀", fontSize: 60, position: grid(16, 5), z: 10)
        makeLabel(name: "portal_hint", text: "", fontSize: 20, position: point(0, -40), z: 1, alpha: 0.5).attach(to: portal)
        room.addChild(portal)
    }

    if (2...4).contains(number) {
        makeAnchor(name: "gnome_transit_left", position: grid(3, 12)).attach(to: room)
        makeAnchor(name: "gnome_transit_right", position: grid(29, 12)).attach(to: room)
    }

    return room
}

private func buildForestScene() -> ForestScene {
    let scene = ForestScene(size: CGSize(width: worldWidth, height: worldHeight))

    makeAnchor(name: "character_spawn", position: grid(16, 12)).attach(to: scene)
    makeSprite(name: "forest_floor",
               color: SKColor(red: 0.15, green: 0.25, blue: 0.15, alpha: 1.0),
               size: CGSize(width: worldWidth, height: worldHeight),
               position: .zero,
               z: -10).attach(to: scene)

    makeSprite(name: "forest_wall_top", color: SKColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0), size: CGSize(width: worldWidth, height: 60), position: point(0, worldHeight / 2 - 30), z: -5).attach(to: scene)
    makeSprite(name: "forest_wall_bottom", color: SKColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0), size: CGSize(width: worldWidth, height: 60), position: point(0, -worldHeight / 2 + 30), z: -5).attach(to: scene)
    makeSprite(name: "forest_wall_left", color: SKColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0), size: CGSize(width: 60, height: worldHeight), position: point(-worldWidth / 2 + 30, 0), z: -5).attach(to: scene)
    makeSprite(name: "forest_wall_right", color: SKColor(red: 0.1, green: 0.15, blue: 0.1, alpha: 1.0), size: CGSize(width: 60, height: worldHeight), position: point(worldWidth / 2 - 30, 0), z: -5).attach(to: scene)

    makeSprite(name: "left_mist", color: SKColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1.0), size: CGSize(width: 133, height: worldHeight), position: point(-worldWidth / 2 + 67, 0), z: -8).attach(to: scene)
    makeSprite(name: "right_mist", color: SKColor(red: 0.25, green: 0.35, blue: 0.25, alpha: 1.0), size: CGSize(width: 133, height: worldHeight), position: point(worldWidth / 2 - 67, 0), z: -8).attach(to: scene)

    let roomEmojis = ["", "🍄", "⛰️", "⭐", "💎", "🌳"]
    for roomNumber in 1...5 {
        let room = buildForestRoom(number: roomNumber, emoji: roomEmojis[roomNumber])
        room.isHidden = roomNumber != 1
        scene.addChild(room)
    }

    return scene
}

private func addDecorCard(name: String, text: String, color: SKColor, size: CGSize, position: CGPoint, z: CGFloat) -> SKSpriteNode {
    let node = makeSprite(name: name, color: color, size: size, position: position, z: z)
    let label = makeLabel(name: "\(name)_emoji", text: text, fontSize: min(size.width, size.height) * 0.45, position: .zero, z: 1)
    node.addChild(label)
    return node
}

private func buildCaveRoomLabel(title: String) -> SKLabelNode {
    makeLabel(
        name: "cave_room_label",
        text: title,
        fontSize: 40,
        position: point(0, 600),
        z: 4,
        fontName: "Arial",
        fontColor: .white
    )
}

private func buildCaveTriggerLabel(name: String, text: String, position: CGPoint) -> SKLabelNode {
    makeLabel(
        name: name,
        text: text,
        fontSize: 48,
        position: position,
        z: 3,
        fontName: "Arial",
        fontColor: .white
    )
}

private func buildCaveEntranceRoom() -> SKNode {
    let room = SKNode()
    room.name = "cave_room_entrance"

    buildCaveRoomLabel(title: "Entrance").attach(to: room)
    buildCaveTriggerLabel(name: "cave_stairs_down", text: "⬇️", position: point(0, 420)).attach(to: room)
    buildCaveTriggerLabel(name: "cave_exit_door", text: "🚪", position: point(0, -420)).attach(to: room)
    makeAnchor(name: "spawn_from_below", position: point(0, 380)).attach(to: room)
    makeAnchor(name: "spawn_from_forest", position: point(0, -380)).attach(to: room)
    makeAnchor(name: "mine_machine_anchor", position: point(-120, 0)).attach(to: room)
    makeAnchor(name: "waste_bin_anchor", position: point(120, 0)).attach(to: room)

    return room
}

private func buildMiddleCaveRoom(containerName: String, title: String) -> SKNode {
    let room = SKNode()
    room.name = containerName

    buildCaveRoomLabel(title: title).attach(to: room)
    buildCaveTriggerLabel(name: "cave_stairs_up", text: "⬆️", position: point(0, 420)).attach(to: room)
    buildCaveTriggerLabel(name: "cave_stairs_down", text: "⬇️", position: point(0, -420)).attach(to: room)
    makeAnchor(name: "spawn_from_above", position: point(0, 380)).attach(to: room)
    makeAnchor(name: "spawn_from_below", position: point(0, -380)).attach(to: room)

    return room
}

private func buildDeepestCaveRoom() -> SKNode {
    let room = SKNode()
    room.name = "cave_room_floor_3"

    buildCaveRoomLabel(title: "Floor 3").attach(to: room)
    buildCaveTriggerLabel(name: "cave_stairs_up", text: "⬆️", position: point(0, 420)).attach(to: room)
    makeAnchor(name: "spawn_from_above", position: point(0, 380)).attach(to: room)

    return room
}

private func buildCaveScene() -> CaveScene {
    let scene = CaveScene(size: CGSize(width: worldWidth, height: worldHeight))

    makeSprite(name: "cave_floor",
               color: SKColor(red: 0.12, green: 0.11, blue: 0.14, alpha: 1.0),
               size: CGSize(width: worldWidth, height: worldHeight),
               position: .zero,
               z: -10).attach(to: scene)
    makeSprite(name: "cave_wall_top",
               color: SKColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0),
               size: CGSize(width: worldWidth, height: 60),
               position: point(0, worldHeight / 2 - 30),
               z: -5).attach(to: scene)
    makeSprite(name: "cave_wall_bottom",
               color: SKColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0),
               size: CGSize(width: worldWidth, height: 60),
               position: point(0, -worldHeight / 2 + 30),
               z: -5).attach(to: scene)
    makeSprite(name: "cave_wall_left",
               color: SKColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0),
               size: CGSize(width: 60, height: worldHeight),
               position: point(-worldWidth / 2 + 30, 0),
               z: -5).attach(to: scene)
    makeSprite(name: "cave_wall_right",
               color: SKColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0),
               size: CGSize(width: 60, height: worldHeight),
               position: point(worldWidth / 2 - 30, 0),
               z: -5).attach(to: scene)

    makeAnchor(name: "character_spawn", position: point(0, -300)).attach(to: scene)

    let rooms = [
        buildCaveEntranceRoom(),
        buildMiddleCaveRoom(containerName: "cave_room_floor_1", title: "Floor 1"),
        buildMiddleCaveRoom(containerName: "cave_room_floor_2", title: "Floor 2"),
        buildDeepestCaveRoom(),
    ]

    for (index, room) in rooms.enumerated() {
        room.isHidden = index != 0
        scene.addChild(room)
    }

    return scene
}

private func buildHouseScene() -> HouseScene {
    let scene = HouseScene(size: CGSize(width: worldWidth, height: worldHeight))

    makeAnchor(name: "character_spawn", position: grid(16, 7)).attach(to: scene)
    makeSprite(name: "house_floor",
               color: SKColor(red: 0.32, green: 0.24, blue: 0.19, alpha: 1.0),
               size: CGSize(width: worldWidth, height: worldHeight),
               position: .zero,
               z: -10).attach(to: scene)
    makeSprite(name: "house_wall_top",
               color: SKColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 1.0),
               size: CGSize(width: worldWidth, height: 60),
               position: point(0, worldHeight / 2 - 30),
               z: -5).attach(to: scene)
    makeSprite(name: "house_wall_bottom",
               color: SKColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 1.0),
               size: CGSize(width: worldWidth, height: 60),
               position: point(0, -worldHeight / 2 + 30),
               z: -5).attach(to: scene)
    makeSprite(name: "house_wall_left",
               color: SKColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 1.0),
               size: CGSize(width: 60, height: worldHeight),
               position: point(-worldWidth / 2 + 30, 0),
               z: -5).attach(to: scene)
    makeSprite(name: "house_wall_right",
               color: SKColor(red: 0.18, green: 0.13, blue: 0.10, alpha: 1.0),
               size: CGSize(width: 60, height: worldHeight),
               position: point(worldWidth / 2 - 30, 0),
               z: -5).attach(to: scene)

    makeLabel(name: "house_room_label",
              text: "Empty House",
              fontSize: 34,
              position: grid(16, 22),
              z: 4,
              alpha: 0.7,
              fontName: "Helvetica-Bold").attach(to: scene)
    addDecorCard(name: "house_bed",
                 text: "🛏️",
                 color: SKColor(red: 0.73, green: 0.63, blue: 0.48, alpha: 1.0),
                 size: CGSize(width: 120, height: 90),
                 position: grid(10, 14),
                 z: 2).attach(to: scene)
    addDecorCard(name: "house_table",
                 text: "🪑",
                 color: SKColor(red: 0.54, green: 0.40, blue: 0.27, alpha: 1.0),
                 size: CGSize(width: 110, height: 80),
                 position: grid(22, 12),
                 z: 2).attach(to: scene)
    addDecorCard(name: "house_exit_door",
                 text: "🚪",
                 color: SKColor(red: 0.28, green: 0.17, blue: 0.10, alpha: 1.0),
                 size: CGSize(width: 90, height: 110),
                 position: grid(16, 5),
                 z: 3).attach(to: scene)
    makeAnchor(name: "house_resident_anchor", position: grid(16, 12)).attach(to: scene)

    return scene
}

private func buildOakLobby() -> SKNode {
    let room = SKNode()
    room.name = "oak_room_lobby"

    makeLabel(name: "oak_room_label", text: "🏡", fontSize: 80, position: grid(16, 22), z: 4, alpha: 0.45).attach(to: room)
    addDecorCard(name: "oak_lobby_fireplace", text: "🔥", color: SKColor(red: 0.35, green: 0.10, blue: 0.05, alpha: 1.0), size: CGSize(width: 120, height: 90), position: grid(7, 12), z: 2).attach(to: room)
    addDecorCard(name: "oak_lobby_kitchen", text: "🍳", color: SKColor(red: 0.70, green: 0.55, blue: 0.35, alpha: 1.0), size: CGSize(width: 120, height: 90), position: grid(25, 12), z: 2).attach(to: room)
    addDecorCard(name: "oak_lobby_couch_left", text: "🛋️", color: SKColor(red: 0.45, green: 0.25, blue: 0.15, alpha: 1.0), size: CGSize(width: 80, height: 80), position: grid(13, 9), z: 2).attach(to: room)
    addDecorCard(name: "oak_lobby_couch_right", text: "🛋️", color: SKColor(red: 0.45, green: 0.25, blue: 0.15, alpha: 1.0), size: CGSize(width: 80, height: 80), position: grid(19, 9), z: 2).attach(to: room)

    [
        (name: "oak_stairs_left", position: grid(10, 19)),
        (name: "oak_stairs_middle", position: grid(16, 19)),
        (name: "oak_stairs_right", position: grid(22, 19)),
    ].forEach { entry in
        addDecorCard(name: entry.name, text: "⬆️", color: SKColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0), size: CGSize(width: 80, height: 80), position: entry.position, z: 3).attach(to: room)
    }

    let treasuryStair = addDecorCard(
        name: "oak_stairs_treasury",
        text: "💎",
        color: SKColor(red: 0.35, green: 0.26, blue: 0.12, alpha: 1.0),
        size: CGSize(width: 80, height: 80),
        position: grid(6, 12),
        z: 3
    )
    makeAnchor(name: "spawn_from_treasury", position: .zero).attach(to: treasuryStair)
    treasuryStair.attach(to: room)

    addDecorCard(name: "oak_exit_door", text: "🚪", color: SKColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1.0), size: CGSize(width: 80, height: 100), position: grid(16, 5), z: 3).attach(to: room)

    makeAnchor(name: "gnome_anchor_greeter", position: grid(16, 13)).attach(to: room)
    makeAnchor(name: "gnome_anchor_fireplace_keeper", position: grid(9, 11)).attach(to: room)
    makeAnchor(name: "gnome_anchor_kitchen", position: grid(23, 11)).attach(to: room)
    makeAnchor(name: "spawn_from_left_bedroom", position: grid(10, 17)).attach(to: room)
    makeAnchor(name: "spawn_from_middle_bedroom", position: grid(16, 17)).attach(to: room)
    makeAnchor(name: "spawn_from_right_bedroom", position: grid(22, 17)).attach(to: room)
    makeAnchor(name: "spawn_from_forest", position: grid(16, 7)).attach(to: room)

    return room
}

private func buildOakBedroom(containerName: String) -> SKNode {
    let room = SKNode()
    room.name = containerName

    makeLabel(name: "oak_room_label", text: "🛏️", fontSize: 80, position: grid(16, 22), z: 4, alpha: 0.45).attach(to: room)
    addDecorCard(name: "oak_bedroom_bed", text: "🛏️", color: SKColor(red: 0.85, green: 0.75, blue: 0.60, alpha: 1.0), size: CGSize(width: 120, height: 90), position: grid(14, 15), z: 2).attach(to: room)
    addDecorCard(name: "oak_bedroom_nightstand", text: "🕯️", color: SKColor(red: 0.40, green: 0.25, blue: 0.15, alpha: 1.0), size: CGSize(width: 60, height: 60), position: grid(18, 15), z: 2).attach(to: room)
    addDecorCard(name: "oak_bedroom_window", text: "🪟", color: SKColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0), size: CGSize(width: 80, height: 80), position: grid(16, 21), z: 2).attach(to: room)
    addDecorCard(name: "oak_stairs_down", text: "⬇️", color: SKColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0), size: CGSize(width: 80, height: 80), position: grid(16, 5), z: 3).attach(to: room)

    makeAnchor(name: "gnome_anchor_bedroom", position: grid(16, 10)).attach(to: room)
    makeAnchor(name: "spawn_from_lobby", position: grid(16, 7)).attach(to: room)
    return room
}

private func buildOakTreasury() -> SKNode {
    let room = SKNode()
    room.name = "oak_room_treasury"

    makeLabel(name: "oak_room_label", text: "💎", fontSize: 80, position: grid(16, 22), z: 4, alpha: 0.45).attach(to: room)

    let stairsDown = addDecorCard(
        name: "oak_stairs_down",
        text: "⬇️",
        color: SKColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1.0),
        size: CGSize(width: 80, height: 80),
        position: grid(16, 5),
        z: 3
    )
    makeAnchor(name: "spawn_from_lobby", position: .zero).attach(to: stairsDown)
    stairsDown.attach(to: room)

    makeAnchor(name: "treasury_pile_anchor", position: grid(16, 12)).attach(to: room)
    return room
}

private func buildBigOakTreeScene() -> BigOakTreeScene {
    let scene = BigOakTreeScene(size: CGSize(width: worldWidth, height: worldHeight))

    makeAnchor(name: "character_spawn", position: grid(16, 7)).attach(to: scene)
    makeSprite(name: "oak_floor",
               color: SKColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1.0),
               size: CGSize(width: worldWidth, height: worldHeight),
               position: .zero,
               z: -10).attach(to: scene)
    makeSprite(name: "oak_wall_top", color: SKColor(red: 0.15, green: 0.09, blue: 0.06, alpha: 1.0), size: CGSize(width: worldWidth, height: 60), position: point(0, worldHeight / 2 - 30), z: -5).attach(to: scene)
    makeSprite(name: "oak_wall_bottom", color: SKColor(red: 0.15, green: 0.09, blue: 0.06, alpha: 1.0), size: CGSize(width: worldWidth, height: 60), position: point(0, -worldHeight / 2 + 30), z: -5).attach(to: scene)
    makeSprite(name: "oak_wall_left", color: SKColor(red: 0.15, green: 0.09, blue: 0.06, alpha: 1.0), size: CGSize(width: 60, height: worldHeight), position: point(-worldWidth / 2 + 30, 0), z: -5).attach(to: scene)
    makeSprite(name: "oak_wall_right", color: SKColor(red: 0.15, green: 0.09, blue: 0.06, alpha: 1.0), size: CGSize(width: 60, height: worldHeight), position: point(worldWidth / 2 - 30, 0), z: -5).attach(to: scene)

    let lobby = buildOakLobby()
    scene.addChild(lobby)

    let leftBedroom = buildOakBedroom(containerName: "oak_room_left_bedroom")
    leftBedroom.isHidden = true
    scene.addChild(leftBedroom)

    let middleBedroom = buildOakBedroom(containerName: "oak_room_middle_bedroom")
    middleBedroom.isHidden = true
    scene.addChild(middleBedroom)

    let rightBedroom = buildOakBedroom(containerName: "oak_room_right_bedroom")
    rightBedroom.isHidden = true
    scene.addChild(rightBedroom)

    let treasury = buildOakTreasury()
    treasury.isHidden = true
    scene.addChild(treasury)

    return scene
}

private func outputURL(for fileName: String) -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("BobaAtDawn")
        .appendingPathComponent(fileName)
}

private func shouldGenerate(_ fileName: String, requested: Set<String>) -> Bool {
    guard !requested.isEmpty else { return true }

    let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    return requested.contains(fileName) || requested.contains(stem)
}

registerClassNames()

do {
    let requestedScenes = Set(CommandLine.arguments.dropFirst())
    let sceneDefinitions: [(fileName: String, build: () -> SKScene)] = [
        ("TitleScene.sks", buildTitleScene),
        ("GameScene.sks", buildGameScene),
        ("ForestScene.sks", buildForestScene),
        ("BigOakTreeScene.sks", buildBigOakTreeScene),
        ("CaveScene.sks", buildCaveScene),
        ("HouseScene.sks", buildHouseScene),
    ]

    var sceneURLs: [URL] = []
    for definition in sceneDefinitions where shouldGenerate(definition.fileName, requested: requestedScenes) {
        let url = outputURL(for: definition.fileName)
        try writeScene(definition.build(), to: url)
        sceneURLs.append(url)
    }

    guard !sceneURLs.isEmpty else {
        throw NSError(
            domain: "GenerateEditorScenes",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "No matching scenes requested: \(requestedScenes.sorted())"]
        )
    }

    try repairGeneratedScenes(at: sceneURLs)
    print("Generated editor-first scenes successfully.")
} catch {
    fputs("Failed to generate scenes: \(error)\n", stderr)
    exit(1)
}
