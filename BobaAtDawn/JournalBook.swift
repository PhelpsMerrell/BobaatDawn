//
//  JournalBook.swift
//  BobaAtDawn
//
//  In-shop book that opens to display past daily chronicles. Long-press
//  to open the JournalBookOverlay (parchment two-page spread with
//  prev/next navigation).
//
//  EDITOR SETUP
//  ------------
//  1. In GameScene.sks, add a Color Sprite node.
//  2. Set Custom Class to "JournalBook".
//  3. Set the node name to "journal_book" (lowercase, exact).
//  4. Place it on the shop floor wherever feels right — somewhere on
//     the counter or a nearby table works.
//  5. Add it to GameScene.swift's editor-name lookup (see GameScene
//     change for `editorJournalBookName`).
//
//  This is a non-carriable RotatableObject: it stays put, has a small
//  label child, and the long-press handler routes to GameScene which
//  pops the overlay.
//

import SpriteKit

@objc(JournalBook)
class JournalBook: RotatableObject {

    /// Shown above the book — keeps it findable in a busy shop.
    private var nameLabel: SKLabelNode?

    // MARK: - Init (code-created, mostly for tests)

    init() {
        super.init(
            type: .furniture,
            color: SKColor(red: 0.42, green: 0.20, blue: 0.10, alpha: 1.0),
            shape: "rectangle"
        )
        self.name = "journal_book"
        self.size = CGSize(width: 70, height: 80)
        setupLabel()
    }

    // MARK: - Init (editor-loaded via .sks)

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        // If editor didn't supply a label, add one. If it did, just keep it.
        nameLabel = children.compactMap { $0 as? SKLabelNode }.first
        if nameLabel == nil {
            setupLabel()
        }
    }

    private func setupLabel() {
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = "📖"
        label.fontSize = 28
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        label.zPosition = 2
        label.name = "journal_book_label"
        addChild(label)
        nameLabel = label
    }

    // NOTE: We do NOT override `canBeCarried` because `RotatableObject`
    // doesn't expose it as `open`. Instead, GameScene's long-press
    // handler has an explicit `as? JournalBook` branch that runs BEFORE
    // the carry fallback, mirroring how StorageContainer is handled.
}
