//
//  JournalBookOverlay.swift
//  BobaAtDawn
//
//  Camera-pinned overlay that shows the daily chronicle history as
//  flippable book pages. Mirrors NPCDebugMenu's parenting pattern:
//  parented to the scene (so aspectFill + camera scale apply normally)
//  with a per-frame "follow camera" action so it stays anchored to the
//  viewport.
//
//  Two-page spread on landscape, single-page stacked layout on portrait.
//  Long-press the page edges (or the < / > buttons) to flip.
//

import SpriteKit

final class JournalBookOverlay: SKNode {

    // MARK: - Tunables

    private static let parchmentColor = SKColor(red: 0.95, green: 0.88, blue: 0.74, alpha: 1.0)
    private static let inkColor       = SKColor(red: 0.18, green: 0.10, blue: 0.06, alpha: 1.0)
    private static let dimInkColor    = SKColor(red: 0.42, green: 0.30, blue: 0.20, alpha: 1.0)
    private static let backdropColor  = SKColor(red: 0.06, green: 0.04, blue: 0.03, alpha: 0.78)
    private static let headerFont     = "Palatino-Bold"
    private static let bodyFont       = "Palatino"
    private static let bodyItalic     = "Palatino-Italic"

    // MARK: - State

    /// All loaded summaries, ascending by day.
    private var summaries: [DailySummary] = []
    /// Index of the current spread's left page in `summaries`. The right
    /// page is `currentLeftIndex + 1` if it exists. -1 means no pages
    /// loaded yet (empty book).
    private var currentLeftIndex: Int = -1

    /// Camera the overlay should pin to. Stored so we can re-anchor on
    /// the very first frame even if the action timing is off.
    private weak var pinnedCamera: SKCameraNode?

    // MARK: - Layout (computed each open)
    private let visibleSize: CGSize
    private var bookSize: CGSize = .zero
    private var pageSize: CGSize = .zero
    private var isPortrait: Bool { visibleSize.width < visibleSize.height * 0.85 }

    // MARK: - Children
    private var backdrop: SKSpriteNode!
    private var bookFrame: SKSpriteNode!
    private var leftPage: SKSpriteNode!
    private var rightPage: SKSpriteNode!
    private var leftPageContent: SKNode!
    private var rightPageContent: SKNode!
    private var prevButton: SKLabelNode!
    private var nextButton: SKLabelNode!
    private var closeButton: SKLabelNode!
    private var dayCounter: SKLabelNode!

    // MARK: - Init

    init(visibleSize: CGSize, camera: SKCameraNode?) {
        self.visibleSize = visibleSize
        self.pinnedCamera = camera
        super.init()
        self.name = "journal_book_overlay"
        self.zPosition = 9_500   // above gameplay, below dialogue (10_000)

        loadSummaries()
        buildHierarchy()
        renderCurrentSpread()
        runPinFollowAction()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Static Helper

    /// Find an existing overlay (if any) parented to `host`. Used to
    /// dismiss-on-second-tap behavior.
    static func existing(in host: SKNode) -> JournalBookOverlay? {
        host.childNode(withName: "journal_book_overlay") as? JournalBookOverlay
    }

    // MARK: - Data

    private func loadSummaries() {
        summaries = SaveService.shared.loadAllDailySummaries()
        // Open on the most recent spread. If the latest day is at
        // index N, the spread starts at the largest even index ≤ N.
        if summaries.isEmpty {
            currentLeftIndex = -1
        } else {
            let last = summaries.count - 1
            currentLeftIndex = last - (last % 2)
        }
    }

    // MARK: - Hierarchy

    private func buildHierarchy() {
        // Backdrop covers the whole screen, dims the world behind.
        backdrop = SKSpriteNode(color: Self.backdropColor, size: visibleSize)
        backdrop.zPosition = -1
        backdrop.name = "journal_book_backdrop"
        addChild(backdrop)

        // Book frame sized as a percentage of the visible viewport.
        let bookW = visibleSize.width  * 0.92
        let bookH = visibleSize.height * 0.86
        bookSize = CGSize(width: bookW, height: bookH)
        bookFrame = SKSpriteNode(color: Self.parchmentColor.withAlphaComponent(0.0), size: bookSize)
        bookFrame.zPosition = 0
        addChild(bookFrame)

        // Page geometry depends on orientation.
        if isPortrait {
            // Stacked: one wide page on top, navigation strip on bottom.
            let pageW = bookW * 0.94
            let pageH = bookH * 0.84
            pageSize = CGSize(width: pageW, height: pageH)

            leftPage = makePageSprite()
            leftPage.position = CGPoint(x: 0, y: bookH * 0.04)
            bookFrame.addChild(leftPage)

            // Right page is hidden in portrait — content stays on a
            // single scroll. We still keep the node for code paths.
            rightPage = makePageSprite()
            rightPage.isHidden = true
            bookFrame.addChild(rightPage)
        } else {
            // Two-page spread.
            let gap: CGFloat = 14
            let pageW = (bookW - gap) * 0.5 * 0.96
            let pageH = bookH * 0.86
            pageSize = CGSize(width: pageW, height: pageH)

            leftPage = makePageSprite()
            leftPage.position = CGPoint(x: -(pageW / 2 + gap / 2), y: bookH * 0.02)
            bookFrame.addChild(leftPage)

            rightPage = makePageSprite()
            rightPage.position = CGPoint(x: (pageW / 2 + gap / 2), y: bookH * 0.02)
            bookFrame.addChild(rightPage)
        }

        leftPageContent = SKNode()
        leftPage.addChild(leftPageContent)
        rightPageContent = SKNode()
        rightPage.addChild(rightPageContent)

        // Title strip above the pages.
        let title = SKLabelNode(fontNamed: Self.headerFont)
        title.text = "The Forest Chronicle"
        title.fontSize = isPortrait ? 22 : 28
        title.fontColor = SKColor(red: 0.92, green: 0.86, blue: 0.74, alpha: 1.0)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .top
        title.position = CGPoint(x: 0, y: bookH / 2 - 6)
        title.zPosition = 2
        bookFrame.addChild(title)

        dayCounter = SKLabelNode(fontNamed: Self.bodyItalic)
        dayCounter.fontSize = isPortrait ? 12 : 14
        dayCounter.fontColor = SKColor(red: 0.75, green: 0.68, blue: 0.55, alpha: 1.0)
        dayCounter.horizontalAlignmentMode = .center
        dayCounter.verticalAlignmentMode = .top
        dayCounter.position = CGPoint(x: 0, y: bookH / 2 - 38)
        dayCounter.zPosition = 2
        bookFrame.addChild(dayCounter)

        // Navigation buttons along the bottom.
        let navY = -bookH / 2 + 28
        prevButton = makeNavLabel("◀  earlier", fontSize: isPortrait ? 16 : 18)
        prevButton.name = "journal_prev"
        prevButton.position = CGPoint(x: -bookW * 0.32, y: navY)
        bookFrame.addChild(prevButton)

        nextButton = makeNavLabel("later  ▶", fontSize: isPortrait ? 16 : 18)
        nextButton.name = "journal_next"
        nextButton.position = CGPoint(x: bookW * 0.32, y: navY)
        bookFrame.addChild(nextButton)

        // Close in the top corner.
        closeButton = SKLabelNode(fontNamed: Self.headerFont)
        closeButton.text = "✕"
        closeButton.fontSize = isPortrait ? 20 : 24
        closeButton.fontColor = SKColor(red: 0.92, green: 0.86, blue: 0.74, alpha: 1.0)
        closeButton.horizontalAlignmentMode = .center
        closeButton.verticalAlignmentMode = .center
        closeButton.position = CGPoint(x: bookW / 2 - 22, y: bookH / 2 - 22)
        closeButton.zPosition = 3
        closeButton.name = "journal_close"
        bookFrame.addChild(closeButton)
    }

    private func makePageSprite() -> SKSpriteNode {
        let page = SKSpriteNode(color: Self.parchmentColor, size: pageSize)
        page.zPosition = 1
        // Subtle inner shadow via a slightly larger darker sprite behind.
        let shadow = SKSpriteNode(
            color: SKColor(red: 0.30, green: 0.16, blue: 0.05, alpha: 0.45),
            size: CGSize(width: pageSize.width + 6, height: pageSize.height + 6)
        )
        shadow.zPosition = -1
        shadow.position = CGPoint(x: 1, y: -2)
        page.addChild(shadow)
        // Decorative border.
        let borderInset: CGFloat = 9
        let border = SKShapeNode(rectOf: CGSize(
            width: pageSize.width - borderInset * 2,
            height: pageSize.height - borderInset * 2
        ))
        border.strokeColor = SKColor(red: 0.55, green: 0.34, blue: 0.18, alpha: 0.55)
        border.lineWidth = 1.5
        border.fillColor = .clear
        border.zPosition = 0.5
        page.addChild(border)
        return page
    }

    private func makeNavLabel(_ text: String, fontSize: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: Self.bodyFont)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = SKColor(red: 0.92, green: 0.86, blue: 0.74, alpha: 1.0)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 3
        return label
    }

    // MARK: - Camera Pin

    private func runPinFollowAction() {
        let pinAction = SKAction.run { [weak self] in
            guard let self, let cam = self.pinnedCamera else { return }
            self.position = cam.position
        }
        let wait = SKAction.wait(forDuration: 1.0 / 60.0)
        let loop = SKAction.repeatForever(SKAction.sequence([pinAction, wait]))
        run(loop, withKey: "journal_pin_follow")
    }

    // MARK: - Rendering

    private func renderCurrentSpread() {
        leftPageContent.removeAllChildren()
        rightPageContent.removeAllChildren()

        guard !summaries.isEmpty else {
            renderEmptyState()
            updateNavVisibility()
            return
        }

        // Left page = summary at currentLeftIndex
        if currentLeftIndex >= 0, currentLeftIndex < summaries.count {
            renderSummary(summaries[currentLeftIndex], onto: leftPageContent)
        }

        // Right page = summary at currentLeftIndex + 1 (if it exists)
        if !isPortrait {
            let rightIdx = currentLeftIndex + 1
            if rightIdx >= 0, rightIdx < summaries.count {
                renderSummary(summaries[rightIdx], onto: rightPageContent)
            } else {
                // Empty right page — show a small flourish.
                let mark = SKLabelNode(fontNamed: Self.bodyItalic)
                mark.text = "—"
                mark.fontSize = 28
                mark.fontColor = Self.dimInkColor
                mark.horizontalAlignmentMode = .center
                mark.verticalAlignmentMode = .center
                mark.position = .zero
                rightPageContent.addChild(mark)
            }
        }

        // Day counter
        let total = summaries.count
        if total == 0 {
            dayCounter.text = ""
        } else {
            let leftDay = currentLeftIndex >= 0 ? summaries[currentLeftIndex].dayCount : 0
            if isPortrait {
                dayCounter.text = "Day \(leftDay) of \(summaries.last!.dayCount)"
            } else {
                let rightIdx = currentLeftIndex + 1
                let rightDay = (rightIdx < summaries.count) ? summaries[rightIdx].dayCount : leftDay
                dayCounter.text = (leftDay == rightDay)
                    ? "Day \(leftDay) of \(summaries.last!.dayCount)"
                    : "Days \(leftDay)–\(rightDay) of \(summaries.last!.dayCount)"
            }
        }

        updateNavVisibility()
    }

    private func renderEmptyState() {
        let label = SKLabelNode(fontNamed: Self.bodyItalic)
        label.text = "The book has no pages yet."
        label.fontSize = isPortrait ? 14 : 16
        label.fontColor = Self.dimInkColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = .zero
        leftPageContent.addChild(label)

        let hint = SKLabelNode(fontNamed: Self.bodyItalic)
        hint.text = "Each dawn writes a new chronicle."
        hint.fontSize = isPortrait ? 12 : 13
        hint.fontColor = Self.dimInkColor
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.position = CGPoint(x: 0, y: -22)
        leftPageContent.addChild(hint)

        dayCounter.text = ""
    }

    /// Render one DailySummary into a page-content node, top-aligned.
    private func renderSummary(_ summary: DailySummary, onto host: SKNode) {
        let pageW = pageSize.width
        let pageH = pageSize.height
        let leftEdge   = -pageW / 2 + 22
        let topEdge    = pageH / 2 - 24

        // Day header — "Day N" in big serif.
        let day = SKLabelNode(fontNamed: Self.headerFont)
        day.text = "Day \(summary.dayCount)"
        day.fontSize = isPortrait ? 22 : 26
        day.fontColor = Self.inkColor
        day.horizontalAlignmentMode = .left
        day.verticalAlignmentMode = .top
        day.position = CGPoint(x: leftEdge, y: topEdge)
        host.addChild(day)

        // Headline strip — small italic counts under the date.
        let headlineY = topEdge - day.fontSize - 4
        let headlineText = formatHeadlineStrip(summary.headlines)
        if !headlineText.isEmpty {
            let headlineLabel = SKLabelNode(fontNamed: Self.bodyItalic)
            headlineLabel.text = headlineText
            headlineLabel.fontSize = isPortrait ? 11 : 12
            headlineLabel.fontColor = Self.dimInkColor
            headlineLabel.horizontalAlignmentMode = .left
            headlineLabel.verticalAlignmentMode = .top
            headlineLabel.position = CGPoint(x: leftEdge, y: headlineY)
            host.addChild(headlineLabel)
        }

        // Body — sectioned paragraphs.
        var cursorY = headlineY - 22
        let bodyFontSize: CGFloat = isPortrait ? 12 : 13
        let lineHeight: CGFloat = bodyFontSize + 4
        let wrapWidth = pageW - 44

        // Opening
        cursorY = appendParagraph(
            summary.openingLine,
            italic: true,
            fontSize: bodyFontSize,
            color: Self.inkColor,
            x: leftEdge, startY: cursorY,
            wrapWidth: wrapWidth, lineHeight: lineHeight,
            host: host
        )
        cursorY -= 8

        // Forest
        cursorY = appendSectionHeader("Forest", color: Self.inkColor,
                                      x: leftEdge, y: cursorY, host: host)
        cursorY = appendParagraph(
            summary.forestSection, italic: false,
            fontSize: bodyFontSize, color: Self.inkColor,
            x: leftEdge, startY: cursorY,
            wrapWidth: wrapWidth, lineHeight: lineHeight, host: host
        )
        cursorY -= 6

        // Mines
        cursorY = appendSectionHeader("Mines", color: Self.inkColor,
                                      x: leftEdge, y: cursorY, host: host)
        cursorY = appendParagraph(
            summary.minesSection, italic: false,
            fontSize: bodyFontSize, color: Self.inkColor,
            x: leftEdge, startY: cursorY,
            wrapWidth: wrapWidth, lineHeight: lineHeight, host: host
        )
        cursorY -= 6

        // Shop
        cursorY = appendSectionHeader("The Shop", color: Self.inkColor,
                                      x: leftEdge, y: cursorY, host: host)
        cursorY = appendParagraph(
            summary.shopSection, italic: false,
            fontSize: bodyFontSize, color: Self.inkColor,
            x: leftEdge, startY: cursorY,
            wrapWidth: wrapWidth, lineHeight: lineHeight, host: host
        )
        cursorY -= 6

        // Social
        cursorY = appendSectionHeader("Among Neighbors", color: Self.inkColor,
                                      x: leftEdge, y: cursorY, host: host)
        cursorY = appendParagraph(
            summary.socialSection, italic: false,
            fontSize: bodyFontSize, color: Self.inkColor,
            x: leftEdge, startY: cursorY,
            wrapWidth: wrapWidth, lineHeight: lineHeight, host: host
        )
        cursorY -= 8

        // Closing
        _ = appendParagraph(
            summary.closingLine, italic: true,
            fontSize: bodyFontSize, color: Self.dimInkColor,
            x: leftEdge, startY: cursorY,
            wrapWidth: wrapWidth, lineHeight: lineHeight, host: host
        )
    }

    private func formatHeadlineStrip(_ h: DailyChronicleHeadlines) -> String {
        var bits: [String] = []
        if h.drinksServed > 0 { bits.append("\(h.drinksServed) cup\(h.drinksServed == 1 ? "" : "s")") }
        if h.gemsCollected > 0 { bits.append("\(h.gemsCollected) gem\(h.gemsCollected == 1 ? "" : "s")") }
        if h.liberations > 0 { bits.append("\(h.liberations) let go") }
        if h.rankChanges > 0 { bits.append("\(h.rankChanges) rank chang\(h.rankChanges == 1 ? "e" : "es")") }
        if h.trashCleanedCount > 0 { bits.append("\(h.trashCleanedCount) tidied") }
        let foragedTotal = h.foragedByIngredient.values.reduce(0, +)
        if foragedTotal > 0 { bits.append("\(foragedTotal) foraged") }
        return bits.joined(separator: " · ")
    }

    /// Append a single section header line. Returns the y-position
    /// directly under the header (where the next paragraph should start).
    private func appendSectionHeader(_ text: String, color: SKColor,
                                     x: CGFloat, y: CGFloat, host: SKNode) -> CGFloat {
        let label = SKLabelNode(fontNamed: Self.headerFont)
        label.text = text
        label.fontSize = isPortrait ? 13 : 14
        label.fontColor = color
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: x, y: y)
        host.addChild(label)
        return y - label.fontSize - 4
    }

    /// Wrap-and-append a paragraph. Returns the y-position below the
    /// last laid-out line.
    private func appendParagraph(
        _ text: String,
        italic: Bool,
        fontSize: CGFloat,
        color: SKColor,
        x: CGFloat, startY: CGFloat,
        wrapWidth: CGFloat, lineHeight: CGFloat,
        host: SKNode
    ) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return startY }

        let fontName = italic ? Self.bodyItalic : Self.bodyFont
        let lines = wrapText(trimmed, fontName: fontName, fontSize: fontSize, maxWidth: wrapWidth)
        var y = startY
        for line in lines {
            let label = SKLabelNode(fontNamed: fontName)
            label.text = line
            label.fontSize = fontSize
            label.fontColor = color
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode = .top
            label.position = CGPoint(x: x, y: y)
            host.addChild(label)
            y -= lineHeight
        }
        return y
    }

    /// Greedy word-wrap using cached SKLabelNode width measurement.
    private func wrapText(_ text: String, fontName: String, fontSize: CGFloat,
                          maxWidth: CGFloat) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let measure = SKLabelNode(fontNamed: fontName)
        measure.fontSize = fontSize

        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            measure.text = candidate
            if measure.frame.width <= maxWidth {
                current = candidate
            } else {
                if !current.isEmpty {
                    lines.append(current)
                }
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: - Navigation

    private func updateNavVisibility() {
        let step = isPortrait ? 1 : 2
        prevButton.alpha = (currentLeftIndex - step >= 0) ? 1.0 : 0.25
        nextButton.alpha = (currentLeftIndex + step < summaries.count) ? 1.0 : 0.25
    }

    private func flipBackward() {
        let step = isPortrait ? 1 : 2
        let newIndex = currentLeftIndex - step
        guard newIndex >= 0 else { return }
        currentLeftIndex = newIndex
        renderCurrentSpread()
    }

    private func flipForward() {
        let step = isPortrait ? 1 : 2
        let newIndex = currentLeftIndex + step
        guard newIndex < summaries.count else { return }
        currentLeftIndex = newIndex
        renderCurrentSpread()
    }

    // MARK: - Public Input

    /// Walk the ancestor chain at `point` and route to a button if hit.
    /// Returns true if the tap was consumed by the overlay.
    @discardableResult
    func handleTap(at point: CGPoint) -> Bool {
        let local = convert(point, from: parent ?? self)
        let hits = nodes(at: local)
        for hit in hits {
            var cursor: SKNode? = hit
            while let c = cursor {
                switch c.name {
                case "journal_close":
                    dismiss()
                    return true
                case "journal_prev":
                    flipBackward()
                    return true
                case "journal_next":
                    flipForward()
                    return true
                default:
                    cursor = c.parent
                }
            }
        }
        // Tap on the backdrop closes too.
        if hits.contains(where: { $0 === backdrop }) {
            dismiss()
            return true
        }
        return false
    }

    /// Public dismiss with a quick fade-out.
    func dismiss() {
        run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Open helper

    /// Build and parent an overlay onto `host` (the scene). Returns the
    /// new instance. If one is already open, it's removed first.
    @discardableResult
    static func present(in host: SKScene, camera: SKCameraNode?) -> JournalBookOverlay {
        host.childNode(withName: "journal_book_overlay")?.removeFromParent()

        // Compute visible scene-space size, mirroring NPCDebugMenu.
        let visible: CGSize
        if let view = host.view {
            let topLeft = host.convertPoint(fromView: .zero)
            let bottomRight = host.convertPoint(fromView: CGPoint(
                x: view.bounds.width, y: view.bounds.height
            ))
            visible = CGSize(
                width: abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y)
            )
        } else {
            visible = host.size
        }

        let overlay = JournalBookOverlay(visibleSize: visible, camera: camera)
        overlay.alpha = 0
        overlay.position = camera?.position ?? .zero
        host.addChild(overlay)
        overlay.run(SKAction.fadeIn(withDuration: 0.22))
        return overlay
    }
}
